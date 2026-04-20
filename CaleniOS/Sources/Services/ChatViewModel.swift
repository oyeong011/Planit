#if os(iOS)
import Foundation
import SwiftUI
import CalenShared

// MARK: - ChatMessage

/// 채팅 버블 1개의 표시 상태. Hashable로 LazyVStack 재사용 최적화.
public struct ChatMessage: Identifiable, Hashable {
    public enum Role: String {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public var text: String
    public let timestamp: Date
    public var isStreaming: Bool
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.errorMessage = errorMessage
    }
}

// MARK: - ChatViewModel

/// iOS AI 채팅 탭의 상태 허브.
///
/// 역할:
///   - `messages` append / 스트림 누적
///   - `draftText` 바인딩
///   - `send`, `retry`, `clear`
///   - `ClaudeAPIClient` 호출 및 에러 → `errorBanner` 매핑
///
/// 시스템 프롬프트는 minimal — v0.1.2에서 오늘 일정/메모리 컨텍스트 주입 예정.
@MainActor
public final class ChatViewModel: ObservableObject {

    // MARK: Published

    @Published public var messages: [ChatMessage] = []
    @Published public var isSending: Bool = false
    @Published public var draftText: String = ""
    @Published public var errorBanner: String?

    // MARK: Dependencies

    private let clientFactory: () -> ClaudeAPIClient
    private var activeTask: Task<Void, Never>?

    /// v0.1.1 minimal 시스템 프롬프트.
    public var systemPrompt: String = "당신은 Calen 일정 도우미입니다. 한국어로 간결하게 답하고, 의견이 필요할 때는 명확하게 제시합니다."

    // MARK: Init

    /// 기본 초기화. Keychain에서 API 키를 읽는 실제 클라이언트를 주입.
    public convenience init() {
        self.init(clientFactory: ChatViewModel.makeDefaultClient)
    }

    /// 테스트용/커스텀 팩토리 주입.
    public init(clientFactory: @escaping () -> ClaudeAPIClient) {
        self.clientFactory = clientFactory
    }

    /// Keychain에서 API 키를 읽는 기본 팩토리. `@AppStorage("calen-ios.claude.model")`로
    /// 모델 override 가능(없으면 `claude-opus-4-7`).
    private static func makeDefaultClient() -> ClaudeAPIClient {
        let model = UserDefaults.standard.string(forKey: "calen-ios.claude.model")
            ?? ClaudeAPIClient.defaultModel
        return ClaudeAPIClient(
            apiKeyProvider: { ClaudeAPIKeychain.load() },
            model: model
        )
    }

    // MARK: Public API

    /// API 키가 Keychain에 존재하는지.
    public var hasAPIKey: Bool {
        guard let key = ClaudeAPIKeychain.load() else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 사용자 메시지 전송. optimistic하게 user/assistant 2개 추가 후 스트림 누적.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        errorBanner = nil

        let userMsg = ChatMessage(role: .user, text: trimmed)
        let assistantMsg = ChatMessage(
            role: .assistant,
            text: "",
            isStreaming: true
        )
        messages.append(userMsg)
        messages.append(assistantMsg)
        draftText = ""

        await runStream(for: assistantMsg.id)
    }

    /// 재시도. 기존 assistant 메시지의 내용을 초기화하고 스트림 재개.
    public func retry(_ messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard messages[idx].role == .assistant else { return }
        messages[idx].text = ""
        messages[idx].isStreaming = true
        messages[idx].errorMessage = nil
        errorBanner = nil

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.runStream(for: messageId)
        }
    }

    /// 전체 대화 삭제 + 진행 중 요청 취소.
    public func clear() {
        activeTask?.cancel()
        activeTask = nil
        messages = []
        errorBanner = nil
        isSending = false
    }

    // MARK: Internal (streaming)

    private func runStream(for assistantId: UUID) async {
        isSending = true
        defer { isSending = false }

        // API 키 선검사 — 네트워크 라운드 아끼고 UX 명확히.
        guard hasAPIKey else {
            setError(for: assistantId, ClaudeAPIClient.ClaudeAPIError.apiKeyMissing.userMessage)
            return
        }

        // 대화 히스토리 구성 — 현재 assistant(빈 값)는 제외, 그 앞까지.
        let history = buildHistory(upto: assistantId)
        let client = clientFactory()
        let stream = await client.send(
            messages: history,
            system: systemPrompt,
            stream: true
        )

        do {
            for try await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .messageStart:
                    break
                case let .contentBlockDelta(text):
                    appendDelta(text, to: assistantId)
                case .messageStop:
                    finalize(assistantId)
                }
            }
            finalize(assistantId)
        } catch let err as ClaudeAPIClient.ClaudeAPIError {
            setError(for: assistantId, err.userMessage)
        } catch is CancellationError {
            finalize(assistantId)
        } catch {
            setError(for: assistantId, "오류: \(error.localizedDescription)")
        }
    }

    private func buildHistory(upto assistantId: UUID) -> [ClaudeAPIClient.ClaudeMessage] {
        var out: [ClaudeAPIClient.ClaudeMessage] = []
        for m in messages {
            if m.id == assistantId { break }  // 현재 빈 assistant bubble 전까지
            // 빈 메시지는 API에 넘기지 않음 (Anthropic: 마지막 assistant가 빈 문자열이면 400).
            let trimmed = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            switch m.role {
            case .user:
                out.append(.user(trimmed))
            case .assistant:
                out.append(.assistant(trimmed))
            }
        }
        return out
    }

    private func appendDelta(_ delta: String, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += delta
        messages[idx].isStreaming = true
    }

    private func finalize(_ id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].isStreaming = false
    }

    private func setError(for id: UUID, _ message: String) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].isStreaming = false
            messages[idx].errorMessage = message
        }
        errorBanner = message
    }
}
#endif
