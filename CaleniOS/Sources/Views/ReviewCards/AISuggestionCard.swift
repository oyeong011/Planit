#if os(iOS)
import SwiftUI

// MARK: - AISuggestionCard
//
// Claude API로 생성한 짧은 요약 카드 (2문장 이하).
// ReviewViewModel의 `regenerateAISummary()`를 통해 생성 — 카드 자체는 표시 전용 + 재생성 버튼만.
//
// 상태 조합:
//   - loading: ProgressView
//   - summary 있음: 본문 표시
//   - error 있음: 빨간 배너 + 재시도
//   - 모두 없음: "AI 요약 생성" CTA

struct AISuggestionCard: View {

    let summary: String?
    let isLoading: Bool
    let error: String?
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.calenBlue)
                Text("AI 요약")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                Spacer()
                Button(action: onRegenerate) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text(summary == nil ? "생성" : "재생성")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.calenBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.calenBlue.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.calenCardSurface)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("요약을 생성하는 중...")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer()
            }
        } else if let error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.label))
                    .lineLimit(3)
            }
        } else if let summary, !summary.isEmpty {
            Text(summary)
                .font(.system(size: 14))
                .foregroundStyle(Color(.label))
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("이 기간의 일정을 AI가 분석해 짧은 조언을 만들어 드려요.")
                .font(.system(size: 13))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        AISuggestionCard(
            summary: "이번 주는 미팅이 많았습니다. 개인 시간을 10% 확보하는 걸 추천합니다.",
            isLoading: false,
            error: nil,
            onRegenerate: {}
        )
        AISuggestionCard(summary: nil, isLoading: true, error: nil, onRegenerate: {})
        AISuggestionCard(summary: nil, isLoading: false, error: "API 키를 확인해 주세요.", onRegenerate: {})
        AISuggestionCard(summary: nil, isLoading: false, error: nil, onRegenerate: {})
    }
    .padding()
    .background(Color.calenCream)
}
#endif
