#if os(iOS)
import SwiftUI

// MARK: - ChatBubble
//
// 단일 채팅 메시지 버블. macOS `ChatView`의 버블 스타일을 참조해 iOS system 배경으로 재작성.
// v0.1.1에서는 Markdown 렌더링 없이 raw 문자열(`Text` + `.textSelection(.enabled)`)만.
// v0.1.2에 AttributedString 변환 예정.

struct ChatBubble: View {
    let message: ChatMessage
    let onRetry: () -> Void

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                bubbleContent

                if let errMsg = message.errorMessage {
                    HStack(spacing: 8) {
                        Text(errMsg)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .lineLimit(3)

                        Button(action: onRetry) {
                            Label("재시도", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.calenBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: Content

    @ViewBuilder
    private var bubbleContent: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Text(message.text.isEmpty && message.isStreaming ? " " : message.text)
                .font(.system(size: 15))
                .foregroundStyle(isUser ? Color.white : Color(.label))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if message.isStreaming {
                StreamingCursor(isUser: isUser)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isUser
                      ? AnyShapeStyle(Color.calenBlue.opacity(0.9))
                      : AnyShapeStyle(Color(.secondarySystemBackground)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(message.errorMessage == nil ? Color.clear : Color.red.opacity(0.6), lineWidth: 1)
        )
    }
}

// MARK: - StreamingCursor

/// 스트리밍 중 깜빡이는 커서.
private struct StreamingCursor: View {
    let isUser: Bool
    @State private var blink: Bool = false

    var body: some View {
        Rectangle()
            .fill(isUser ? Color.white.opacity(0.9) : Color(.label))
            .frame(width: 2, height: 14)
            .opacity(blink ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
    }
}

// MARK: - Previews

#Preview("Chat Bubbles") {
    VStack(spacing: 0) {
        ChatBubble(
            message: ChatMessage(role: .user, text: "오늘 일정 알려줘"),
            onRetry: {}
        )
        ChatBubble(
            message: ChatMessage(
                role: .assistant,
                text: "오전 10시 스탠드업, 오후 2시 기획 회의",
                isStreaming: true
            ),
            onRetry: {}
        )
        ChatBubble(
            message: ChatMessage(
                role: .assistant,
                text: "답변 생성 실패",
                errorMessage: "API 키를 확인해 주세요."
            ),
            onRetry: {}
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}
#endif
