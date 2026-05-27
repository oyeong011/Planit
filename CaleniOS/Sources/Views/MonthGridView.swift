#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - MonthGridView (UI v10 — clarity-first hybrid)
//
// 디자인 결정:
//   - 그리드는 "한 달 컨텍스트" 역할만. 세부 텍스트는 하단 카드/시트가 담당.
//   - 다일간 이벤트(2일 이상)는 가로 막대 1줄 — 기간 시각화가 핵심 가치.
//   - 단일일 이벤트는 점(dot)만 — 카테고리 색만, 텍스트 없음.
//   - 셀 56pt 정사각형에 가깝게, 한눈에 빠른 스캔 가능.

struct MonthGridView: View {

    let monthAnchor: Date
    let schedules: [ScheduleDisplayItem]
    let selectedDate: Date
    let expandedWeekStart: Date?
    let onTapDate: (Date) -> Void
    let onTapEvent: (ScheduleDisplayItem) -> Void
    var onMoveEvent: (ScheduleDisplayItem, Date) -> Void = { _, _ in }

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        c.timeZone = .current
        return c
    }()

    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    // MARK: - Dimensions
    private let weekRowHeight: CGFloat = 56
    private let dateAreaHeight: CGFloat = 24
    private let barHeight: CGFloat = 12
    private let cellHPadding: CGFloat = 2

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(weekdayLabelColor(at: index))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)

            VStack(spacing: 2) {
                ForEach(weeksInGrid, id: \.self) { weekStart in
                    weekRow(weekStart: weekStart)
                        .frame(height: weekRowHeight)
                }
            }
        }
    }

    // MARK: - Week row

    @ViewBuilder
    private func weekRow(weekStart: Date) -> some View {
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }

        // 다일간 이벤트만 막대로. 단일일은 점.
        let multiDayInputs = schedules.compactMap { item -> WeekEventLayout.Input? in
            guard isMultiDay(item) else { return nil }
            let end = item.endTime ?? item.startTime.addingTimeInterval(1800)
            return WeekEventLayout.Input(id: item.id.uuidString, startDate: item.startTime, endDate: end)
        }
        let result = WeekEventLayout.layout(
            events: multiDayInputs,
            weekStart: weekStart,
            maxVisibleLanes: 1,   // 막대는 한 줄만 — 다일간이 많으면 두 번째는 점에 흡수
            calendar: cal
        )

        GeometryReader { geo in
            let columnWidth = geo.size.width / 7.0

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, date in
                        DayCellShell(
                            date: date,
                            isInCurrentMonth: cal.isDate(date, equalTo: monthAnchor, toGranularity: .month),
                            isToday: cal.isDateInToday(date),
                            isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                            columnIndex: idx,
                            singleDayItems: singleDayItems(for: date),
                            rowHeight: weekRowHeight,
                            dateAreaHeight: dateAreaHeight,
                            barReserved: !result.placements.isEmpty,
                            onTap: { onTapDate(date) }
                        )
                        .frame(width: columnWidth)
                    }
                }

                // 다일간 막대
                ForEach(result.placements, id: \.id) { placement in
                    if let item = scheduleById(placement.id) {
                        MultiDayBar(
                            item: item,
                            continuesFromPrev: placement.continuesFromPrev,
                            continuesToNext: placement.continuesToNext,
                            dimmed: !currentMonthAnchors(placement: placement, weekDays: days)
                        )
                        .frame(
                            width: columnWidth * CGFloat(placement.spanColumns) - 2 * cellHPadding,
                            height: barHeight
                        )
                        .position(
                            x: columnWidth * (CGFloat(placement.startColumn) + CGFloat(placement.spanColumns) / 2),
                            y: dateAreaHeight + 2 + barHeight / 2
                        )
                        .onTapGesture { onTapEvent(item) }
                    }
                }
            }
        }
    }

    // MARK: - Data helpers

    private func isMultiDay(_ item: ScheduleDisplayItem) -> Bool {
        guard let end = item.endTime else { return false }
        let startDay = cal.startOfDay(for: item.startTime)
        let endDay = cal.startOfDay(for: end)
        return endDay > startDay
    }

    private func singleDayItems(for date: Date) -> [ScheduleDisplayItem] {
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return schedules
            .filter { item in
                guard !isMultiDay(item) else { return false }
                return item.startTime >= start && item.startTime < end
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private func currentMonthAnchors(placement: WeekEventLayout.Placement, weekDays: [Date]) -> Bool {
        let startIdx = max(0, min(weekDays.count - 1, placement.startColumn))
        let anchor = weekDays[startIdx]
        return cal.isDate(anchor, equalTo: monthAnchor, toGranularity: .month)
    }

    private func scheduleById(_ idString: String) -> ScheduleDisplayItem? {
        schedules.first { $0.id.uuidString == idString }
    }

    // MARK: - Grid helpers

    private var weeksInGrid: [Date] {
        var comps = cal.dateComponents([.year, .month], from: monthAnchor)
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps) else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) - 1
        guard let gridStart = cal.date(byAdding: .day, value: -weekdayOfFirst, to: firstOfMonth) else {
            return []
        }
        return (0..<6).compactMap { cal.date(byAdding: .day, value: $0 * 7, to: gridStart) }
    }

    private func weekdayLabelColor(at index: Int) -> Color {
        if index == 0 { return .red.opacity(0.8) }
        if index == 6 { return Color.calenBlue.opacity(0.8) }
        return .secondary
    }
}

// MARK: - DayCellShell (날짜 + 단일일 점)

private struct DayCellShell: View {
    let date: Date
    let isInCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let columnIndex: Int
    let singleDayItems: [ScheduleDisplayItem]
    let rowHeight: CGFloat
    let dateAreaHeight: CGFloat
    /// 이 weekRow에 다일간 막대가 있는지 — 점 위치를 그 아래로 내리기 위해.
    let barReserved: Bool
    let onTap: () -> Void

    private let maxDots = 3

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var numberColor: Color {
        if !isInCurrentMonth { return .secondary.opacity(0.4) }
        if isToday { return .white }
        if columnIndex == 0 { return .red.opacity(0.9) }
        if columnIndex == 6 { return Color.calenBlue.opacity(0.9) }
        return .primary
    }

    private var backgroundColor: Color {
        if isSelected && !isToday { return Color.calenBlue.opacity(0.08) }
        return .clear
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.calenBlue)
                        .frame(width: 26, height: 26)
                } else if isSelected {
                    Circle()
                        .stroke(Color.calenBlue, lineWidth: 1.4)
                        .frame(width: 26, height: 26)
                }
                Text(dayNumber)
                    .font(.system(size: 13, weight: isToday ? .bold : .medium))
                    .foregroundStyle(numberColor)
            }
            .frame(height: dateAreaHeight)
            .padding(.top, 3)

            Spacer(minLength: 0)
                .frame(height: barReserved ? 14 : 0)

            dotsRow

            Spacer(minLength: 0)
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityLabel(accessibilityText)
    }

    private var dotsRow: some View {
        let visible = singleDayItems.prefix(maxDots)
        let extra = max(0, singleDayItems.count - maxDots)
        return HStack(spacing: 3) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                Circle()
                    .fill(item.category.swiftUIColor)
                    .frame(width: 5, height: 5)
                    .opacity(isInCurrentMonth ? 1.0 : 0.45)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isInCurrentMonth ? 1.0 : 0.45)
            }
        }
        .frame(height: 6)
    }

    private var accessibilityText: String {
        let count = singleDayItems.count
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        return "\(fmt.string(from: date)) — 일정 \(count)개"
    }
}

// MARK: - MultiDayBar (다일간 막대 — Planit 톤 옅은 fill)

private struct MultiDayBar: View {
    let item: ScheduleDisplayItem
    let continuesFromPrev: Bool
    let continuesToNext: Bool
    let dimmed: Bool

    var body: some View {
        Text(item.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(item.category.textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(
                BarShape(
                    leftSharp: continuesFromPrev,
                    rightSharp: continuesToNext,
                    cornerRadius: 4
                )
                .fill(item.category.fillColor)
            )
            .opacity(dimmed ? 0.45 : 1.0)
    }
}

private struct BarShape: Shape {
    let leftSharp: Bool
    let rightSharp: Bool
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let topLeft = leftSharp ? 0 : r
        let bottomLeft = leftSharp ? 0 : r
        let topRight = rightSharp ? 0 : r
        let bottomRight = rightSharp ? 0 : r

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
                        radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                        radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                        radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            path.addArc(center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
                        radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Month Grid v10") {
    let vm = HomeViewModel()
    return MonthGridView(
        monthAnchor: vm.currentMonth,
        schedules: HomeViewModel.mockMonthSchedules(around: vm.currentMonth),
        selectedDate: vm.selectedDate,
        expandedWeekStart: vm.expandedWeekStart,
        onTapDate: { _ in },
        onTapEvent: { _ in },
        onMoveEvent: { _, _ in }
    )
    .padding(.horizontal, 8)
    .background(Color.calenCream)
}
#endif
