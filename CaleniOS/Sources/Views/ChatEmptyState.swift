#if os(iOS)
import SwiftUI

// MARK: - ChatEmptyState
//
// 대화가 없을 때 표시되는 welcome + 3개 suggestion chip.

struct ChatEmptyState: View {
    /// suggestion chip 탭 시 호출 — ChatTabView가 draft에 채워 자동 전송.
    let onSuggestionTap: (String) -> Void

    private let suggestions = [
        "오늘 일정 알려줘",
        "이번 주 요약",
        "내일 계획 짜줘"
    ]

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.calenBlue)

            VStack(spacing: 6) {
                Text("무엇을 도와드릴까요?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(.label))

                Text("일정, 계획, 요약 — Claude에게 물어보세요.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    ChatSuggestionChip(text: s, onTap: onSuggestionTap)
                }
            }
            .padding(.top, 6)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

#Preview {
    ChatEmptyState(onSuggestionTap: { _ in })
}
#endif
