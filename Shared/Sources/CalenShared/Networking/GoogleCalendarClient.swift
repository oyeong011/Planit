import Foundation

// MARK: - GoogleCalendarClient
//
// Phase B M3: macOS의 기존 `Planit/Services/GoogleCalendarService.swift`를 건드리지 않고,
// Shared 레이어에 **새로** 추출한 순수 REST 클라이언트.
//
// 책임:
//   1. URL 빌드 + 쿼리 파라미터 + RFC3339 직렬화
//   2. Google Calendar v3 DTO encode/decode
//   3. list/insert/patch/delete — 순수 기능 단위
//   4. Google colorId (1~11) ↔ Calen 앱 6색 팔레트 매핑
//
// 비책임:
//   - 토큰 저장/갱신 (CalendarAuthProviding가 담당)
//   - 캐시/옵티미스틱 UI (호출자 Repository가 담당)
//   - 캘린더 목록 조회 (이번 Phase에서는 primary 기준, 다중 캘린더는 향후)
//
// 테스트: init에 `transport: URLProtocol.Type?`을 주입하면 URLSessionConfiguration에
// 해당 URLProtocol이 끼워져 모든 요청을 가로챌 수 있다 (GoogleCalendarClientTests에서 사용).
//
// codex 권고 반영:
//   - all-day endDate는 Google이 exclusive → 내부 CalendarEvent는 inclusive로 저장(마지막 날 00:00 유지)
//   - status == "cancelled" → skip
//   - recurring instance는 singleEvents=true로 전개되므로 "이 인스턴스만" 정책 자동
//   - colorId → colorHex 매핑 테이블 명시

public actor GoogleCalendarClient {

    // MARK: - Types

    /// Google Calendar REST 요청 실패 원인. HTTP 상태 → semantic 에러 매핑.
    public enum GoogleCalendarClientError: Error, Equatable, Sendable {
        case unauthorized            // 401
        case forbidden               // 403
        case notFound                // 404
        case conflict                // 409
        case preconditionFailed      // 412 (etag mismatch)
        case rateLimited(retryAfter: TimeInterval?) // 429
        case serverError(statusCode: Int)           // 5xx
        case invalidResponse
        case decoding(String)
        case encoding(String)
        case noAccessToken
        case network(String)

        public static func == (
            lhs: GoogleCalendarClientError, rhs: GoogleCalendarClientError
        ) -> Bool {
            switch (lhs, rhs) {
            case (.unauthorized, .unauthorized),
                 (.forbidden, .forbidden),
                 (.notFound, .notFound),
                 (.conflict, .conflict),
                 (.preconditionFailed, .preconditionFailed),
                 (.invalidResponse, .invalidResponse),
                 (.noAccessToken, .noAccessToken):
                return true
            case let (.rateLimited(a), .rateLimited(b)):
                return a == b
            case let (.serverError(a), .serverError(b)):
                return a == b
            case let (.decoding(a), .decoding(b)):
                return a == b
            case let (.encoding(a), .encoding(b)):
                return a == b
            case let (.network(a), .network(b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Dependencies

    private let authProvider: CalendarAuthProviding
    private let session: URLSession

    // MARK: - Init

    /// - Parameters:
    ///   - authProvider: bearer 토큰을 제공할 OAuth 제공자 (iOS/macOS auth manager)
    ///   - transport: 테스트용 URLProtocol 타입. nil이면 default ephemeral session 사용.
    public init(
        authProvider: CalendarAuthProviding,
        transport: URLProtocol.Type? = nil
    ) {
        self.authProvider = authProvider
        if let transport {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [transport]
            // URLSession은 Foundation URLProtocol.registerClass와 무관하게 config.protocolClasses를
            // 우선 처리한다 (사용자 프로토콜 → default handlers 순). 테스트에서 이 경로로 모든 요청을
            // 가로채 fake response를 반환한다.
            self.session = URLSession(configuration: config)
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// 지정 캘린더에서 주어진 구간과 겹치는 이벤트 목록을 반환.
    /// - `singleEvents=true`: 반복 이벤트를 인스턴스로 전개 (codex 정책 9 — 이 인스턴스만 편집).
    /// - `cancelled` 이벤트는 skip.
    /// - pagination(`nextPageToken`)을 내부적으로 모두 처리.
    public func listEvents(
        calendarId: String = "primary",
        in interval: DateInterval
    ) async throws -> [CalendarEvent] {
        let token = try await accessToken()
        let encodedCal = Self.encodePathSegment(calendarId)

        let timeMin = Self.rfc3339UTC.string(from: interval.start)
        let timeMax = Self.rfc3339UTC.string(from: interval.end)

        var pageToken: String? = nil
        var aggregated: [CalendarEvent] = []

        repeat {
            var comps = URLComponents(string: "\(Self.baseURL)/calendars/\(encodedCal)/events")!
            var items: [URLQueryItem] = [
                URLQueryItem(name: "timeMin", value: timeMin),
                URLQueryItem(name: "timeMax", value: timeMax),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
            ]
            if let pt = pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pt))
            }
            comps.queryItems = items

            guard let url = comps.url else {
                throw GoogleCalendarClientError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await perform(request)
            try Self.validate(response)

            let page: GoogleEventListDTO
            do {
                page = try Self.decoder.decode(GoogleEventListDTO.self, from: data)
            } catch {
                throw GoogleCalendarClientError.decoding("\(error)")
            }

            for dto in page.items ?? [] {
                if dto.status == "cancelled" { continue }
                if let ev = Self.mapToCalendarEvent(dto, calendarId: calendarId) {
                    aggregated.append(ev)
                }
            }

            pageToken = page.nextPageToken
        } while pageToken != nil

        return aggregated
    }

    /// 이벤트 생성. draft의 start/end가 all-day일 때 Google 규칙(endDate exclusive)으로 +1일 보정.
    public func insertEvent(
        calendarId: String = "primary",
        draft: CalendarEventDraft
    ) async throws -> CalendarEvent {
        let token = try await accessToken()
        let encodedCal = Self.encodePathSegment(calendarId)

        guard let url = URL(string: "\(Self.baseURL)/calendars/\(encodedCal)/events") else {
            throw GoogleCalendarClientError.invalidResponse
        }

        let body = Self.makeEventBody(
            title: draft.title,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            location: draft.location,
            description: draft.description,
            colorHex: draft.colorHex
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try Self.encoder.encode(body)
        } catch {
            throw GoogleCalendarClientError.encoding("\(error)")
        }

        let (data, response) = try await perform(request)
        try Self.validate(response)

        do {
            let dto = try Self.decoder.decode(GoogleEventDTO.self, from: data)
            guard let ev = Self.mapToCalendarEvent(dto, calendarId: calendarId) else {
                throw GoogleCalendarClientError.decoding("insert: DTO → CalendarEvent 매핑 실패")
            }
            return ev
        } catch let err as GoogleCalendarClientError {
            throw err
        } catch {
            throw GoogleCalendarClientError.decoding("\(error)")
        }
    }

    /// 기존 이벤트 PATCH. event.id / event.calendarId 기반.
    public func patchEvent(_ event: CalendarEvent) async throws -> CalendarEvent {
        let token = try await accessToken()
        let encodedCal = Self.encodePathSegment(event.calendarId)
        let encodedId = Self.encodePathSegment(event.id)

        guard let url = URL(
            string: "\(Self.baseURL)/calendars/\(encodedCal)/events/\(encodedId)"
        ) else {
            throw GoogleCalendarClientError.invalidResponse
        }

        let body = Self.makeEventBody(
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            description: event.description,
            colorHex: event.colorHex
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Phase B HIGH #4 fix: lost update 방지 — etag 있으면 If-Match conditional update.
        // 412 Precondition Failed 시 `GoogleCalendarClientError.preconditionFailed`로 매핑되어
        // 상위 layer가 refetch + 사용자 diff/rollback UI를 구동하도록 신호.
        if let etag = event.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        do {
            request.httpBody = try Self.encoder.encode(body)
        } catch {
            throw GoogleCalendarClientError.encoding("\(error)")
        }

        let (data, response) = try await perform(request)
        try Self.validate(response)

        do {
            let dto = try Self.decoder.decode(GoogleEventDTO.self, from: data)
            guard let ev = Self.mapToCalendarEvent(dto, calendarId: event.calendarId) else {
                throw GoogleCalendarClientError.decoding("patch: DTO → CalendarEvent 매핑 실패")
            }
            return ev
        } catch let err as GoogleCalendarClientError {
            throw err
        } catch {
            throw GoogleCalendarClientError.decoding("\(error)")
        }
    }

    /// 이벤트 DELETE. 204 / 200 모두 성공 처리. 404는 notFound throw.
    public func deleteEvent(_ event: CalendarEvent) async throws {
        let token = try await accessToken()
        let encodedCal = Self.encodePathSegment(event.calendarId)
        let encodedId = Self.encodePathSegment(event.id)

        guard let url = URL(
            string: "\(Self.baseURL)/calendars/\(encodedCal)/events/\(encodedId)"
        ) else {
            throw GoogleCalendarClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Phase B HIGH #4 fix: DELETE도 etag 기반 conditional — 외부에서 수정된 이벤트를
        // 모르고 삭제하는 lost update 시나리오 방지.
        if let etag = event.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }

        let (_, response) = try await perform(request)
        try Self.validate(response)
    }

    // MARK: - Internal: transport

    /// URLSession 호출을 래핑해 network level error를 매핑.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw GoogleCalendarClientError.network("\(error.localizedDescription)")
        }
    }

    private func accessToken() async throws -> String {
        try? await authProvider.refreshIfNeeded()
        guard let token = await authProvider.currentAccessToken, !token.isEmpty else {
            throw GoogleCalendarClientError.noAccessToken
        }
        return token
    }

    // MARK: - Static config

    static let baseURL = "https://www.googleapis.com/calendar/v3"

    /// Google Calendar API는 RFC3339 UTC (`yyyy-MM-dd'T'HH:mm:ssZ`). Zulu 형식을 명시적으로 요구.
    static let rfc3339UTC: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    /// RFC3339 (local + milliseconds 허용). DTO 파싱용.
    static let rfc3339Flexible: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    /// all-day `date`용 — **parsing (decode) 전용**, UTC. Google API 응답은 UTC로 옴.
    static let allDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    /// all-day **encoding(write) 전용** — 로컬 타임존 기준 year-month-day.
    /// Phase B MEDIUM #7 fix: 사용자가 KST 자정 `Date`를 만들면 그 Date는 UTC로는 전날 15:00이다.
    /// UTC formatter로 찍으면 전날 문자열이 나와 off-by-one. current timezone 기준으로 인코딩해야 정확.
    static let localAllDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: - HTTP validation

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarClientError.invalidResponse
        }
        let code = http.statusCode
        if (200...299).contains(code) { return }

        switch code {
        case 401:
            throw GoogleCalendarClientError.unauthorized
        case 403:
            throw GoogleCalendarClientError.forbidden
        case 404:
            throw GoogleCalendarClientError.notFound
        case 409:
            throw GoogleCalendarClientError.conflict
        case 412:
            throw GoogleCalendarClientError.preconditionFailed
        case 429:
            let retry: TimeInterval?
            if let s = http.value(forHTTPHeaderField: "Retry-After"),
               let v = TimeInterval(s) {
                retry = v
            } else {
                retry = nil
            }
            throw GoogleCalendarClientError.rateLimited(retryAfter: retry)
        case 500...599:
            throw GoogleCalendarClientError.serverError(statusCode: code)
        default:
            throw GoogleCalendarClientError.serverError(statusCode: code)
        }
    }

    // MARK: - Helpers

    /// URL path segment percent-encoding. `@`, `:`, `/` 모두 인코딩.
    static func encodePathSegment(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: "/:@")))
            ?? s
    }

    // MARK: - DTO ↔ CalendarEvent mapping

    /// Google colorId (1~11) → Calen 6색 팔레트 hex.
    /// 매핑은 색상학적으로 가장 가까운 카테고리에 맞춘다.
    ///   1 Lavender      → 개인 violet (#9A5CE8)
    ///   2 Sage          → 운동 green  (#40C786)
    ///   3 Grape         → 개인 violet (#9A5CE8)
    ///   4 Flamingo      → 업무 pink   (#F56691)
    ///   5 Banana        → 식사 yellow (#FAC430)
    ///   6 Tangerine     → 식사 yellow (#FAC430)
    ///   7 Peacock       → 미팅 blue   (#3B82F6)
    ///   8 Graphite      → 일반 gray   (#909094)
    ///   9 Blueberry     → 미팅 blue   (#3B82F6)
    ///  10 Basil         → 운동 green  (#40C786)
    ///  11 Tomato        → 업무 pink   (#F56691)
    static let colorIdToHex: [String: String] = [
        "1":  "#9A5CE8",
        "2":  "#40C786",
        "3":  "#9A5CE8",
        "4":  "#F56691",
        "5":  "#FAC430",
        "6":  "#FAC430",
        "7":  "#3B82F6",
        "8":  "#909094",
        "9":  "#3B82F6",
        "10": "#40C786",
        "11": "#F56691",
    ]

    /// Calen hex → 가장 가까운 Google colorId (insert/patch 시 사용).
    static let hexToColorId: [String: String] = [
        "#F56691": "11", // Tomato
        "#3B82F6": "9",  // Blueberry
        "#FAC430": "5",  // Banana
        "#40C786": "10", // Basil
        "#9A5CE8": "3",  // Grape
        "#909094": "8",  // Graphite
    ]

    static let defaultColorHex = "#3366CC"

    /// DTO → CalendarEvent. 실패 시 nil.
    static func mapToCalendarEvent(_ dto: GoogleEventDTO, calendarId: String) -> CalendarEvent? {
        let isAllDay = (dto.start?.date != nil) && (dto.start?.dateTime == nil)

        let startDate: Date
        let endDate: Date

        if isAllDay {
            guard let startStr = dto.start?.date,
                  let endStr = dto.end?.date,
                  let start = allDayFormatter.date(from: startStr),
                  let endExclusive = allDayFormatter.date(from: endStr) else {
                return nil
            }
            startDate = start
            // Phase B HIGH #3 fix: Google all-day endDate는 exclusive (다음 날 00:00).
            // 내부 모델도 exclusive로 통일 — WeekEventLayout/allDayEventsByDay/EventEditSheet
            // 모두 `endDate > dayStart` 형태로 exclusive interval 해석 중. 여기서 -1일 변환하면
            // 렌더가 하루 짧아지는 off-by-one 버그 → 원본 그대로 저장.
            endDate = endExclusive
        } else {
            guard let startStr = dto.start?.dateTime,
                  let endStr = dto.end?.dateTime,
                  let start = parseDateTime(startStr),
                  let end = parseDateTime(endStr) else {
                return nil
            }
            startDate = start
            endDate = end
        }

        let colorHex: String
        if let cid = dto.colorId, let hex = colorIdToHex[cid] {
            colorHex = hex
        } else {
            colorHex = defaultColorHex
        }

        let updated = dto.updated.flatMap { parseDateTime($0) }

        // 읽기 전용 판정: attendees에서 self.responseStatus가 있으며 self가 organizer가 아닐 때
        // v0.1.0은 보수적으로 `guestsCanModify == false` 기본을 따르고 별도 판정은 상위로 유예.
        let readOnly = false

        guard let id = dto.id else { return nil }

        return CalendarEvent(
            id: id,
            calendarId: calendarId,
            title: dto.summary ?? "(제목 없음)",
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            description: dto.description,
            location: dto.location,
            colorHex: colorHex,
            source: .google,
            etag: dto.etag,
            updated: updated,
            isReadOnly: readOnly
        )
    }

    /// ISO8601 RFC3339 파싱 — fractional seconds 유무 둘 다 허용.
    static func parseDateTime(_ s: String) -> Date? {
        if let d = rfc3339Flexible.date(from: s) { return d }
        if let d = rfc3339UTC.date(from: s) { return d }
        return nil
    }

    /// CalendarEvent/Draft → Google request body DTO.
    /// all-day는 내부 모델이 이미 exclusive end(= 다음 날 00:00)를 저장하므로 그대로 전송.
    /// timed는 RFC3339 UTC로 전송.
    static func makeEventBody(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String?,
        description: String?,
        colorHex: String?
    ) -> GoogleEventWriteDTO {
        let start: EventDate
        let end: EventDate

        if isAllDay {
            // Phase B HIGH #3 fix: 내부 모델이 exclusive end로 통일됐으므로 여기서 +1일 하지 않는다.
            // Google Calendar API spec과 그대로 일치 (end.date exclusive).
            // all-day 문자열은 **로컬 타임존 기준** 년-월-일 component로 생성해야 한국 KST 자정 Date가
            // UTC로 변환되어 전날로 인코딩되는 off-by-one을 피함 (MEDIUM #7).
            start = EventDate(
                date: localAllDayFormatter.string(from: startDate),
                dateTime: nil,
                timeZone: nil
            )
            end = EventDate(
                date: localAllDayFormatter.string(from: endDate),
                dateTime: nil,
                timeZone: nil
            )
        } else {
            start = EventDate(
                date: nil,
                dateTime: rfc3339UTC.string(from: startDate),
                timeZone: TimeZone.current.identifier
            )
            end = EventDate(
                date: nil,
                dateTime: rfc3339UTC.string(from: endDate),
                timeZone: TimeZone.current.identifier
            )
        }

        let colorId: String? = {
            guard let hex = colorHex?.uppercased() else { return nil }
            return hexToColorId[hex]
        }()

        return GoogleEventWriteDTO(
            summary: title,
            location: location,
            description: description,
            start: start,
            end: end,
            colorId: colorId
        )
    }
}

// MARK: - DTOs

/// Google events.list 응답.
struct GoogleEventListDTO: Decodable {
    let items: [GoogleEventDTO]?
    let nextPageToken: String?
}

/// Google Calendar event (v3) — decode only.
/// Docs: https://developers.google.com/calendar/api/v3/reference/events
struct GoogleEventDTO: Decodable {
    let id: String?
    let etag: String?
    let updated: String?
    let summary: String?
    let location: String?
    let description: String?
    let start: EventDate?
    let end: EventDate?
    let colorId: String?
    let status: String?
    let recurrence: [String]?
    let recurringEventId: String?
    let transparency: String?
}

/// Google Calendar event (v3) — encode only.
struct GoogleEventWriteDTO: Encodable, Equatable {
    let summary: String
    let location: String?
    let description: String?
    let start: EventDate
    let end: EventDate
    let colorId: String?
}

/// Google event start/end. date(`yyyy-MM-dd`)가 있으면 all-day, dateTime이 있으면 timed.
struct EventDate: Codable, Equatable {
    let date: String?
    let dateTime: String?
    let timeZone: String?
}
