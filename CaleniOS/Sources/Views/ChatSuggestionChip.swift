#if os(iOS)
import SwiftUI

// MARK: - ChatSuggestionChip
//
// 빈 상태 하단에 표시되는 추천 질문 버튼. 탭하면 onTap(text)가 호출된다.

struct ChatSuggestionChip: View {
    let text: String
    let onTap: (String) -> Void

    var body: some View {
        Button {
            onTap(text)
        } label: {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.calenBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.calenBlue.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 10) {
        ChatSuggestionChip(text: "오늘 일정 알려줘", onTap: { _ in })
        ChatSuggestionChip(text: "이번 주 요약", onTap: { _ in })
    }
    .padding()
}
#endif
