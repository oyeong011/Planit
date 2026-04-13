import SwiftUI

struct ChatView: View {
    @ObservedObject var aiService: AIService
    @ObservedObject var viewModel: CalendarViewModel
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var showSettings: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                Text("AI")
                    .font(.system(size: 14, weight: .bold))

                // Provider badge
                HStack(spacing: 3) {
                    Image(systemName: aiService.provider.icon)
                        .font(.system(size: 8))
                    Text(aiService.provider.rawValue)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))

                Spacer()
                Button { showSettings.toggle() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings) {
                    AISettingsPopover(aiService: aiService)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if !aiService.isConfigured {
                unconfiguredView
            } else {
                chatContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Unconfigured

    private var unconfiguredView: some View {
        VStack(spacing: 12) {
            Spacer()

            switch aiService.provider {
            case .gemini:
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Google 로그인이 필요합니다")
                    .font(.system(size: 13, weight: .medium))
                Text("Google 계정으로 로그인하면\nGemini가 자동 연결됩니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            case .claude:
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Claude Code 미설치")
                    .font(.system(size: 13, weight: .medium))
                Text("brew install claude-code\n또는 npm install -g @anthropic-ai/claude-code")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

            case .codex:
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Codex CLI 미설치")
                    .font(.system(size: 13, weight: .medium))
                Text("brew install codex\n또는 npm install -g @openai/codex")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Button { showSettings = true } label: {
                Text("다른 AI 선택")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            VStack(spacing: 8) {
                                Text("캘린더 AI 어시스턴트")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("\"내일 3시에 회의 추가해줘\"\n\"이번주 일정 알려줘\"\n\"정처기 일정 삭제해줘\"")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }

                        ForEach(messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }

                        if aiService.isLoading {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("생각 중...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .id("loading")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 6) {
                TextField("메시지 입력...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.purple)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || aiService.isLoading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""

        Task {
            let response = await aiService.sendMessage(text, history: Array(messages.dropLast()))
            messages.append(contentsOf: response)
            viewModel.refreshEvents()
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 20) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                if message.role == .toolCall {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9))
                        Text(message.content)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)))
                } else {
                    Text(message.content)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(message.role == .user
                                      ? Color.purple.opacity(0.2)
                                      : Color(nsColor: .controlBackgroundColor))
                        )
                }
            }

            if message.role != .user { Spacer(minLength: 20) }
        }
    }
}

// MARK: - Settings Popover

struct AISettingsPopover: View {
    @ObservedObject var aiService: AIService
    @State private var tempProvider: AIProvider = .gemini

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 설정")
                .font(.system(size: 13, weight: .bold))

            // Provider picker
            VStack(spacing: 8) {
                ForEach(AIProvider.allCases, id: \.self) { p in
                    ProviderRow(provider: p, isSelected: tempProvider == p, aiService: aiService)
                        .onTapGesture { tempProvider = p }
                }
            }

            // Model info
            Text("모델: \(tempProvider.defaultModel)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Save
            Button {
                aiService.provider = tempProvider
                aiService.saveSettings()
            } label: {
                Text("저장")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.purple))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            tempProvider = aiService.provider
        }
    }
}

// MARK: - Provider Row

struct ProviderRow: View {
    let provider: AIProvider
    let isSelected: Bool
    let aiService: AIService

    private var isAvailable: Bool {
        switch provider {
        case .gemini: return true  // Always available if logged in
        case .claude: return aiService.claudeAvailable
        case .codex: return aiService.codexAvailable
        }
    }

    private var statusText: String {
        switch provider {
        case .gemini: return "Google 로그인으로 자동 연결"
        case .claude: return aiService.claudeAvailable ? "설치됨 — 바로 사용 가능" : "미설치"
        case .codex: return aiService.codexAvailable ? "설치됨 — 바로 사용 가능" : "미설치"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .purple : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(provider.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    if isAvailable {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                    }
                }
                Text(statusText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.purple.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.purple.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
