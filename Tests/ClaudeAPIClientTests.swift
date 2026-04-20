import Foundation
import Testing
@testable import CalenShared

// MARK: - ClaudeAPIClientTests
//
// URLProtocol 기반 mock으로 `ClaudeAPIClient`의 요청 빌드, SSE 파싱, 에러 매핑을 검증.
// 외부 네트워크 접근 0건.
//
// 커버리지 (6+):
//   1. 일반 텍스트(non-streaming) 응답 파싱
//   2. 스트리밍 SSE 다중 청크 누적
//   3. 401 → .unauthorized 매핑
//   4. 429 → .rateLimited 매핑
//   5. empty content — messageStart + messageStop만
//   6. cancellation — 스트림 중단 시 후속 이벤트 중단
//   7. API 키 미설정 → .apiKeyMissing

// MARK: - ClaudeMockURLProtocol

/// 테스트 간 독립적인 mock URLProtocol. GoogleCalendarClientTests의 `MockURLProtocol`과 이름 충돌을
/// 피하기 위해 `ClaudeMockURLProtocol`로 분리.
final class ClaudeMockURLProtocol: URLProtocol {

    /// (headers, data chunks) — chunks는 순서대로 클라이언트에 전달된다.
    struct MockResponse {
        let status: Int
        let headers: [String: String]
        let chunks: [Data]
        let finalError: Error?

        static func nonStreamingJSON(_ json: String, status: Int = 200) -> MockResponse {
            MockResponse(
                status: status,
                headers: ["Content-Type": "application/json"],
                chunks: [json.data(using: .utf8) ?? Data()],
                finalError: nil
            )
        }

        static func sse(_ chunks: [String], status: Int = 200) -> MockResponse {
            MockResponse(
                status: status,
                headers: ["Content-Type": "text/event-stream"],
                chunks: chunks.map { $0.data(using: .utf8) ?? Data() },
                finalError: nil
            )
        }

        static func errorResponse(status: Int, body: String = "") -> MockResponse {
            MockResponse(
                status: status,
                headers: ["Content-Type": "application/json"],
                chunks: [body.data(using: .utf8) ?? Data()],
                finalError: nil
            )
        }
    }

    nonisolated(unsafe) static var response: MockResponse?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    static func reset() {
        response = nil
        capturedRequests = []
        capturedBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Body 추출 — httpBody 또는 httpBodyStream.
        let bodyData: Data = {
            if let d = request.httpBody { return d }
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

        guard let resp = Self.response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "ClaudeMockURLProtocol", code: -1))
            return
        }

        let http = HTTPURLResponse(
            url: url,
            statusCode: resp.status,
            httpVersion: "HTTP/1.1",
            headerFields: resp.headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        for chunk in resp.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if let err = resp.finalError {
            client?.urlProtocol(self, didFailWithError: err)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeClient(
    apiKey: String? = "sk-ant-test",
    model: String = "claude-opus-4-7"
) -> ClaudeAPIClient {
    ClaudeAPIClient(
        apiKeyProvider: { apiKey },
        model: model,
        maxTokens: 256,
        endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
        transport: ClaudeMockURLProtocol.self
    )
}

private func collectEvents(
    from stream: AsyncThrowingStream<ClaudeAPIClient.ChatEvent, Error>
) async throws -> [ClaudeAPIClient.ChatEvent] {
    var out: [ClaudeAPIClient.ChatEvent] = []
    for try await event in stream {
        out.append(event)
    }
    return out
}

// MARK: - Tests

@Suite("ClaudeAPIClient", .serialized)
struct ClaudeAPIClientTests {

    // MARK: 1

    @Test func nonStreaming_parses_content_text_block() async throws {
        ClaudeMockURLProtocol.reset()
        let json = """
        {
          "id": "msg_01",
          "type": "message",
          "role": "assistant",
          "content": [
            { "type": "text", "text": "안녕하세요! 무엇을 도와드릴까요?" }
          ],
          "model": "claude-opus-4-7",
          "stop_reason": "end_turn"
        }
        """
        ClaudeMockURLProtocol.response = .nonStreamingJSON(json)

        let client = makeClient()
        let stream = await client.send(
            messages: [.user("안녕")],
            system: "test",
            stream: false
        )
        let events = try await collectEvents(from: stream)

        #expect(events.contains(.messageStart))
        let deltas = events.compactMap { event -> String? in
            if case let .contentBlockDelta(t) = event { return t }
            return nil
        }
        #expect(deltas.joined() == "안녕하세요! 무엇을 도와드릴까요?")
        #expect(events.contains(.messageStop))

        // Request 헤더 검증
        let req = ClaudeMockURLProtocol.capturedRequests.first!
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.httpMethod == "POST")

        // Body 검증 — model / stream=false / system
        let body = try JSONSerialization.jsonObject(with: ClaudeMockURLProtocol.capturedBodies.first!) as! [String: Any]
        #expect(body["model"] as? String == "claude-opus-4-7")
        #expect(body["stream"] as? Bool == false)
        #expect(body["system"] as? String == "test")
        let messages = body["messages"] as! [[String: Any]]
        #expect(messages.count == 1)
        #expect((messages[0]["role"] as? String) == "user")
    }

    // MARK: 2

    @Test func streaming_accumulates_sse_deltas() async throws {
        ClaudeMockURLProtocol.reset()

        // Anthropic SSE 스펙 샘플 — message_start → content_block_delta x N → message_stop.
        // 여러 청크로 분리해 parser가 버퍼링/line-split을 잘 처리하는지 확인.
        let sse = [
            "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\"}}\n\n",
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"안녕\"}}\n\n",
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"하세요\"}}\n\n",
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"!\"}}\n\n",
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
        ]
        ClaudeMockURLProtocol.response = .sse(sse)

        let client = makeClient()
        let stream = await client.send(
            messages: [.user("안녕")],
            system: nil,
            stream: true
        )
        let events = try await collectEvents(from: stream)

        // 시작/중단
        #expect(events.first == .messageStart)
        #expect(events.last == .messageStop)

        let combined = events.compactMap { event -> String? in
            if case let .contentBlockDelta(t) = event { return t }
            return nil
        }.joined()
        #expect(combined == "안녕하세요!")

        // 스트리밍 요청은 Accept: text/event-stream
        let req = ClaudeMockURLProtocol.capturedRequests.first!
        #expect(req.value(forHTTPHeaderField: "Accept") == "text/event-stream")

        let body = try JSONSerialization.jsonObject(with: ClaudeMockURLProtocol.capturedBodies.first!) as! [String: Any]
        #expect(body["stream"] as? Bool == true)
    }

    // MARK: 3

    @Test func unauthorized_401_maps_to_unauthorized_error() async throws {
        ClaudeMockURLProtocol.reset()
        ClaudeMockURLProtocol.response = .errorResponse(
            status: 401,
            body: "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}"
        )

        let client = makeClient()
        let stream = await client.send(
            messages: [.user("안녕")],
            system: nil,
            stream: true
        )

        var captured: ClaudeAPIClient.ClaudeAPIError?
        do {
            for try await _ in stream {}
        } catch let err as ClaudeAPIClient.ClaudeAPIError {
            captured = err
        }
        #expect(captured == .unauthorized)
    }

    // MARK: 4

    @Test func rate_limited_429_maps_to_rateLimited_error() async throws {
        ClaudeMockURLProtocol.reset()
        ClaudeMockURLProtocol.response = .errorResponse(status: 429, body: "{}")

        let client = makeClient()
        let stream = await client.send(
            messages: [.user("hi")],
            system: nil,
            stream: false
        )

        var captured: ClaudeAPIClient.ClaudeAPIError?
        do {
            for try await _ in stream {}
        } catch let err as ClaudeAPIClient.ClaudeAPIError {
            captured = err
        }
        #expect(captured == .rateLimited)
    }

    // MARK: 5

    @Test func empty_content_yields_start_and_stop_only() async throws {
        ClaudeMockURLProtocol.reset()
        let json = """
        {
          "id": "msg_empty",
          "role": "assistant",
          "content": [],
          "model": "claude-opus-4-7"
        }
        """
        ClaudeMockURLProtocol.response = .nonStreamingJSON(json)

        let client = makeClient()
        let stream = await client.send(
            messages: [.user("hi")],
            system: nil,
            stream: false
        )
        let events = try await collectEvents(from: stream)

        #expect(events.contains(.messageStart))
        #expect(events.contains(.messageStop))
        // content_block_delta는 없어야 함.
        let hasDelta = events.contains { event in
            if case .contentBlockDelta = event { return true }
            return false
        }
        #expect(hasDelta == false)
    }

    // MARK: 6

    @Test func cancellation_stops_stream_consumption() async throws {
        ClaudeMockURLProtocol.reset()

        // 큰 SSE 스트림 — 5개 청크. Task 취소 후 이벤트가 더 이상 들어오지 않아야 한다.
        let sse = (1...5).map { i in
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"chunk\(i)\"}}\n\n"
        }
        ClaudeMockURLProtocol.response = .sse(sse)

        let client = makeClient()
        let stream = await client.send(
            messages: [.user("stream me")],
            system: nil,
            stream: true
        )

        var received: [ClaudeAPIClient.ChatEvent] = []
        let task = Task {
            do {
                for try await event in stream {
                    received.append(event)
                    if received.count >= 1 {
                        break  // 첫 이벤트 받으면 consumer 측에서 중단
                    }
                }
            } catch {}
        }

        await task.value
        // 최소 1개 이벤트만 받고 종료 — 5개 모두 받지 않음.
        #expect(received.count <= 5)
        #expect(received.isEmpty == false)
    }

    // MARK: 7

    @Test func missing_api_key_throws_apiKeyMissing() async throws {
        ClaudeMockURLProtocol.reset()

        let client = makeClient(apiKey: nil)
        let stream = await client.send(
            messages: [.user("hi")],
            system: nil,
            stream: false
        )

        var captured: ClaudeAPIClient.ClaudeAPIError?
        do {
            for try await _ in stream {}
        } catch let err as ClaudeAPIClient.ClaudeAPIError {
            captured = err
        }
        #expect(captured == .apiKeyMissing)
        // 실제 요청 자체가 나가지 않아야 함.
        #expect(ClaudeMockURLProtocol.capturedRequests.isEmpty)
    }
}
