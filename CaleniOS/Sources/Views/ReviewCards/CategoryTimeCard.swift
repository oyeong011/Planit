#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - CategoryTimeCard
//
// 카테고리별 시간 누적을 가로 bar chart로 표시.
// 6 카테고리(work/meeting/meal/exercise/personal/general) 모두 0이면 placeholder.

struct CategoryTimeCard: View {

    /// 카테고리별 누적 분(minute).
    let minutesByCategory: [ReviewCategory: Int]

    private var totalMinutes: Int {
        ReviewCategory.allCases.reduce(0) { $0 + (minutesByCategory[$1] ?? 0) }
    }

    /// 0이 아닌 항목만 내림차순 정렬.
    private var orderedItems: [(category: ReviewCategory, minutes: Int)] {
        ReviewCategory.allCases
            .compactMap { cat -> (ReviewCategory, Int)? in
                let m = minutesByCategory[cat] ?? 0
                guard m > 0 else { return nil }
                return (cat, m)
            }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if totalMinutes == 0 {
                placeholder
            } else {
                stackedBar
                legend
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.calenCardSurface)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(Color.calenBlue)
            Text("카테고리별 시간")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.label))
            Spacer()
            Text(formattedTotal)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: Placeholder

    private var placeholder: some View {
        Text("집계할 일정이 없습니다")
            .font(.system(size: 13))
            .foregroundStyle(Color(.secondaryLabel))
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }

    // MARK: Stacked Bar

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(orderedItems, id: \.category) { item in
                    let width = geo.size.width * CGFloat(item.minutes) / CGFloat(max(totalMinutes, 1))
                    color(for: item.category)
                        .frame(width: max(width, 4), height: 16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(height: 16)
    }

    // MARK: Legend

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(orderedItems, id: \.category) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: item.category))
                        .frame(width: 8, height: 8)
                    Text(item.category.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.label))
                    Text(formatHour(item.minutes))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
        }
    }

    // MARK: Helpers

    private func color(for category: ReviewCategory) -> Color {
        switch category {
        case .work:     return .cardWork
        case .meeting:  return .cardMeeting
        case .meal:     return .cardMeal
        case .exercise: return .cardExercise
        case .personal: return .cardPersonal
        case .general:  return .cardGeneral
        }
    }

    private var formattedTotal: String {
        formatHour(totalMinutes)
    }

    private func formatHour(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            if m == 0 { return "\(h)h" }
            return "\(h)h \(m)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        CategoryTimeCard(minutesByCategory: [
            .work: 180,
            .meeting: 90,
            .meal: 60,
            .exercise: 45,
            .personal: 120
        ])
        CategoryTimeCard(minutesByCategory: [:])
    }
    .padding()
    .background(Color.calenCream)
}
#endif
