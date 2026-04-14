import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct ChatView: View {
    @ObservedObject var aiService: AIService
    @ObservedObject var viewModel: CalendarViewModel
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var showSettings: Bool = false
    @State private var attachments: [ChatAttachment] = []
    @State private var isDragOver: Bool = false

    /// 허용하는 파일 타입
    private static let allowedTypes: [UTType] = [.image, .png, .jpeg, .gif, .webP, .tiff, .bmp, .pdf]
    private static let maxAttachments = 5
    private static let maxFileSize: Int = 20_971_520  // 20MB

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
            case .claude:
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(String(localized: "chat.claude.not.installed"))
                    .font(.system(size: 13, weight: .medium))
                Text(String(localized: "chat.claude.install.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

            case .codex:
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(String(localized: "chat.codex.not.installed"))
                    .font(.system(size: 13, weight: .medium))
                Text(String(localized: "chat.codex.install.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button {
                    aiService.recheckCLI()
                } label: {
                    Text(String(localized: "chat.redetect"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button { showSettings = true } label: {
                    Text(String(localized: "chat.select.other.ai"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
            }

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
                                Text(String(localized: "chat.assistant.title"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "chat.examples"))
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

            // 첨부파일 미리보기
            if !attachments.isEmpty {
                attachmentPreviewStrip
            }

            // Input
            HStack(spacing: 6) {
                // 첨부 버튼
                Button { openFilePicker() } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "chat.attach.hint"))

                PasteAwareTextField(
                    text: $inputText,
                    placeholder: String(localized: "chat.input.placeholder"),
                    onSubmit: sendMessage
                )
                .frame(height: 20)

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSend ? Color.purple : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: CalenNotification.pasteImage)) { notif in
            if let image = notif.userInfo?["image"] as? NSImage {
                pasteImageFromClipboard(image)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CalenNotification.pasteFiles)) { notif in
            if let urls = notif.userInfo?["urls"] as? [URL] {
                for url in urls { addAttachment(url: url) }
            }
        }
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.purple.opacity(0.05))
                    .allowsHitTesting(false)
            }
        }
    }

    private var canSend: Bool {
        (!inputText.isEmpty || !attachments.isEmpty) && !aiService.isLoading
    }

    // MARK: - Attachment Preview Strip

    private var attachmentPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { att in
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 2) {
                            if let thumb = att.thumbnail {
                                Image(nsImage: thumb)
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
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.allowedTypes
        panel.message = String(localized: "chat.attach.picker.message")

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            addAttachment(url: url)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    addAttachment(url: url)
                }
            }
        }
        return true
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

    // MARK: - Clipboard Paste

    private func pasteImageFromClipboard(_ image: NSImage) {
        guard attachments.count < Self.maxAttachments else { return }

        // 클립보드 이미지를 임시 파일로 저장
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("calen-paste", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let fileName = "paste-\(UUID().uuidString.prefix(8)).png"
        let fileURL = tmpDir.appendingPathComponent(fileName)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        guard pngData.count <= Self.maxFileSize else { return }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            attachments.append(ChatAttachment(url: fileURL))
        } catch {}
    }


    // MARK: - Action Approval Card

    private var actionApprovalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(String(localized: "chat.action.confirm.title"))
                    .font(.system(size: 11, weight: .bold))
            }

            ForEach(Array(aiService.pendingActions.enumerated()), id: \.offset) { _, action in
                HStack(spacing: 6) {
                    Image(systemName: action.action == "create" ? "plus.circle.fill" :
                            action.action == "update" ? "pencil.circle.fill" : "trash.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(action.action == "delete" ? .red : .blue)
                    Text("\(actionLabel(action.action)): \(action.title ?? "?")")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        let results = await aiService.confirmPendingActions()
                        messages.append(contentsOf: results)
                        viewModel.refreshEvents()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(localized: "common.execute"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.purple))
                }
                .buttonStyle(.plain)

                Button {
                    let msg = aiService.declinePendingActions()
                    messages.append(msg)
                } label: {
                    Text(String(localized: "common.cancel"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
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

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }

        let currentAttachments = attachments
        let displayText = text.isEmpty
            ? currentAttachments.map { "[\($0.fileName)]" }.joined(separator: " ")
            : text

        messages.append(ChatMessage(role: .user, content: displayText, attachments: currentAttachments))
        inputText = ""
        attachments = []

        Task {
            let response = await aiService.sendMessage(text, attachments: currentAttachments, history: Array(messages.dropLast()))
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
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        // 첨부파일 썸네일
                        if !message.attachments.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(message.attachments) { att in
                                    if let thumb = att.thumbnail {
                                        Image(nsImage: thumb)
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

                        // 텍스트
                        if !message.content.isEmpty {
                            Text(message.content)
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
// 일반 텍스트 입력용 NSTextField 래퍼 (이미지 paste는 PasteInterceptingController에서 처리)

class _PasteAwareNSTextField: NSTextField {}

struct PasteAwareTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> _PasteAwareNSTextField {
        let field = _PasteAwareNSTextField()
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

    func updateNSView(_ field: _PasteAwareNSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
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

