#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - HabitStreakCard
//
// 최근 7일 습관 완료 dot.
// Todo가 없는 iOS에선 macOS의 habit-streak을 "그 날 이벤트가 있었느냐 + 대표 카테고리"로 근사.
// 연속 이벤트 일수(= streak)를 상단에 표시한다.

struct HabitStreakCard: View {

    /// 최근 7일 — 과거 → 오늘 순서.
    let days: [DaySummary]

    private var streak: Int {
        // 오늘부터 거꾸로, 이벤트가 1개 이상 있는 연속 일수.
        var count = 0
        for day in days.reversed() {
            if day.totalCount > 0 { count += 1 } else { break }
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("최근 7일 습관")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.label))
                Spacer()
                Text("연속 \(streak)일")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(streak > 0 ? Color.orange : Color(.secondaryLabel))
            }

            HStack(spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 4) {
                        dot(for: day)
                        Text(weekdayLabel(for: day.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.calenCardSurface)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("최근 7일 이벤트 연속 \(streak)일")
    }

    // MARK: Dot

    @ViewBuilder
    private func dot(for day: DaySummary) -> some View {
        let fillColor: Color = {
            guard let cat = day.dominant else {
                return Color(.tertiaryLabel).opacity(0.35)
            }
            switch cat {
            case .work:     return .cardWork
            case .meeting:  return .cardMeeting
            case .meal:     return .cardMeal
            case .exercise: return .cardExercise
            case .personal: return .cardPersonal
            case .general:  return .cardGeneral
            }
        }()

        Circle()
            .fill(fillColor)
            .frame(width: 24, height: 24)
            .overlay(
                Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5)
            )
    }

    private func weekdayLabel(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "E"
        return fmt.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let sample: [DaySummary] = (0..<7).map { offset in
        let date = cal.date(byAdding: .day, value: -(6 - offset), to: today) ?? today
        let cats: [ReviewCategory?] = [.meeting, .work, nil, .exercise, .meal, .personal, .meeting]
        return DaySummary(date: date, totalCount: cats[offset] == nil ? 0 : 3, dominant: cats[offset])
    }
    return VStack { HabitStreakCard(days: sample) }
        .padding()
        .background(Color.calenCream)
}
#endif
