#if os(iOS)
import SwiftUI

// MARK: - ChatTabView
//
// iOS AI 채팅 탭 루트. `NavigationStack` + ScrollView + LazyVStack + 하단 input bar.
// v0.1.1 범위:
//   - 텍스트 전송 / 스트리밍 표시
//   - 빈 상태 + 3개 suggestion chip
//   - API 키 미설정 배너 (SettingsView의 Claude API 키 시트로 유도는 v0.1.2에)
//   - 재시도 버튼
// v0.1.2에:
//   - Markdown 렌더링, 첨부 업로드, planning-action flow

struct ChatTabView: View {

    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var inputFocused: Bool
    @Namespace private var scrollBottom

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.hasAPIKey {
                    apiKeyMissingBanner
                }

                if let err = viewModel.errorBanner {
                    errorBanner(err)
                }

                messagesArea

                inputBar
            }
            .navigationTitle("AI 채팅")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.messages.isEmpty {
                        Button {
                            viewModel.clear()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("대화 지우기")
                    }
                }
            }
        }
    }

    // MARK: Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if viewModel.messages.isEmpty {
                    ChatEmptyState { suggestion in
                        Task { await viewModel.send(suggestion) }
                    }
                    .frame(minHeight: 400)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.messages) { msg in
                            ChatBubble(
                                message: msg,
                                onRetry: { viewModel.retry(msg.id) }
                            )
                            .id(msg.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(scrollBottom)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(scrollBottom, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                // 스트리밍 중 텍스트 길이가 늘어나면 하단 유지.
                proxy.scrollTo(scrollBottom, anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("메시지를 입력하세요", text: $viewModel.draftText, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { sendCurrent() }

            Button {
                sendCurrent()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.calenBlue : Color(.tertiaryLabel))
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
            .accessibilityLabel("전송")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: -1)
        )
    }

    private var canSend: Bool {
        !viewModel.isSending
            && !viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendCurrent() {
        let text = viewModel.draftText
        Task { await viewModel.send(text) }
    }

    // MARK: Banners

    private var apiKeyMissingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude API 키가 필요합니다")
                    .font(.system(size: 13, weight: .semibold))
                Text("설정 탭에서 API 키를 입력하면 AI 채팅을 사용할 수 있어요.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(.label))
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
    }
}

// MARK: - Previews

#Preview {
    ChatTabView()
        .environmentObject(AppState())
}
#endif
