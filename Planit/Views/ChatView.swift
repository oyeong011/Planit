import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct ChatView: View {
    @ObservedObject var aiService: AIService
    @ObservedObject var viewModel: CalendarViewModel
    var goalMemoryService: GoalMemoryService? = nil
    var habitService: HabitService? = nil          // 습관 — 목표와 완전히 분리
    // aiService.chatMessages 사용 — 탭 전환 후에도 유지
    @State private var inputText: String = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var detectedGoalNotice: String? = nil
    @State private var detectedHabitNotice: String? = nil  // 습관 감지 알림 (별도 상태)
    // 배너 자동 닫기 Task 핸들 — 새 배너가 오면 이전 dismiss를 취소하여 경합 방지
    @State private var goalNoticeDismissTask: Task<Void, Never>? = nil
    @State private var habitNoticeDismissTask: Task<Void, Never>? = nil

    /// 허용하는 파일 타입
    private static let allowedTypes: [UTType] = [.pdf]
    private static let maxAttachments = 5
    private static let maxFileSize: Int = 20_971_520  // 20MB

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.purple)
                Text("AI")
                    .font(.system(size: 13, weight: .bold))

                // Provider 세그먼트 칩
                HStack(spacing: 2) {
                    ForEach(AIProvider.allCases, id: \.self) { p in
                        let isSelected = aiService.provider == p
                        Button {
                            aiService.provider = p
                            aiService.saveSettings()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: p.icon).font(.system(size: 10))
                                Text(p.rawValue.components(separatedBy: " ").first ?? p.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.purple.opacity(0.18) : Color.clear)
                            )
                            .foregroundStyle(isSelected ? Color.purple : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.platformControlBackground))

                Spacer()

                // 채팅 지우기 버튼
                if !aiService.chatMessages.isEmpty {
                    Button {
                        aiService.chatMessages = []
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("채팅 기록 지우기")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 목표 감지 알림 배너
            if let notice = detectedGoalNotice {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.indigo)
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.indigo)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.indigo.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            // 습관 감지 알림 배너 (목표와 분리, 다른 색상)
            if let notice = detectedHabitNotice {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.teal)
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.teal)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.teal.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !aiService.isConfigured {
                unconfiguredView
            } else {
                chatContent
            }
        }
        .animation(.easeInOut(duration: 0.3), value: detectedGoalNotice)
        .animation(.easeInOut(duration: 0.3), value: detectedHabitNotice)
        .background(Color.platformWindowBackground)
        // AI 응답의 Markdown 링크 피싱 방지 — https/http만 허용
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return .discarded }
            return .systemAction
        })
    }

    // MARK: - Setup Guide (CLI 미설치 시)

    private var unconfiguredView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 헤더
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.purple)
                        Text(String(localized: "setup.title"))
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(String(localized: "setup.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Divider()

                // Step 1 — AI 설치
                setupStep(
                    number: 1,
                    icon: "terminal.fill",
                    color: .purple,
                    title: String(localized: "setup.step1.title"),
                    done: aiService.claudeAvailable || aiService.codexAvailable
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Claude Code
                        installOption(
                            name: "Claude Code",
                            description: String(localized: "setup.claude.desc"),
                            commands: [
                                "brew install claude-code",
                                "# " + String(localized: "setup.or.npm") + ": npm install -g @anthropic-ai/claude-code",
                                "claude --version"
                            ],
                            isInstalled: aiService.claudeAvailable,
                            badgeColor: .purple
                        )

                        // Codex
                        installOption(
                            name: "Codex",
                            description: String(localized: "setup.codex.desc"),
                            commands: [
                                "npm install -g @openai/codex",
                                "codex --version"
                            ],
                            isInstalled: aiService.codexAvailable,
                            badgeColor: .green
                        )

                        // 재감지 버튼
                        Button {
                            aiService.recheckCLI()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text(String(localized: "chat.redetect"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.4)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }

                // Step 2 — Google Calendar 연결
                setupStep(
                    number: 2,
                    icon: "calendar.badge.checkmark",
                    color: .blue,
                    title: String(localized: "setup.step2.title"),
                    done: viewModel.authManager.isAuthenticated
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.authManager.isAuthenticated {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(viewModel.authManager.userEmail ?? String(localized: "setup.google.connected"))
                                    .font(.system(size: 11))
                            }
                        } else {
                            Text(String(localized: "setup.google.desc"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            Button {
                                Task { await viewModel.authManager.startOAuthFlow() }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 11))
                                    Text(String(localized: "setup.google.connect.button"))
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 7).fill(.blue))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Text(String(localized: "setup.google.skip.hint"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // 완료 상태
                if (aiService.claudeAvailable || aiService.codexAvailable) && viewModel.authManager.isAuthenticated {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(String(localized: "setup.complete"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.06)))
                }
            }
            .padding(12)
        }
    }

    private func setupStep(
        number: Int,
        icon: String,
        color: Color,
        title: String,
        done: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(done ? Color.green : color.opacity(0.15))
                        .frame(width: 24, height: 24)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(done ? .secondary : .primary)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }

            if !done {
                content()
                    .padding(.leading, 32)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(done ? Color.green.opacity(0.04) : Color.platformControlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(done ? Color.green.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private func installOption(
        name: String,
        description: String,
        commands: [String],
        isInstalled: Bool,
        badgeColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                if isInstalled {
                    Text(String(localized: "setup.installed"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badgeColor.opacity(0.12)))
                }
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if !isInstalled {
                ForEach(commands, id: \.self) { cmd in
                    HStack(spacing: 6) {
                        Text(cmd)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                            #else
                            UIPasteboard.general.string = cmd
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "setup.copy.command"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.08)))
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isInstalled ? badgeColor.opacity(0.05) : Color.clear)
        )
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if aiService.chatMessages.isEmpty {
                            emptyStateView
                        }

                        ForEach(aiService.chatMessages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }

                        if aiService.isLoading {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text(String(localized: "chat.thinking"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .id("loading")
                        }

                        // Pending action approval buttons
                        if aiService.hasPendingActions {
                            actionApprovalCard
                                .id("approval")
                        }

                        if aiService.externalContextPreview != nil {
                            externalContextApprovalCard
                                .id("external-context-approval")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .onChange(of: aiService.chatMessages.count) {
                    if let lastId = aiService.chatMessages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // 첨부파일 미리보기
            if !attachments.isEmpty {
                attachmentPreviewStrip
            }

            // Input
            HStack(spacing: 6) {
                // PDF 첨부 버튼
                Button { openFilePicker() } label: {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "chat.attach.pdf.hint"))

                PasteAwareTextField(
                    text: $inputText,
                    placeholder: String(localized: "chat.input.placeholder"),
                    onSubmit: sendMessage,
                    onPastePayload: handlePastePayload
                )
                .frame(height: 20)

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSend ? Color.purple : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var canSend: Bool {
        (!inputText.isEmpty || !attachments.isEmpty) && !aiService.isLoading
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)
                Text(String(localized: "chat.assistant.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "chat.empty.subtitle"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 6) {
                ForEach(quickActions, id: \.self) { action in
                    Button {
                        inputText = action
                        sendMessage()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: quickActionIcon(action))
                                .font(.system(size: 10))
                                .foregroundStyle(.purple)
                                .frame(width: 14)
                            Text(action)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.platformControlBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var quickActions: [String] {
        [
            String(localized: "chat.quick.today"),
            String(localized: "chat.quick.add.meeting"),
            String(localized: "chat.quick.free.time"),
            String(localized: "chat.quick.tomorrow.plan"),
        ]
    }

    private func quickActionIcon(_ action: String) -> String {
        let today = String(localized: "chat.quick.today")
        let meeting = String(localized: "chat.quick.add.meeting")
        let free = String(localized: "chat.quick.free.time")
        switch action {
        case today:   return "calendar"
        case meeting: return "plus.circle"
        case free:    return "clock"
        default:      return "wand.and.stars"
        }
    }

    // MARK: - Attachment Preview Strip

    private var attachmentPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { att in
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 2) {
                            if let thumb = att.thumbnail {
                                Image(decorative: thumb, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: att.type == .pdf ? "doc.fill" : "photo")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            Text(att.fileName)
                                .font(.system(size: 8))
                                .lineLimit(1)
                                .frame(width: 44)
                        }

                        // 삭제 버튼
                        Button {
                            attachments.removeAll { $0.id == att.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .background(Circle().fill(.gray))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(height: 64)
    }

    // MARK: - File Picker

    private func openFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.allowedTypes
        panel.message = String(localized: "chat.attach.picker.message")

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            addAttachment(url: url)
        }
        #endif
        // iOS: PhotosPicker / UIDocumentPickerViewController (향후 구현)
    }

    private func addAttachment(url: URL) {
        guard attachments.count < Self.maxAttachments else { return }

        let ext = url.pathExtension.lowercased()
        let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp", "heic"]
        guard imageExts.contains(ext) || ext == "pdf" else { return }

        // 파일 크기 제한
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > Self.maxFileSize { return }

        // 중복 방지
        guard !attachments.contains(where: { $0.url == url }) else { return }

        attachments.append(ChatAttachment(url: url))
    }

    private func handlePastePayload(_ payload: ChatPasteboardReader.Payload) -> Bool {
        switch payload {
        case .files(let urls):
            for url in urls {
                addAttachment(url: url)
            }
            return true
        case .text:
            return false
        }
    }

    // MARK: - Action Approval Card

    private var externalContextApprovalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("AI 컨텍스트 전송 승인")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                Spacer()
            }

            Text("캘린더, 목표, 첨부 파일 정보가 선택한 CLI 제공자에게 전송됩니다. 민감한 이름의 캘린더는 제외됩니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if let preview = aiService.externalContextPreview {
                ScrollView {
                    Text(preview)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }

            Button {
                aiService.grantExternalContextConsent()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("승인하고 계속")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.blue))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.platformControlBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.25), lineWidth: 1))
    }

    private var actionApprovalCard: some View {
        let hasDelete = aiService.pendingActions.contains { $0.action == "delete" }
        let accentColor: Color = hasDelete ? .red : .orange

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: hasDelete ? "trash.fill" : "pencil.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor)
                Text(String(localized: "chat.action.confirm.title"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                Spacer()
                Text("\(aiService.pendingActions.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accentColor.opacity(0.12)))
            }

            ForEach(Array(aiService.pendingActions.enumerated()), id: \.offset) { _, action in
                HStack(spacing: 8) {
                    Image(systemName: action.action == "update" ? "pencil.circle.fill" : "trash.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(action.action == "delete" ? .red : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(resolveActionTitle(action))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text(actionLabel(action.action))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        let results = await aiService.confirmPendingActions()
                        aiService.chatMessages.append(contentsOf: results)
                        viewModel.refreshEvents()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(localized: "common.execute"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(accentColor))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    let msg = aiService.declinePendingActions()
                    aiService.chatMessages.append(msg)
                } label: {
                    Text(String(localized: "common.cancel"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 4)
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "create": return String(localized: "chat.action.create")
        case "update": return String(localized: "chat.action.update")
        case "delete": return String(localized: "chat.action.delete")
        default: return action
        }
    }

    /// delete/update 액션은 AI가 title을 누락해도 eventId로 실제 이벤트 제목을 조회해 표시한다.
    private func resolveActionTitle(_ action: CalendarAction) -> String {
        if let title = action.title, !title.isEmpty { return title }
        if let eid = action.eventId,
           let event = viewModel.calendarEvents.first(where: { $0.id == eid }) {
            return event.title
        }
        return String(localized: "chat.action.unknown")
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }

        // ViewModel의 캐시 이벤트 + 카테고리를 AIService에 주입
        aiService.cachedCalendarEvents = viewModel.calendarEvents
        aiService.cachedCategories = viewModel.categories

        // 할일 생성 콜백 연결 (AIService → ViewModel)
        aiService.onTodoCreate = { title, categoryID, date in
            viewModel.addTodo(title: title, categoryID: categoryID, date: date)
        }
        // 이벤트 카테고리 설정 콜백 연결
        aiService.onEventCategorySet = { eventID, eventTitle, categoryID in
            viewModel.setEventCategory(eventID: eventID, eventTitle: eventTitle, categoryID: categoryID)
        }

        let currentAttachments = attachments
        let displayText = text.isEmpty
            ? currentAttachments.map { "[\($0.fileName)]" }.joined(separator: " ")
            : text

        aiService.chatMessages.append(ChatMessage(role: .user, content: displayText, attachments: currentAttachments))
        inputText = ""
        attachments = []

        // 목표 감지 — 장기 성취 목표 (취업, 합격 등) → GoalMemoryService
        if let gms = goalMemoryService, !text.isEmpty {
            let added = gms.processUserMessage(text)
            if !added.isEmpty {
                let names = added.map { $0.title }.joined(separator: ", ")
                withAnimation { detectedGoalNotice = String(format: String(localized: "goal.detected.notice"), names) }
                // 이전 dismiss task 취소 → stale closure 경합 방지
                goalNoticeDismissTask?.cancel()
                goalNoticeDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation { detectedGoalNotice = nil }
                }
            }
        }
        // 습관 감지 — 반복 행동 루틴 (운동, 독서 등) → HabitService (목표와 완전히 분리)
        if let hs = habitService, !text.isEmpty {
            let added = hs.processUserMessage(text)
            if !added.isEmpty {
                let names = added.map { $0.emoji + " " + $0.name }.joined(separator: ", ")
                withAnimation { detectedHabitNotice = String(format: String(localized: "habit.detected.notice"), names) }
                // 이전 dismiss task 취소 → stale closure 경합 방지
                habitNoticeDismissTask?.cancel()
                habitNoticeDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation { detectedHabitNotice = nil }
                }
            }
        }

        Task {
            let response = await aiService.sendMessage(text, attachments: currentAttachments, history: Array(aiService.chatMessages.dropLast()))
            aiService.chatMessages.append(contentsOf: response)
            viewModel.refreshEvents()
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    /// Markdown 문자열을 AttributedString으로 변환 (실패 시 plain text fallback)
    static func markdownText(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(raw)
    }

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
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        // 첨부파일 썸네일
                        if !message.attachments.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(message.attachments) { att in
                                    if let thumb = att.thumbnail {
                                        Image(decorative: thumb, scale: 1)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        VStack(spacing: 2) {
                                            Image(systemName: att.type == .pdf ? "doc.fill" : "photo")
                                                .font(.system(size: 16))
                                            Text(att.fileName)
                                                .font(.system(size: 7))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, height: 60)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                                    }
                                }
                            }
                        }

                        // 텍스트 (Markdown 렌더링)
                        if !message.content.isEmpty {
                            Text(message.role == .assistant ? Self.markdownText(message.content) : AttributedString(message.content))
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.role == .user
                                  ? Color.purple.opacity(0.2)
                                  : Color.platformControlBackground)
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
    @State private var tempProvider: AIProvider = .claude

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "ai.settings.title"))
                .font(.system(size: 13, weight: .bold))

            // Provider picker
            VStack(spacing: 8) {
                ForEach(AIProvider.allCases, id: \.self) { p in
                    ProviderRow(provider: p, isSelected: tempProvider == p, aiService: aiService)
                        .onTapGesture { tempProvider = p }
                }
            }

            // Model info
            Text(String(format: String(localized: "ai.settings.model"), tempProvider.defaultModel))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Save
            Button {
                aiService.provider = tempProvider
                aiService.saveSettings()
            } label: {
                Text(String(localized: "common.save"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.purple))
                    .contentShape(Rectangle())
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
        case .claude: return aiService.claudeAvailable
        case .codex: return aiService.codexAvailable
        }
    }

    private var statusText: String {
        switch provider {
        case .claude: return aiService.claudeAvailable ? String(localized: "ai.provider.installed") : String(localized: "ai.provider.not.installed")
        case .codex: return aiService.codexAvailable ? String(localized: "ai.provider.installed") : String(localized: "ai.provider.not.installed")
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

// MARK: - PasteAwareTextField

#if os(macOS)
struct ChatPasteboardReader {
    enum Payload: Equatable {
        case text(String)
        case files([URL])
    }

    private static let supportedFileExtensions: Set<String> = [
        "pdf", "png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp", "heic"
    ]

    static func payload(from pasteboard: NSPasteboard) -> Payload? {
        let fileURLs = attachmentFileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            return .files(fileURLs)
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }

        return nil
    }

    private static func attachmentFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let fileURLString = item.string(forType: .fileURL),
                   let url = URL(string: fileURLString) {
                    urls.append(url)
                }
                if let urlString = item.string(forType: .URL),
                   let url = URL(string: urlString),
                   url.isFileURL {
                    urls.append(url)
                }
            }
        }

        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            urls.append(contentsOf: objects.compactMap { object in
                if let url = object as? URL {
                    return url
                }
                if let nsurl = object as? NSURL {
                    return nsurl as URL
                }
                return nil
            })
        }

        var seen = Set<URL>()
        return urls
            .map { $0.standardizedFileURL }
            .filter { url in
                supportedFileExtensions.contains(url.pathExtension.lowercased())
                    && seen.insert(url).inserted
            }
    }
}

final class PasteAwareNSTextField: NSTextField {
    var onPastePayload: ((ChatPasteboardReader.Payload) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           let payload = ChatPasteboardReader.payload(from: .general),
           onPastePayload?(payload) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct PasteAwareTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onPastePayload: ((ChatPasteboardReader.Payload) -> Bool)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let field = PasteAwareNSTextField()
        field.onPastePayload = onPastePayload
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if let field = field as? PasteAwareNSTextField {
            field.onPastePayload = onPastePayload
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasteAwareTextField
        init(_ parent: PasteAwareTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
#else
/// iOS에서는 SwiftUI 기본 TextField 사용 (UIViewRepresentable 불필요)
struct PasteAwareTextField: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onPastePayload: Any? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .onSubmit { onSubmit() }
    }
}
#endif
