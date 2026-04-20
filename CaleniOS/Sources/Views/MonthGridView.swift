#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - MonthGridView (UI v7)
//
// TimeBlocks 스타일 월 그리드.
// v6까지: 각 날짜 셀 내부에 작은 pill로 이벤트 표시 → 제목 잘림.
// v7: **주(week) 단위 레이어드 렌더링**으로 전환.
//   1) 각 주는 ZStack — Layer 1은 7칸 DayCellShell(배경+날짜숫자만), Layer 2는 이벤트 가로 막대를
//      GeometryReader 기반 absolute 좌표로 배치.
//   2) 다일간(multi-day) 이벤트는 여러 칼럼에 걸친 하나의 긴 bar로 렌더 (TimeBlocks 원본 패턴).
//   3) 주 경계에서 clip + continuesFromPrev/Next 플래그로 ◀/▶ 아이콘 표시.
//   4) 같은 주에서 lane 4개까지 표시, 초과는 해당 칼럼 하단 "+N" 뱃지.
//
// 배치 알고리즘은 `CalenShared.WeekEventLayout`이 담당(테스트 8개).
// 본 뷰는 그 결과를 받아 SwiftUI로 그리기만 한다.

struct MonthGridView: View {

    /// 해당 월을 대표하는 Date(보통 그 달 1일).
    let monthAnchor: Date

    /// 그리드에 표시할 일정 목록 (parent가 필터/제공).
    let schedules: [ScheduleDisplayItem]

    /// 선택된 날짜 (parent binding).
    let selectedDate: Date

    /// 확장된 주의 월요일 (현재는 미사용 — 호환 유지).
    let expandedWeekStart: Date?

    /// 날짜 탭 콜백.
    let onTapDate: (Date) -> Void

    /// 이벤트 막대 탭 콜백 — 편집 sheet 오픈 신호.
    let onTapEvent: (ScheduleDisplayItem) -> Void

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        c.timeZone = .current
        return c
    }()

    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    // MARK: - Dimensions

    private let rowDateAreaHeight: CGFloat = 22    // 날짜 숫자 영역 (축소)
    private let barHeight: CGFloat = 20            // 바 높이 증가 (읽힘)
    private let barSpacing: CGFloat = 2
    private let maxLanes: Int = 3                  // 공간 확보 — 4번째부터 "+N"
    private let overflowBadgeHeight: CGFloat = 12
    private let cellHorizontalPadding: CGFloat = 1  // 1pt만 양끝 간격 — 바가 cell 거의 꽉 채움

    private var laneArea: CGFloat {
        CGFloat(maxLanes) * (barHeight + barSpacing)
    }

    private var weekRowHeight: CGFloat {
        rowDateAreaHeight + laneArea + overflowBadgeHeight + 4
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            // 요일 헤더
            HStack(spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(weekdayLabelColor(at: index))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)

            // 주 단위 레이어드 렌더링
            VStack(spacing: 4) {
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

        let inputs = schedules.compactMap { item -> WeekEventLayout.Input? in
            let end = item.endTime ?? cal.date(byAdding: .minute, value: 30, to: item.startTime) ?? item.startTime
            return WeekEventLayout.Input(id: item.id.uuidString, startDate: item.startTime, endDate: end)
        }
        let result = WeekEventLayout.layout(
            events: inputs,
            weekStart: weekStart,
            maxVisibleLanes: maxLanes,
            calendar: cal
        )

        GeometryReader { geo in
            let columnWidth = geo.size.width / 7.0

            ZStack(alignment: .topLeading) {
                // Layer 1: 7 day cells (배경 + 날짜 숫자 + overflow 뱃지)
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, date in
                        DayCellShell(
                            date: date,
                            isInCurrentMonth: cal.isDate(date, equalTo: monthAnchor, toGranularity: .month),
                            isToday: cal.isDateInToday(date),
                            isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                            columnIndex: cal.component(.weekday, from: date) - 1,
                            hiddenCount: result.hiddenByColumn[idx] ?? 0,
                            rowHeight: weekRowHeight,
                            onTapCell: { onTapDate(date) }
                        )
                        .frame(width: columnWidth)
                    }
                }

                // Layer 2: 이벤트 가로 막대들 (absolute 좌표)
                ForEach(result.placements, id: \.id) { placement in
                    if let item = scheduleById(placement.id) {
                        EventBarRibbon(
                            item: item,
                            continuesFromPrev: placement.continuesFromPrev,
                            continuesToNext: placement.continuesToNext,
                            dimmed: !currentMonthContainsBar(placement: placement, weekDays: days)
                        )
                        .frame(
                            width: columnWidth * CGFloat(placement.spanColumns)
                                - 2 * cellHorizontalPadding,
                            height: barHeight
                        )
                        .position(
                            x: columnWidth * (CGFloat(placement.startColumn) + CGFloat(placement.spanColumns) / 2),
                            y: rowDateAreaHeight
                                + CGFloat(placement.lane) * (barHeight + barSpacing)
                                + barHeight / 2
                        )
                        .onTapGesture { onTapEvent(item) }
                    }
                }
            }
        }
    }

    private func currentMonthContainsBar(placement: WeekEventLayout.Placement, weekDays: [Date]) -> Bool {
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

// MARK: - DayCellShell (배경 + 날짜 숫자 + overflow 뱃지)

private struct DayCellShell: View {
    let date: Date
    let isInCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let columnIndex: Int
    let hiddenCount: Int
    let rowHeight: CGFloat
    let onTapCell: () -> Void

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var numberColor: Color {
        if !isInCurrentMonth { return .secondary.opacity(0.45) }
        if isToday && !isSelected { return .white }
        if columnIndex == 0 { return .red.opacity(0.9) }
        if columnIndex == 6 { return Color.calenBlue.opacity(0.9) }
        return .primary
    }

    private var backgroundColor: Color {
        if isSelected && isInCurrentMonth { return Color.calenBlue.opacity(0.10) }
        return .clear
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color.calenBlue)
                            .frame(width: 22, height: 22)
                    }
                    Text(dayNumber)
                        .font(isToday ? .system(size: 13, weight: .bold) : .system(size: 12, weight: .medium))
                        .foregroundStyle(numberColor)
                }
            }
            .padding(.top, 3)
            .padding(.trailing, 6)

            Spacer(minLength: 0)

            if hiddenCount > 0 {
                HStack {
                    Spacer()
                    Text("+\(hiddenCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.calenBlue.opacity(0.9))
                    Spacer()
                }
                .padding(.bottom, 2)
            }
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTapCell() }
    }
}

// MARK: - EventBarRibbon (가로 막대)

private struct EventBarRibbon: View {
    let item: ScheduleDisplayItem
    let continuesFromPrev: Bool
    let continuesToNext: Bool
    let dimmed: Bool

    var body: some View {
        // 단일 bar: 카테고리 색상 fill + 흰색 굵은 텍스트.
        // 가독성 우선 — 내부 HStack의 chevron/컬러바 중첩을 제거해 전체 폭을 텍스트에 할당.
        ZStack(alignment: .leading) {
            barShape
                .fill(background)

            HStack(spacing: 3) {
                if continuesFromPrev {
                    Image(systemName: "chevron.compact.left")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(textColor.opacity(0.85))
                }
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if continuesToNext {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(textColor.opacity(0.85))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(dimmed ? 0.5 : 1.0)
    }

    /// 바 fill은 카테고리 색 **solid**(~0.9 opacity). 텍스트는 흰색.
    /// 기존 0.2 opacity + stroke는 글자와 채도 대비가 부족해 가독성 낮았음.
    private var background: Color {
        category.swiftUIColor.opacity(0.88)
    }

    private var textColor: Color { .white }

    private var category: ScheduleCategory { item.category }

    private var barShape: some Shape {
        BarShape(leftSharp: continuesFromPrev, rightSharp: continuesToNext, cornerRadius: 4)
    }
}

/// 좌/우 각각 cornerRadius를 개별 제어하는 shape.
/// 주 경계에서 continuesFromPrev/Next가 true면 해당 side의 radius = 0.
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

// MARK: - Preview

#Preview("Month Grid v7") {
    let vm = HomeViewModel()
    return MonthGridView(
        monthAnchor: vm.currentMonth,
        schedules: HomeViewModel.mockMonthSchedules(around: vm.currentMonth),
        selectedDate: vm.selectedDate,
        expandedWeekStart: vm.expandedWeekStart,
        onTapDate: { _ in },
        onTapEvent: { _ in }
    )
    .padding(.horizontal, 8)
    .background(Color.calenCream)
}
#endif
