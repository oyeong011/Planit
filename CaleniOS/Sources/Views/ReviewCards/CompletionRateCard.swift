#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - CompletionRateCard
//
// "오늘 일정 12개 / 완료 9개 (75%)" + circular progress.
// iOS는 Todo 모델이 없으므로 "종료된 이벤트 / 전체 이벤트"로 완료 비율을 근사한다.

struct CompletionRateCard: View {

    let done: Int
    let total: Int
    let rate: Double         // 0.0 ~ 1.0
    let periodLabel: String  // "오늘" / "이번 주" / "이번 달"

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.calenBlue.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.001, min(rate, 1.0)))
                    .stroke(
                        Color.calenBlue,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: rate)

                VStack(spacing: 0) {
                    Text("\(Int(rate * 100))%")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.calenBlue)
                }
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(periodLabel) 완료율")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))

                Text("\(periodLabel) 일정 \(total)개 / 완료 \(done)개")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if total == 0 {
                    Text("아직 일정이 없어요")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.calenCardSurface)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(periodLabel) 완료율 \(Int(rate * 100))퍼센트, 총 \(total)개 중 \(done)개 완료")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        CompletionRateCard(done: 9, total: 12, rate: 0.75, periodLabel: "오늘")
        CompletionRateCard(done: 0, total: 0, rate: 0, periodLabel: "이번 주")
    }
    .padding()
    .background(Color.calenCream)
}
#endif
