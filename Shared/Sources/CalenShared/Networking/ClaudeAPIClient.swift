import Foundation

// MARK: - ClaudeAPIClient
//
// v0.1.1 — iOS AI 채팅 탭의 HTTP Claude API 클라이언트.
// macOS는 `AIService`가 CLI 기반으로 동작하지만 iOS에는 Claude Code CLI를 심을 수 없으므로
// Anthropic Messages API(`https://api.anthropic.com/v1/messages`)를 직접 호출한다.
//
// 책임:
//   1. `/v1/messages` 요청 빌드 + 직렬화 (+ SSE streaming)
//   2. 응답 본문(JSON) 파싱, 스트리밍 SSE 이벤트 파싱
//   3. HTTP 상태 → `ClaudeAPIError` 의미 매핑
//
// 비책임:
//   - API 키 저장/로드 (iOS: `ClaudeAPIKeychain`, macOS: `APIKeyManager`)
//   - Markdown 렌더링 / 첨부파일 업로드 (v0.1.2로 연기)
//
// 테스트: init `transport: URLProtocol.Type?` 주입으로 URLSessionConfiguration에 mock
// URLProtocol을 끼워 모든 요청을 가로챈다 (`ClaudeAPIClientTests`).

/// Claude Messages API (`https://api.anthropic.com/v1/messages`) 클라이언트.
/// `actor`로 선언되어 스트림 상태 접근이 직렬화된다.
public actor ClaudeAPIClient {

    // MARK: - Types

    /// Claude Messages API content block. v0.1.1에서는 text만. (이미지/PDF는 v0.1.2)
    public enum ContentBlock: Sendable, Equatable {
        case text(String)

        public var text: String? {
            if case let .text(s) = self { return s }
            return nil
        }
    }

    /// 단일 메시지 value type. role은 Anthropic 스펙의 `"user"` / `"assistant"` 문자열.
    public struct ClaudeMessage: Sendable, Equatable {
        public let role: String  // "user" | "assistant"
        public let content: [ContentBlock]

        public init(role: String, content: [ContentBlock]) {
            self.role = role
            self.content = content
        }

        /// 편의 초기화 — text 한 덩어리.
        public static func user(_ text: String) -> ClaudeMessage {
            .init(role: "user", content: [.text(text)])
        }

        public static func assistant(_ text: String) -> ClaudeMessage {
            .init(role: "assistant", content: [.text(text)])
        }
    }

    /// ChatViewModel이 구독하는 스트리밍 이벤트.
    /// Anthropic SSE 스펙(`message_start` / `content_block_delta` / `message_stop`)을
    /// 간소화해 text delta만 UI로 흘린다.
    public enum ChatEvent: Sendable, Equatable {
        /// 새 assistant 메시지 시작. UI에서 빈 assistant bubble를 추가하는 신호.
        case messageStart
        /// assistant 텍스트 조각 도착. 누적해 기존 bubble에 append.
        case contentBlockDelta(String)
        /// 스트림 종료 (정상 완료).
        case messageStop
    }

    /// Claude API 호출 에러 — HTTP 상태 → 의미 매핑.
    /// Equatable은 category 기반(associated error는 identity 비교 생략).
    public enum ClaudeAPIError: Error, Equatable, Sendable {
        /// 401 — API 키 없음/잘못됨.
        case unauthorized
        /// 429 — rate limit. 호출자 측 backoff/토스트 유도.
        case rateLimited
        /// 5xx — Anthropic 서버 오류.
        case serverError(status: Int)
        /// 기타 4xx.
        case clientError(status: Int, body: String)
        /// URLSession / 전송 단계 실패.
        case network(String)
        /// 응답 JSON 디코딩 실패.
        case decoding(String)
        /// API 키 설정 안 됨(호출자 측에서 선검사 실패한 경우).
        case apiKeyMissing

        public static func == (lhs: ClaudeAPIError, rhs: ClaudeAPIError) -> Bool {
            switch (lhs, rhs) {
            case (.unauthorized, .unauthorized),
                 (.rateLimited, .rateLimited),
                 (.apiKeyMissing, .apiKeyMissing):
                return true
            case let (.serverError(a), .serverError(b)):
                return a == b
            case let (.clientError(a, ab), .clientError(b, bb)):
                return a == b && ab == bb
            case let (.network(a), .network(b)):
                return a == b
            case let (.decoding(a), .decoding(b)):
                return a == b
            default:
                return false
            }
        }

        /// 사용자에게 표시할 기본 메시지(한국어).
        public var userMessage: String {
            switch self {
            case .unauthorized:
                return "API 키를 확인해 주세요."
            case .rateLimited:
                return "요청이 많습니다. 잠시 후 다시 시도해 주세요."
            case .serverError:
                return "Anthropic 서버 오류입니다. 잠시 후 다시 시도해 주세요."
            case let .clientError(status, _):
                return "요청 오류 (\(status))"
            case let .network(detail):
                return "네트워크 오류: \(detail)"
            case .decoding:
                return "응답을 해석할 수 없습니다."
            case .apiKeyMissing:
                return "Claude API 키가 설정되지 않았습니다."
            }
        }
    }

    // MARK: - Defaults

    /// 기본 Anthropic API endpoint.
    public static let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// 기본 모델 — `claude-opus-4-7` (프로젝트 cursor, user CLAUDE.md 에서 명시).
    public static let defaultModel = "claude-opus-4-7"
    /// fallback 모델.
    public static let fallbackModel = "claude-sonnet-4-6"
    /// Anthropic SSE가 요구하는 API 버전 헤더.
    public static let anthropicVersion = "2023-06-01"
    /// 기본 max_tokens.
    public static let defaultMaxTokens = 2048

    // MARK: - Dependencies

    private let endpoint: URL
    private let apiKeyProvider: @Sendable () -> String?
    private let session: URLSession
    private let model: String
    private let maxTokens: Int

    // MARK: - Init

    /// - Parameters:
    ///   - apiKeyProvider: 매 호출 시 Keychain에서 최신 API 키를 읽는 클로저. `nil` 반환 시 `.apiKeyMissing`.
    ///   - model: 기본값은 `claude-opus-4-7`. 외부에서 AppStorage로 override 가능.
    ///   - maxTokens: 기본 2048.
    ///   - endpoint: 테스트 override용. 기본 `defaultEndpoint`.
    ///   - transport: 테스트 URLProtocol 주입용. 지정 시 `URLSessionConfiguration.ephemeral`에
    ///     protocolClasses 를 설정한 세션으로 교체된다.
    public init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        model: String = ClaudeAPIClient.defaultModel,
        maxTokens: Int = ClaudeAPIClient.defaultMaxTokens,
        endpoint: URL = ClaudeAPIClient.defaultEndpoint,
        transport: URLProtocol.Type? = nil
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.maxTokens = maxTokens
        self.endpoint = endpoint

        if let transport {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [transport]
            self.session = URLSession(configuration: config)
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            // 스트리밍 응답이 수 분간 이어질 수 있음.
            config.timeoutIntervalForResource = 300
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// 메시지 배열 + 시스템 프롬프트로 Claude 호출. `stream=true`면 SSE 파싱 후 delta 이벤트 방출,
    /// `false`면 단일 JSON을 파싱해 assistant text 전체를 하나의 `.contentBlockDelta`로 emit.
    ///
    /// 스트림은 오류 발생 시 `AsyncThrowingStream`의 error 경로로 `ClaudeAPIError`를 throw한다.
    public func send(
        messages: [ClaudeMessage],
        system: String? = nil,
        stream: Bool = true
    ) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runSend(
                        messages: messages,
                        system: system,
                        stream: stream,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Core

    private func runSend(
        messages: [ClaudeMessage],
        system: String?,
        stream: Bool,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        guard let apiKey = apiKeyProvider(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeAPIError.apiKeyMissing
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        let body = Self.makeRequestBody(
            model: model,
            maxTokens: maxTokens,
            messages: messages,
            system: system,
            stream: stream
        )
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw ClaudeAPIError.decoding("request body encode 실패: \(error)")
        }

        if stream {
            try await performStreaming(request: request, continuation: continuation)
        } else {
            try await performNonStreaming(request: request, continuation: continuation)
        }
    }

    // MARK: Non-streaming

    private func performNonStreaming(
        request: URLRequest,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeAPIError.network("\(error)")
        }
        try Self.validate(response: response, body: data)

        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = obj["content"] as? [[String: Any]]
        else {
            throw ClaudeAPIError.decoding("content 배열을 찾을 수 없음")
        }

        continuation.yield(.messageStart)
        var any = false
        for block in content {
            if let type = block["type"] as? String, type == "text",
               let text = block["text"] as? String, !text.isEmpty {
                continuation.yield(.contentBlockDelta(text))
                any = true
            }
        }
        if !any {
            // empty content — 그래도 stop을 emit해 UI가 멈추지 않도록.
        }
        continuation.yield(.messageStop)
    }

    // MARK: Streaming (SSE)

    private func performStreaming(
        request: URLRequest,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw ClaudeAPIError.network("\(error)")
        }

        // 비-2xx면 body를 일부 읽어 에러 매핑.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var collected = Data()
            do {
                for try await byte in bytes {
                    collected.append(byte)
                    if collected.count > 8192 { break }
                }
            } catch {
                // ignore — 상태 기반으로 매핑.
            }
            try Self.validate(response: response, body: collected)
        }

        // URLSession.AsyncBytes.lines는 URLProtocol 테스트 환경에서 버퍼 flush 타이밍이
        // 실제 네트워크와 달라 마지막 청크를 누락하는 경우가 있다. 안전하게 byte 단위로
        // 수동 라인 분리해 SSE parser를 돌린다.
        var pending = Data()
        var eventType: String? = nil
        var dataLines: [String] = []

        func flushLine(_ raw: String) throws {
            if raw.isEmpty {
                if !dataLines.isEmpty {
                    let payload = dataLines.joined(separator: "\n")
                    try Self.dispatch(
                        event: eventType,
                        dataPayload: payload,
                        continuation: continuation
                    )
                }
                eventType = nil
                dataLines = []
                return
            }
            if raw.hasPrefix(":") { return }  // SSE comment

            if raw.hasPrefix("event:") {
                eventType = String(raw.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if raw.hasPrefix("data:") {
                let value = String(raw.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces)
                dataLines.append(value)
            }
            // 기타 라인은 무시 (id:, retry: 등).
        }

        do {
            for try await byte in bytes {
                if byte == 0x0A {  // '\n'
                    // \r\n인 경우 trailing \r 제거
                    if pending.last == 0x0D {
                        pending.removeLast()
                    }
                    let line = String(data: pending, encoding: .utf8) ?? ""
                    pending.removeAll(keepingCapacity: true)
                    try flushLine(line)
                } else {
                    pending.append(byte)
                }
            }
            // EOF — 잔여 buffer 처리
            if !pending.isEmpty {
                let line = String(data: pending, encoding: .utf8) ?? ""
                try flushLine(line)
            }
            // 마지막 block flush (trailing newline 없는 경우 대비)
            if !dataLines.isEmpty {
                let payload = dataLines.joined(separator: "\n")
                try Self.dispatch(
                    event: eventType,
                    dataPayload: payload,
                    continuation: continuation
                )
            }
        } catch let err as ClaudeAPIError {
            throw err
        } catch is CancellationError {
            // 호출자가 스트림 consumer를 중단 → OK.
            return
        } catch {
            throw ClaudeAPIError.network("\(error)")
        }
    }

    // MARK: - Helpers

    private static func makeRequestBody(
        model: String,
        maxTokens: Int,
        messages: [ClaudeMessage],
        system: String?,
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": messages.map { msg -> [String: Any] in
                let blocks = msg.content.map { block -> [String: Any] in
                    switch block {
                    case let .text(t):
                        return ["type": "text", "text": t]
                    }
                }
                return ["role": msg.role, "content": blocks]
            }
        ]
        if let system, !system.isEmpty {
            body["system"] = system
        }
        return body
    }

    /// SSE dispatch — `message_start` / `content_block_delta` / `message_stop` / `error`만 취급.
    /// 그 외(ping, message_delta 등)는 silently skip.
    private static func dispatch(
        event: String?,
        dataPayload: String,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) throws {
        // Anthropic이 보내는 `[DONE]` 마커는 현재 스펙상 없음. 안전하게 skip.
        if dataPayload == "[DONE]" { return }

        guard let data = dataPayload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 잘못된 JSON은 하나만 보내진 건 무시. 전체 스트림을 깨뜨리지 않음.
            return
        }

        // event 라인이 없으면 body의 "type"으로 추론.
        let type = event ?? (obj["type"] as? String) ?? ""

        switch type {
        case "message_start":
            continuation.yield(.messageStart)
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any],
               let dtype = delta["type"] as? String,
               dtype == "text_delta",
               let text = delta["text"] as? String,
               !text.isEmpty {
                continuation.yield(.contentBlockDelta(text))
            }
        case "message_stop":
            continuation.yield(.messageStop)
        case "error":
            // 스트림 도중 error event — 원본 message는 로그에 남길 수 있도록 prefix로만 반영.
            let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "stream error"
            throw ClaudeAPIError.clientError(status: 0, body: msg)
        default:
            // ping, message_delta, content_block_start/stop 등은 UI 동작에 영향 없음.
            return
        }
    }

    /// HTTP 응답 상태 검증 → `ClaudeAPIError` 매핑.
    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.network("URL 응답 타입 아님")
        }
        let status = http.statusCode
        if (200..<300).contains(status) { return }

        switch status {
        case 401:
            throw ClaudeAPIError.unauthorized
        case 429:
            throw ClaudeAPIError.rateLimited
        case 500..<600:
            throw ClaudeAPIError.serverError(status: status)
        default:
            let text = String(data: body.prefix(1024), encoding: .utf8) ?? ""
            throw ClaudeAPIError.clientError(status: status, body: text)
        }
    }
}

