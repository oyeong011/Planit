import Foundation
import Testing
import CalenShared

// MARK: - GoogleCalendarClientTests
//
// URLProtocol 기반 mock으로 `GoogleCalendarClient`의 request 빌드/응답 파싱/에러 매핑을 검증.
// 외부 네트워크 접근 0건.
//
// 커버리지 6개:
//   1. listEvents DTO 파싱 (timed + all-day 혼합)
//   2. cancelled 상태 skip
//   3. insertEvent — URL / method / body(JSON) 검증
//   4. patchEvent — PATCH verb + partial body 검증
//   5. deleteEvent — 204 No Content 반환 시 성공
//   6. 401 → unauthorized 매핑

// MARK: - MockURLProtocol

/// URLSession에 주입해 모든 HTTP 요청을 가로채는 프로토콜.
/// 테스트 case 별 `responder`를 set → GoogleCalendarClient가 보낸 URLRequest를
/// 캡처하고 원하는 응답을 반환.
final class MockURLProtocol: URLProtocol {
    /// 전체 테스트 스위트 간 공유되는 큐. `setUp`으로 push, `pop` 으로 consume.
    /// 각 테스트가 순차적으로 request 1개씩 소비한다.
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?
    /// 마지막 들어온 요청을 기록 (body assert 용).
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    static func reset() {
        responder = nil
        capturedRequests = []
        capturedBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol은 httpBodyStream으로 들어오는 경우가 있으므로 둘 다 지원.
        let bodyData: Data = {
            if let data = request.httpBody { return data }
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var out = Data()
                let bufSize = 1024
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
                defer { buf.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buf, maxLength: bufSize)
                    if read <= 0 { break }
                    out.append(buf, count: read)
                }
                return out
            }
            return Data()
        }()
        Self.capturedRequests.append(request)
        Self.capturedBodies.append(bodyData)

        guard let responder = Self.responder else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(domain: "MockURLProtocol", code: -1)
            )
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - StubAuth

final class StubAuth: CalendarAuthProviding, @unchecked Sendable {
    var token: String?
    var refreshCalls = 0

    init(token: String? = "stub-token") {
        self.token = token
    }

    var currentAccessToken: String? {
        get async { token }
    }

    func refreshIfNeeded() async throws {
        refreshCalls += 1
    }
}

// MARK: - Helpers

private func makeHTTPResponse(
    url: URL,
    status: Int,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

private func iso(_ s: String) -> Date {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime]
    return fmt.date(from: s) ?? Date(timeIntervalSince1970: 0)
}

// MARK: - Tests

@Suite("GoogleCalendarClient", .serialized)
struct GoogleCalendarClientTests {

    // MARK: 1

    @Test func listEvents_parses_DTO_into_CalendarEvents() async throws {
        MockURLProtocol.reset()

        // timed + all-day 혼합 응답 JSON (실제 Google API 스키마 서브셋)
        let listJSON = """
        {
          "items": [
            {
              "id": "evt-timed-1",
              "etag": "\\"etag-1\\"",
              "status": "confirmed",
              "summary": "팀 스탠드업",
              "location": "본사",
              "description": "OKR 공유",
              "colorId": "9",
              "updated": "2026-04-19T03:00:00Z",
              "start": { "dateTime": "2026-04-19T09:00:00Z" },
              "end":   { "dateTime": "2026-04-19T09:30:00Z" }
            },
            {
              "id": "evt-allday-1",
              "etag": "\\"etag-2\\"",
              "status": "confirmed",
              "summary": "오프사이트",
              "colorId": "3",
              "start": { "date": "2026-04-20" },
              "end":   { "date": "2026-04-22" }
            }
          ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.responder = { req in
            #expect(req.url?.host == "www.googleapis.com")
            #expect(req.url?.path == "/calendar/v3/calendars/primary/events")
            // 필수 쿼리 파라미터
            let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
                .queryItems ?? []
            let names = Set(q.map(\.name))
            #expect(names.contains("timeMin"))
            #expect(names.contains("timeMax"))
            #expect(names.contains("singleEvents"))
            #expect(names.contains("orderBy"))
            // auth
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer stub-token")

            return (makeHTTPResponse(url: req.url!, status: 200), listJSON)
        }

        let client = GoogleCalendarClient(
            authProvider: StubAuth(token: "stub-token"),
            transport: MockURLProtocol.self
        )
        let interval = DateInterval(
            start: iso("2026-04-19T00:00:00Z"),
            end:   iso("2026-04-30T00:00:00Z")
        )
        let events = try await client.listEvents(calendarId: "primary", in: interval)

        #expect(events.count == 2)

        let timed = events.first(where: { $0.id == "evt-timed-1" })
        #expect(timed != nil)
        #expect(timed?.title == "팀 스탠드업")
        #expect(timed?.location == "본사")
        #expect(timed?.description == "OKR 공유")
        #expect(timed?.isAllDay == false)
        // colorId 9 = Blueberry → 미팅 blue (#3B82F6)
        #expect(timed?.colorHex == "#3B82F6")
        #expect(timed?.calendarId == "primary")
        #expect(timed?.source == .google)
        #expect(timed?.etag == "\"etag-1\"")
        #expect(timed?.startDate == iso("2026-04-19T09:00:00Z"))
        #expect(timed?.endDate == iso("2026-04-19T09:30:00Z"))

        let allDay = events.first(where: { $0.id == "evt-allday-1" })
        #expect(allDay != nil)
        #expect(allDay?.isAllDay == true)
        // colorId 3 = Grape → 개인 violet
        #expect(allDay?.colorHex == "#9A5CE8")
        // Phase B HIGH #3 fix: 내부 모델도 exclusive endDate로 통일.
        // Google end=2026-04-22 (exclusive, 다음 날 00:00) → 내부 그대로 저장.
        // UI는 `endDate > dayStart` 형태로 exclusive 해석 중이라 일관됨.
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        let startComps = cal.dateComponents([.year, .month, .day], from: allDay!.startDate)
        #expect(startComps.year == 2026 && startComps.month == 4 && startComps.day == 20)
        let endComps = cal.dateComponents([.year, .month, .day], from: allDay!.endDate)
        #expect(endComps.year == 2026 && endComps.month == 4 && endComps.day == 22)
    }

    // MARK: 2

    @Test func listEvents_skips_cancelled_status() async throws {
        MockURLProtocol.reset()

        let json = """
        {
          "items": [
            {
              "id": "evt-ok",
              "status": "confirmed",
              "summary": "살아있는 이벤트",
              "start": { "dateTime": "2026-04-19T09:00:00Z" },
              "end":   { "dateTime": "2026-04-19T10:00:00Z" }
            },
            {
              "id": "evt-cancelled",
              "status": "cancelled",
              "summary": "취소됨",
              "start": { "dateTime": "2026-04-19T11:00:00Z" },
              "end":   { "dateTime": "2026-04-19T12:00:00Z" }
            }
          ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.responder = { req in
            (makeHTTPResponse(url: req.url!, status: 200), json)
        }

        let client = GoogleCalendarClient(
            authProvider: StubAuth(token: "t"),
            transport: MockURLProtocol.self
        )
        let interval = DateInterval(
            start: iso("2026-04-19T00:00:00Z"),
            end:   iso("2026-04-20T00:00:00Z")
        )
        let events = try await client.listEvents(calendarId: "primary", in: interval)
        #expect(events.count == 1)
        #expect(events.first?.id == "evt-ok")
    }

    // MARK: 3

    @Test func insertEvent_builds_correct_request_body() async throws {
        MockURLProtocol.reset()

        // Google이 반환할 event (id 발급된 상태)
        let respJSON = """
        {
          "id": "new-id-xyz",
          "etag": "\\"etag-new\\"",
          "status": "confirmed",
          "summary": "새 이벤트",
          "colorId": "11",
          "start": { "dateTime": "2026-04-19T14:00:00Z" },
          "end":   { "dateTime": "2026-04-19T15:00:00Z" }
        }
        """.data(using: .utf8)!

        MockURLProtocol.responder = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/calendar/v3/calendars/primary/events")
            #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer stub-token")
            return (makeHTTPResponse(url: req.url!, status: 200), respJSON)
        }

        let client = GoogleCalendarClient(
            authProvider: StubAuth(token: "stub-token"),
            transport: MockURLProtocol.self
        )

        let draft = CalendarEventDraft(
            calendarId: "primary",
            title: "새 이벤트",
            startDate: iso("2026-04-19T14:00:00Z"),
            endDate: iso("2026-04-19T15:00:00Z"),
            isAllDay: false,
            location: "Zoom",
            description: "설명",
            colorHex: "#F56691"  // → colorId 11 (Tomato)
        )

        let result = try await client.insertEvent(calendarId: "primary", draft: draft)
        #expect(result.id == "new-id-xyz")
        #expect(result.title == "새 이벤트")
        #expect(result.colorHex == "#F56691")
        #expect(result.etag == "\"etag-new\"")

        // Body 검증
        #expect(MockURLProtocol.capturedBodies.count == 1)
        let body = MockURLProtocol.capturedBodies[0]
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(parsed?["summary"] as? String == "새 이벤트")
        #expect(parsed?["location"] as? String == "Zoom")
        #expect(parsed?["description"] as? String == "설명")
        #expect(parsed?["colorId"] as? String == "11")
        let start = parsed?["start"] as? [String: Any]
        #expect((start?["dateTime"] as? String)?.isEmpty == false)
        // all-day가 아니므로 `date` 키는 body에 포함되지 않아야 한다 (optional nil → 미전송)
        #expect(start?["date"] == nil)
    }

    // MARK: 4

    @Test func patchEvent_uses_PATCH_verb_and_partial_body() async throws {
        MockURLProtocol.reset()

        let respJSON = """
        {
          "id": "evt-123",
          "etag": "\\"etag-updated\\"",
          "status": "confirmed",
          "summary": "수정됨",
          "start": { "dateTime": "2026-04-19T10:00:00Z" },
          "end":   { "dateTime": "2026-04-19T11:00:00Z" }
        }
        """.data(using: .utf8)!

        MockURLProtocol.responder = { req in
            #expect(req.httpMethod == "PATCH")
            #expect(req.url?.path == "/calendar/v3/calendars/primary/events/evt-123")
            return (makeHTTPResponse(url: req.url!, status: 200), respJSON)
        }

        let client = GoogleCalendarClient(
            authProvider: StubAuth(token: "stub-token"),
            transport: MockURLProtocol.self
        )
        let original = CalendarEvent(
            id: "evt-123",
            calendarId: "primary",
            title: "수정됨",
            startDate: iso("2026-04-19T10:00:00Z"),
            endDate: iso("2026-04-19T11:00:00Z"),
            isAllDay: false,
            colorHex: "#3B82F6"
        )
        let updated = try await client.patchEvent(original)
        #expect(updated.id == "evt-123")
        #expect(updated.title == "수정됨")
        #expect(updated.etag == "\"etag-updated\"")

        // body: summary 존재, start/end dateTime 존재
        let body = MockURLProtocol.capturedBodies[0]
        let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(parsed?["summary"] as? String == "수정됨")
        let start = parsed?["start"] as? [String: Any]
        #expect((start?["dateTime"] as? String)?.isEmpty == false)
    }

    // MARK: 5

    @Test func deleteEvent_returns_on_204() async throws {
        MockURLProtocol.reset()

        MockURLProtocol.responder = { req in
            #expect(req.httpMethod == "DELETE")
            #expect(req.url?.path == "/calendar/v3/calendars/primary/events/evt-del")
            return (makeHTTPResponse(url: req.url!, status: 204), Data())
        }

        let client = GoogleCalendarClient(
            authProvider: StubAuth(token: "t"),
            transport: MockURLProtocol.self
        )
        let target = CalendarEvent(
            id: "evt-del",
            calendarId: "primary",
            title: "삭제 대상",
            startDate: iso("2026-04-19T10:00:00Z"),
            endDate: iso("2026-04-19T11:00:00Z")
        )
        try await client.deleteEvent(target)  // throw 없어야 함
    }

    // MARK: 6

    @Test func authError_401_maps_to_unauthorized() async throws {
        MockURLProtocol.reset()

        MockURLProtocol.responder = { req in
            (makeHTTPResponse(url: req.url!, status: 401), Data())
        }

        let client = GoogleCalendarClient(
            authProvider: StubAuth(token: "invalid"),
            transport: MockURLProtocol.self
        )
        let interval = DateInterval(
            start: iso("2026-04-19T00:00:00Z"),
            end:   iso("2026-04-20T00:00:00Z")
        )
        await #expect(throws: GoogleCalendarClient.GoogleCalendarClientError.unauthorized) {
            _ = try await client.listEvents(calendarId: "primary", in: interval)
        }
    }
}
