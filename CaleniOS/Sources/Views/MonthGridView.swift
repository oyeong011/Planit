#if os(iOS)
import SwiftUI

// MARK: - MonthGridView
//
// TimeBlocks 스타일 6행 × 7열 월 그리드.
// 각 셀은 `DayCell`로 구성되며, 날짜 숫자 + 최대 3개의 카테고리 색상 막대 + 초과 배지를 표시.
//
// 뷰는 데이터를 소유하지 않고 props(monthAnchor + schedules)로 받는다.
// 가로 스와이프 월 이동은 HomeView의 TabView가 담당.

// MARK: - Category soft color mapping (bar용)

private extension ScheduleCategory {
    var softColor: Color {
        switch self {
        case .work:     return .cardWorkSoft
        case .meeting:  return .cardMeetingSoft
        case .meal:     return .cardMealSoft
        case .exercise: return .cardExerciseSoft
        case .personal: return .cardPersonalSoft
        case .general:  return .cardGeneralSoft
        }
    }
}

// MARK: - MonthGridView

struct MonthGridView: View {

    /// 해당 월을 대표하는 Date(보통 그 달 1일).
    let monthAnchor: Date

    /// 그리드에 표시할 일정 목록 (parent가 필터/제공).
    let schedules: [ScheduleDisplayItem]

    /// 선택된 날짜 (parent binding).
    let selectedDate: Date

    /// 확장된 주의 월요일 (parent binding 복제 — 표시는 안 하고 주 하이라이트용).
    let expandedWeekStart: Date?

    /// 날짜 탭 콜백.
    let onTapDate: (Date) -> Void

    /// 이벤트 막대 탭 콜백.
    let onTapEvent: (ScheduleDisplayItem) -> Void

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        return c
    }()

    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 4) {
            // 요일 헤더
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(weekdayLabelColor(at: index))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }

            // 셀 42개
            let dates = datesInGrid
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    DayCell(
                        date: date,
                        isInCurrentMonth: cal.isDate(date, equalTo: monthAnchor, toGranularity: .month),
                        isToday: cal.isDateInToday(date),
                        isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                        isInExpandedWeek: isInExpandedWeek(date),
                        columnIndex: cal.component(.weekday, from: date) - 1,
                        events: eventsForDay(date),
                        onTapCell: { onTapDate(date) },
                        onTapEvent: onTapEvent
                    )
                }
            }
        }
    }

    // MARK: - Grid helpers

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var datesInGrid: [Date] {
        var comps = cal.dateComponents([.year, .month], from: monthAnchor)
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps) else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) - 1
        guard let gridStart = cal.date(byAdding: .day, value: -weekdayOfFirst, to: firstOfMonth) else {
            return []
        }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func isInExpandedWeek(_ date: Date) -> Bool {
        guard let weekStart = expandedWeekStart,
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return false }
        return date >= weekStart && date < weekEnd
    }

    private func eventsForDay(_ date: Date) -> [ScheduleDisplayItem] {
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return schedules
            .filter { $0.startTime >= start && $0.startTime < end }
            .sorted { $0.startTime < $1.startTime }
    }

    private func weekdayLabelColor(at index: Int) -> Color {
        if index == 0 { return .red.opacity(0.8) }      // 일요일
        if index == 6 { return Color.calenBlue.opacity(0.8) } // 토요일
        return .secondary
    }
}

// MARK: - DayCell

private struct DayCell: View {

    let date: Date
    let isInCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isInExpandedWeek: Bool
    /// 0 = 일요일, 6 = 토요일
    let columnIndex: Int
    let events: [ScheduleDisplayItem]

    let onTapCell: () -> Void
    let onTapEvent: (ScheduleDisplayItem) -> Void

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var numberColor: Color {
        if !isInCurrentMonth { return .secondary.opacity(0.45) }
        if isToday && !isSelected { return .white } // 오늘은 원형 fill 위에 흰색
        if columnIndex == 0 { return .red.opacity(0.9) }
        if columnIndex == 6 { return Color.calenBlue.opacity(0.9) }
        return .primary
    }

    private var backgroundColor: Color {
        if isSelected && isInCurrentMonth {
            return Color.calenBlue.opacity(0.10)
        }
        if isInExpandedWeek && isInCurrentMonth {
            return Color.calenBlue.opacity(0.04)
        }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 상단: 날짜 숫자 우측 정렬
            HStack {
                Spacer()
                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color.calenBlue)
                            .frame(width: 22, height: 22)
                    }
                    Text(dayNumber)
                        .font(isToday ? .system(size: 13, weight: .bold) : .calenDayCellNumber)
                        .foregroundStyle(numberColor)
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)

            // 이벤트 막대 영역 (최대 3개 + overflow)
            eventBarsSection
                .padding(.horizontal, 3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 92, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTapCell() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var eventBarsSection: some View {
        let maxVisible = 3
        let visible = Array(events.prefix(maxVisible))
        let overflow = events.count - visible.count

        VStack(alignment: .leading, spacing: 2) {
            ForEach(visible) { item in
                EventBar(item: item, dimmed: !isInCurrentMonth)
                    .onTapGesture { onTapEvent(item) }
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.calenBlue)
                    .padding(.leading, 2)
            }
        }
    }

    private var accessibilityLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        let base = fmt.string(from: date)
        if events.isEmpty { return base }
        return "\(base), 일정 \(events.count)개"
    }
}

// MARK: - EventBar

private struct EventBar: View {
    let item: ScheduleDisplayItem
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 3) {
            // 좌측 색상 막대 (3pt 높이의 수평 bar 대신 수직 바 + 라벨 조합)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(barColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            Text(item.title)
                .font(.calenEventBarLabel)
                .foregroundStyle(dimmed
                    ? Color.secondary.opacity(0.6)
                    : Color.primary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.trailing, 2)
        }
        .frame(height: 13)
        .padding(.vertical, 1)
        .padding(.leading, 2)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(barBackground)
        )
        .dynamicTypeSize(.xSmall ... .accessibility1)
    }

    private var barColor: Color {
        dimmed ? item.category.softColor.opacity(0.55) : item.category.swiftUIColor
    }

    private var barBackground: Color {
        dimmed
            ? item.category.softColor.opacity(0.15)
            : item.category.softColor.opacity(0.30)
    }
}

// MARK: - Preview

#Preview("Month Grid") {
    let vm = HomeViewModel()
    return MonthGridView(
        monthAnchor: vm.currentMonth,
        schedules: HomeViewModel.mockMonthSchedules(around: vm.currentMonth),
        selectedDate: vm.selectedDate,
        expandedWeekStart: vm.expandedWeekStart,
        onTapDate: { _ in },
        onTapEvent: { _ in }
    )
    .padding(.horizontal, 12)
    .background(Color.calenCream)
}
#endif
