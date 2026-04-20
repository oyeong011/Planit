#if os(iOS)
import SwiftUI
import UIKit
import CalenShared

// MARK: - WeekTimeGridSheet
//
// v5 Phase A 풀스크린 주 시트. 75%/large detent, 시간 그리드, 이벤트 드래그/리사이즈.
//
// 구성:
//  - 상단 주 네비(prev/next + 주 제목)
//  - all-day pinned row (32pt)
//  - ScrollView 내부: 요일 헤더 sticky + 시간 그리드 (60pt × 19h = 1140pt)
//  - 이벤트 블록: ZStack overlay로 컬럼별 배치, 드래그/리사이즈 제스처
//  - rollback 토스트 overlay
//
// 상태:
//  - isPresented binding — HomeView에서 제어
//  - anchorDate — 시트가 렌더할 주의 기준 날짜(해당 주의 어느 날이든 상관없음)
//  - repo — EventRepository (fake/google/eventkit 주입 가능)

struct WeekTimeGridSheet: View {

    @Binding var isPresented: Bool
    let initialDate: Date

    /// EventRepository 구현체. 반드시 `ObservableObject`인 FakeEventRepository 사용 시
    /// 상위에서 `@ObservedObject`로 전달해 `events` 업데이트가 반영되도록 함.
    @ObservedObject var repo: FakeEventRepository

    // MARK: - State

    @State private var anchorDate: Date
    @State private var scrollDisabled: Bool = false
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    /// 현재 드래그 중인 이벤트 id
    @State private var draggingId: String?
    /// 현재 리사이즈 중인 이벤트 id
    @State private var resizingId: String?
    /// 드래그 translation (y) — 즉시 반영용
    @State private var dragTranslation: CGFloat = 0
    /// 리사이즈 translation (y)
    @State private var resizeTranslation: CGFloat = 0

    /// 현재 시각 tick (분 단위 업데이트)
    @State private var nowTick: Date = Date()
    private let nowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let layout = TimeGridLayout()
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }()

    private let leadingGutter: CGFloat = 48

    init(isPresented: Binding<Bool>, initialDate: Date, repo: FakeEventRepository) {
        self._isPresented = isPresented
        self.initialDate = initialDate
        self.repo = repo
        self._anchorDate = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)

            AllDayRowView(
                days: weekDays,
                eventsByDay: allDayEventsByDay,
                onTap: { _ in /* v0.1.1 */ },
                leadingTimeGutter: leadingGutter
            )

            weekdayHeader

            timeGridScrollView
        }
        .background(Color.calenCream.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .bottom) { toastOverlay }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.disabled)
        .onReceive(nowTimer) { nowTick = $0 }
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        HStack(spacing: 10) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.calenBlue)
                    .frame(width: 32, height: 32)
                    .background(Color.calenBlue.opacity(0.10), in: Circle())
            }

            VStack(spacing: 2) {
                Text(weekTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(yearText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.calenBlue)
                    .frame(width: 32, height: 32)
                    .background(Color.calenBlue.opacity(0.10), in: Circle())
            }
        }
    }

    private var weekTitle: String {
        let days = weekDays
        guard let first = days.first, let last = days.last else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        let l = fmt.string(from: first)
        let r = fmt.string(from: last)
        return "\(l) ~ \(r)"
    }

    private var yearText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년"
        return fmt.string(from: weekDays.first ?? anchorDate)
    }

    // MARK: - Weekday Header (sticky inside grid scroll - here fixed above)

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: leadingGutter)
            GeometryReader { geo in
                let colW = geo.size.width / 7
                HStack(spacing: 0) {
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                        weekdayCell(day: day, width: colW, index: idx)
                    }
                }
            }
        }
        .frame(height: 48)
        .background(Color.calenCardSurface)
        .overlay(
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func weekdayCell(day: Date, width: CGFloat, index: Int) -> some View {
        let isToday = cal.isDateInToday(day)
        let dayNumber = cal.component(.day, from: day)

        return VStack(spacing: 2) {
            Text(weekdayName(index: index))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(weekdayColor(index: index))

            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.calenBlue)
                        .frame(width: 24, height: 24)
                }
                Text("\(dayNumber)")
                    .font(.system(size: 14, weight: isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? .white : weekdayColor(index: index))
            }
        }
        .frame(width: width)
    }

    private func weekdayName(index: Int) -> String {
        // firstWeekday=2(월) 기준. index 0 = 월, ..., 5 = 토, 6 = 일
        ["월", "화", "수", "목", "금", "토", "일"][index % 7]
    }

    private func weekdayColor(index: Int) -> Color {
        if index == 6 { return .red.opacity(0.9) }       // 일
        if index == 5 { return Color.calenBlue }         // 토
        return .primary
    }

    // MARK: - Time Grid

    @ViewBuilder
    private var timeGridScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    timeLabelColumn
                    daysGrid
                }
                .id("grid")
            }
            .scrollDisabled(scrollDisabled)
            .onAppear {
                // 현재 시각 근처로 스크롤
                // (SwiftUI ScrollView + ScrollViewReader는 id 지정 구간으로만 scroll —
                // anchor 지점의 ID를 hour 기준으로 별도 심어두고 싶지만 복잡도 대비 이득이 적어
                // 초기에는 8시 근처 offset으로 content를 밀어놓는 방식을 택함.)
                // 여기서는 content 안에 hourly ID를 심어두진 않고, 시트가 열리자마자
                // 자동으로 표준 위치로 스크롤되도록 함 (추후 개선).
            }
        }
    }

    private var timeLabelColumn: some View {
        VStack(spacing: 0) {
            ForEach(0..<layout.durationHours, id: \.self) { offset in
                let hour = layout.startHour + offset
                HStack {
                    Spacer()
                    Text(hourLabel(hour))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }
                .frame(height: layout.hourHeight, alignment: .top)
                .padding(.top, -6) // 시간 라벨이 그 시간의 "시작선" 근처에 오도록 위로 밀착
            }
        }
        .frame(width: leadingGutter)
    }

    private func hourLabel(_ hour: Int) -> String {
        // 0~23 포맷
        let h = hour % 24
        return String(format: "%02d:00", h)
    }

    /// 주 7일 시간 그리드. 각 컬럼은 GeometryReader로 폭을 계산.
    private var daysGrid: some View {
        GeometryReader { geo in
            let colW = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                // 1. 배경 grid lines (시간당 가로 선)
                gridLines
                    .frame(width: geo.size.width, height: layout.totalHeight)

                // 2. 요일별 수직 구분선
                verticalDividers(totalWidth: geo.size.width)

                // 3. 이벤트 블록 (각 요일 컬럼의 timed events)
                ForEach(weekDays, id: \.self) { day in
                    dayEventLayer(day: day, columnWidth: colW)
                }

                // 4. Now line (오늘이 주 내부일 때만)
                if let nowY = currentNowY() {
                    nowLine(y: nowY, totalWidth: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: layout.totalHeight)
        }
        .frame(height: layout.totalHeight)
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<layout.durationHours, id: \.self) { idx in
                Rectangle()
                    .fill(idx == 0 ? Color.clear : Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                Spacer(minLength: 0)
                    .frame(height: layout.hourHeight - 0.5)
            }
        }
    }

    private func verticalDividers(totalWidth: CGFloat) -> some View {
        let colW = totalWidth / 7
        return ZStack(alignment: .topLeading) {
            ForEach(1..<7, id: \.self) { i in
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 0.5, height: layout.totalHeight)
                    .offset(x: colW * CGFloat(i), y: 0)
            }
        }
    }

    // MARK: - Event Layer per Day

    @ViewBuilder
    private func dayEventLayer(day: Date, columnWidth: CGFloat) -> some View {
        let dayIndex = weekDays.firstIndex(of: day) ?? 0
        let columnX = CGFloat(dayIndex) * columnWidth
        let events = timedEvents(for: day)

        ZStack(alignment: .topLeading) {
            ForEach(events, id: \.self) { ev in
                if let frame = layout.frame(for: ev, dayAnchor: day, calendar: cal) {
                    eventBlock(event: ev, frame: frame, columnX: columnX, columnWidth: columnWidth)
                }
            }
        }
    }

    @ViewBuilder
    private func eventBlock(
        event: CalendarEvent,
        frame: (y: CGFloat, height: CGFloat),
        columnX: CGFloat,
        columnWidth: CGFloat
    ) -> some View {
        let isDragging = (draggingId == event.id)
        let isResizing = (resizingId == event.id)

        // 시각 반영을 위한 pixel offset
        let dragY = isDragging ? dragTranslation : 0
        let resizeDelta = isResizing ? resizeTranslation : 0
        let displayHeight = max(
            CGFloat(layout.minDurationMinutes) * layout.pixelsPerMinute,
            frame.height + resizeDelta
        )

        EventBlockView(
            event: event,
            height: displayHeight,
            isDragging: isDragging,
            isResizing: isResizing,
            showResizeHandle: !event.isReadOnly
        )
        .frame(width: max(0, columnWidth - 4), height: displayHeight)
        .offset(x: columnX + 2, y: frame.y + dragY)
        .zIndex((isDragging || isResizing) ? 10 : 1)
        // 이동 드래그 (블록 전체, 상단 80%)
        .gesture(
            event.isReadOnly ? nil : moveGesture(for: event, frame: frame)
        )
        // 리사이즈 드래그 (하단 12pt)
        .overlay(alignment: .bottom) {
            if !event.isReadOnly {
                Color.clear
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture(for: event, frame: frame))
            }
        }
    }

    // MARK: - Gestures

    private func moveGesture(for event: CalendarEvent, frame: (y: CGFloat, height: CGFloat)) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if draggingId != event.id {
                    draggingId = event.id
                    scrollDisabled = true
                    Self.impact(.light)
                }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                let snappedMin = layout.snappedMinutes(forDeltaY: value.translation.height)
                dragTranslation = 0
                draggingId = nil
                scrollDisabled = false

                if snappedMin == 0 { return }

                // delta 적용
                let newStart = event.startDate.addingTimeInterval(TimeInterval(snappedMin * 60))
                let newEnd = event.endDate.addingTimeInterval(TimeInterval(snappedMin * 60))
                var updated = event
                updated.startDate = newStart
                updated.endDate = newEnd
                Self.impact(.medium)
                commitUpdate(updated, original: event, operation: "이동")
            }
    }

    private func resizeGesture(for event: CalendarEvent, frame: (y: CGFloat, height: CGFloat)) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if resizingId != event.id {
                    resizingId = event.id
                    scrollDisabled = true
                    Self.impact(.light)
                }
                resizeTranslation = value.translation.height
            }
            .onEnded { value in
                let snappedMin = layout.snappedMinutes(forDeltaY: value.translation.height)
                resizeTranslation = 0
                resizingId = nil
                scrollDisabled = false

                if snappedMin == 0 { return }

                let rawNewEnd = event.endDate.addingTimeInterval(TimeInterval(snappedMin * 60))
                let minEnd = event.startDate.addingTimeInterval(TimeInterval(layout.minDurationMinutes * 60))
                let newEnd = max(rawNewEnd, minEnd)

                var updated = event
                updated.endDate = newEnd
                Self.impact(.medium)
                commitUpdate(updated, original: event, operation: "리사이즈")
            }
    }

    // MARK: - Commit / Rollback

    private func commitUpdate(_ updated: CalendarEvent, original: CalendarEvent, operation: String) {
        // 낙관적 반영 (in-memory 교체)
        repo.replaceInMemory(updated)

        Task { @MainActor in
            do {
                _ = try await repo.update(updated)
            } catch {
                // rollback
                withAnimation(.easeOut(duration: 0.3)) {
                    repo.replaceInMemory(original)
                }
                Self.impact(.heavy)
                showToast("\(operation) 실패 — 되돌림")
            }
        }
    }

    // MARK: - Toast

    private func showToast(_ msg: String) {
        toastWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            toastMessage = msg
        }
        let item = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.25)) {
                toastMessage = nil
            }
        }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let msg = toastMessage {
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                )
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Data helpers

    private var weekDays: [Date] {
        let start = weekStart(of: anchorDate)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func weekStart(of date: Date) -> Date {
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    private func shiftWeek(by delta: Int) {
        if let d = cal.date(byAdding: .weekOfYear, value: delta, to: anchorDate) {
            withAnimation(.easeInOut(duration: 0.25)) {
                anchorDate = d
            }
        }
    }

    private func timedEvents(for day: Date) -> [CalendarEvent] {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return repo.events.filter { ev in
            !ev.isAllDay
                && ev.endDate > start
                && ev.startDate < end
        }
    }

    private var allDayEventsByDay: [Date: [CalendarEvent]] {
        var map: [Date: [CalendarEvent]] = [:]
        for day in weekDays {
            let start = cal.startOfDay(for: day)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
            let evs = repo.events.filter { $0.isAllDay && $0.endDate > start && $0.startDate < end }
            map[start] = evs
        }
        return map
    }

    private func currentNowY() -> CGFloat? {
        for day in weekDays {
            if cal.isDateInToday(day) {
                return layout.yForNow(on: day, calendar: cal, now: nowTick)
            }
        }
        return nil
    }

    private func nowLine(y: CGFloat, totalWidth: CGFloat) -> some View {
        guard let idx = weekDays.firstIndex(where: { cal.isDateInToday($0) }) else {
            return AnyView(EmptyView())
        }
        let colW = totalWidth / 7
        let x = CGFloat(idx) * colW
        return AnyView(
            ZStack(alignment: .leading) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .offset(x: x - 3.5, y: -3.5)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: colW, height: 1)
                    .offset(x: x, y: 0)
            }
            .offset(y: y)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Haptics

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }
}

// MARK: - Preview

#Preview("WeekTimeGridSheet") {
    struct Wrap: View {
        @StateObject var repo = FakeEventRepository()
        @State var show = true
        var body: some View {
            Color.calenCream
                .sheet(isPresented: $show) {
                    WeekTimeGridSheet(isPresented: $show, initialDate: Date(), repo: repo)
                }
        }
    }
    return Wrap()
}
#endif
