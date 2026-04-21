#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - GrassMapCard
//
// 30일 잔디맵. macOS `TodoGrassStats.make`의 iOS 간소화 버전 사용
// (CalenShared `ReviewAggregator.grassDays`). 7열 LazyVGrid + opacity로 밀도 표시.

struct GrassMapCard: View {

    /// 오래된 날짜 → 오늘 순서로 정렬된 30일 배열(기본).
    let days: [GrassDay]

    /// 현재 주의 인덱스 계산을 위해 max 참조 값 저장.
    private var maxCount: Int {
        days.map(\.count).max() ?? 0
    }

    /// 7열 × ceil(days / 7)행 grid.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 14), spacing: 4), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.grid.3x3.square")
                    .foregroundStyle(Color.green)
                Text("최근 30일 활동")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                Spacer()
                Text("\(totalEvents)개 일정")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color(for: day))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                        )
                        .accessibilityLabel("\(dateLabel(day.date)): \(day.count)개")
                }
            }

            legend
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.calenCardSurface)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: Derived

    private var totalEvents: Int {
        days.reduce(0) { $0 + $1.count }
    }

    private func color(for day: GrassDay) -> Color {
        guard maxCount > 0, day.count > 0 else {
            return Color(.tertiarySystemFill)
        }
        let ratio = Double(day.count) / Double(max(maxCount, 1))
        // GitHub 스타일 5단계 opacity.
        let opacity: Double
        switch ratio {
        case 0..<0.25:  opacity = 0.25
        case 0.25..<0.5: opacity = 0.45
        case 0.5..<0.75: opacity = 0.7
        default:         opacity = 0.95
        }
        return Color.green.opacity(opacity)
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 6) {
            Text("적음")
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabel))
            ForEach([0.25, 0.45, 0.7, 0.95], id: \.self) { o in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.green.opacity(o))
                    .frame(width: 10, height: 10)
            }
            Text("많음")
                .font(.system(size: 11))
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        return fmt.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let sample: [GrassDay] = (0..<30).map { offset in
        let date = cal.date(byAdding: .day, value: -(29 - offset), to: today) ?? today
        return GrassDay(date: date, count: Int.random(in: 0...5))
    }
    return GrassMapCard(days: sample)
        .padding()
        .background(Color.calenCream)
}
#endif
