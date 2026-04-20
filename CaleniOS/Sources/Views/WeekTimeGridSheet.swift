#if os(iOS)
import SwiftUI
import UIKit
import CalenShared

// MARK: - WeekTimeGridSheet (v6)
//
// Phase A 주 시트 v6 재설계.
// v5에서 GeometryReader 기반 7등분 → iPhone 세로에서 칼럼이 ~50pt까지 줄어
// 텍스트가 잘리는 문제를 해결하기 위해 **120pt 고정 칼럼 + 가로 스크롤** 모델로 전환.
//
// 구조:
//   VStack
//     ├─ WeekHeaderBar (월 네비 + 닫기)
//     ├─ DemoBanner (repo.isFakeRepo 일 때)
//     └─ HStack
//         ├─ TimeGutter (48pt, 가로 스크롤 밖 고정)
//         └─ ScrollViewReader { horizontal ScrollView {
//             VStack
//               ├─ WeekdayHeader (7 × columnWidth)
//               ├─ AllDayRow (7 × columnWidth)
//               └─ vertical ScrollView { TimeGridBody (7 × columnWidth × totalHeight) }
//           } }
//
// 핵심 변경점 (codex v6 피드백 반영):
//  1) `isDraggingEvent` 단일 상태로 horizontal + vertical ScrollView 동시에 .scrollDisabled.
//  2) Tap vs Drag: 블록에 DragGesture(min=8)를 달고 onEnded의 translation.distance < 8
//     일 때만 tap으로 간주 → EventEditSheet 오픈. onTapGesture와 병존시키지 않음.
//  3) Edge autoscroll: ScrollViewProxy.scrollTo(dayID, anchor: .center), 300ms throttle.
//  4) 날짜 간 이동: dayDelta 계산 후 (newDay, snappedTimeFromDrag) combine, duration 유지.
//  5) EventEditSheet: .large detent, interactiveDismissDisabled + save/delete rollback.
//  6) columnWidth = max(120, availableWidth / 7) → iPhone 좁음/iPad 넓음 대응.
//  7) DemoBanner: fake repo 상태 고지.

struct WeekTimeGridSheet: View {

    // MARK: - Input

    @Binding var isPresented: Bool
    let initialDate: Date

    @ObservedObject var repo: FakeEventRepository

    // MARK: - Display state

    @State private var anchorDate: Date
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    /// 편집 시트에 바인딩될 이벤트 — nil이면 시트 닫힘.
    @State private var editingEvent: CalendarEvent?

    /// 현재 시각 tick (분 단위 업데이트)
    @State private var nowTick: Date = Date()
    private let nowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // MARK: - Drag state (codex: 단일 상태로 스크롤 제어)

    /// 드래그 중인 이벤트의 id(복합). nil = 드래그 아님.
    /// 이 값이 non-nil일 때 horizontal + vertical ScrollView 모두 .scrollDisabled(true).
    @State private var draggingId: String?
    @State private var resizingId: String?

    /// 드래그 중 translation.
    @State private var dragTranslation: CGSize = .zero
    @State private var resizeTranslation: CGFloat = 0

    /// Edge autoscroll throttle 타임스탬프.
    @State private var lastAutoscrollAt: Date = .distantPast

    // MARK: - Config

    private let layout = TimeGridLayout()
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }()

    private let leadingGutter: CGFloat = 48

    /// 블록 탭 vs 드래그 구분 임계값 (pt). codex: DragGesture onEnded에서 distance < 8 → tap.
    private let tapThreshold: CGFloat = 8
    private let dragMinDistance: CGFloat = 4   // 제스처 인식 시작 minimumDistance

    init(isPresented: Binding<Bool>, initialDate: Date, repo: FakeEventRepository) {
        self._isPresented = isPresented
        self.initialDate = initialDate
        self.repo = repo
        self._anchorDate = State(initialValue: initialDate)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let columnWidth = layout.dayColumnWidth(
                availableWidth: geo.size.width - leadingGutter,
                dayCount: 7
            )

            VStack(spacing: 0) {
                weekHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                if repo.isFakeRepo {
                    DemoBanner()
                }

                // v6: 외곽 vertical scroll 안에서 시간 gutter + weekday header + grid가
                // 함께 세로 스크롤된다 (gutter ↔ grid 시간 라벨 자동 동기화). 가로 스크롤은
                // grid/헤더 row 내부에 별도로 둔다 — weekday header와 all-day row는 가로만,
                // grid body는 가로/세로 둘 다 움직인다.
                scrollingWeekArea(columnWidth: columnWidth)
            }
            .background(Color.calenCream.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .bottom) { toastOverlay }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.disabled)
        .onReceive(nowTimer) { nowTick = $0 }
        .sheet(item: $editingEvent) { ev in
            EventEditSheet(
                event: ev,
                onSave: { updated in
                    try await saveFromEditSheet(updated)
                },
                onDelete: { target in
                    try await deleteFromEditSheet(target)
                }
            )
        }
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
            .disabled(isDraggingEvent)

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
            .disabled(isDraggingEvent)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .disabled(isDraggingEvent)
            .accessibilityLabel("닫기")
        }
    }

    private var weekTitle: String {
        let days = weekDays
        guard let first = days.first, let last = days.last else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        return "\(fmt.string(from: first)) ~ \(fmt.string(from: last))"
    }

    private var yearText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년"
        return fmt.string(from: weekDays.first ?? anchorDate)
    }

    // MARK: - Scrolling area

    @ViewBuilder
    private func scrollingWeekArea(columnWidth: CGFloat) -> some View {
        // v6 구조:
        //   VStack
        //     ├ HStack — [gutter placeholder (leadingGutter)] + [horizontal ScrollView { weekdayHeader + AllDayRow }]
        //     └ vertical ScrollView
        //         └ HStack — [time gutter hour labels (leadingGutter)] + [horizontal ScrollView { timeGridBody }]
        //
        // 상단 헤더 row와 grid 가로 스크롤은 서로 독립. 사용자에게는 두 영역이 함께 가로로 흘러야
        // 자연스러우므로 동일한 ScrollViewReader/hProxy를 공유해 scrollTo로 동기화한다.
        ScrollViewReader { hProxy in
            VStack(spacing: 0) {
                // 상단 헤더 영역 (수직 스크롤 X, 가로 스크롤 O)
                HStack(alignment: .top, spacing: 0) {
                    // gutter placeholder + "종일" 라벨 (AllDay row 위치)
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 48) // weekday header 공간
                        ZStack {
                            Color.calenCardSurface
                            Text("종일")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 4)
                        }
                        .frame(height: 32)
                    }
                    .frame(width: leadingGutter)

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            weekdayHeader(columnWidth: columnWidth)
                            AllDayRowView(
                                days: weekDays,
                                eventsByDay: allDayEventsByDay,
                                onTap: { ev in openEditor(ev) },
                                leadingTimeGutter: 0
                            )
                            .frame(width: columnWidth * 7)
                        }
                    }
                    .scrollDisabled(isDraggingEvent)
                }

                // 하단 그리드 — 수직 스크롤 O, 가로 스크롤 O (별도 proxy)
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        timeGutterLabels
                            .frame(width: leadingGutter)

                        ScrollView(.horizontal, showsIndicators: true) {
                            timeGridBody(columnWidth: columnWidth, hProxy: hProxy)
                        }
                        .scrollDisabled(isDraggingEvent)
                    }
                }
                .scrollDisabled(isDraggingEvent)
            }
            .onAppear {
                let idx = weekDays.firstIndex(where: { cal.isDate($0, inSameDayAs: initialDate) }) ?? 0
                let id = dayID(for: weekDays[idx])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hProxy.scrollTo(id, anchor: .leading)
                    }
                }
            }
            .onChange(of: anchorDate) { _, _ in
                if let first = weekDays.first {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hProxy.scrollTo(dayID(for: first), anchor: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Time Gutter Labels (grid와 같은 vertical scroll 내부에 동거)

    private var timeGutterLabels: some View {
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
                .padding(.top, -6)
            }
        }
        .frame(width: leadingGutter, height: layout.totalHeight, alignment: .top)
    }

    // MARK: - Weekday Header

    private func weekdayHeader(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                weekdayCell(day: day, width: columnWidth, index: idx)
                    .id(dayID(for: day))
            }
        }
        .frame(width: columnWidth * 7, height: 48)
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
        ["월", "화", "수", "목", "금", "토", "일"][index % 7]
    }

    private func weekdayColor(index: Int) -> Color {
        if index == 6 { return .red.opacity(0.9) }
        if index == 5 { return Color.calenBlue }
        return .primary
    }

    // MARK: - Time Grid Body

    @ViewBuilder
    private func timeGridBody(columnWidth: CGFloat, hProxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .topLeading) {
            gridLines(width: columnWidth * 7)

            verticalDividers(columnWidth: columnWidth)

            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                dayEventLayer(
                    day: day,
                    dayIndex: idx,
                    columnWidth: columnWidth,
                    hProxy: hProxy
                )
            }

            if let nowY = currentNowY(),
               let todayIndex = weekDays.firstIndex(where: { cal.isDateInToday($0) }) {
                nowLine(
                    y: nowY,
                    columnX: CGFloat(todayIndex) * columnWidth,
                    columnWidth: columnWidth
                )
            }
        }
        .frame(width: columnWidth * 7, height: layout.totalHeight)
    }

    private func gridLines(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<layout.durationHours, id: \.self) { idx in
                Rectangle()
                    .fill(idx == 0 ? Color.clear : Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                Spacer(minLength: 0)
                    .frame(height: layout.hourHeight - 0.5)
            }
        }
        .frame(width: width)
    }

    private func verticalDividers(columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1..<7, id: \.self) { i in
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 0.5, height: layout.totalHeight)
                    .offset(x: columnWidth * CGFloat(i), y: 0)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour % 24)
    }

    // MARK: - Event Layer per Day

    @ViewBuilder
    private func dayEventLayer(
        day: Date,
        dayIndex: Int,
        columnWidth: CGFloat,
        hProxy: ScrollViewProxy
    ) -> some View {
        let columnX = CGFloat(dayIndex) * columnWidth
        let events = timedEvents(for: day)

        ZStack(alignment: .topLeading) {
            ForEach(events, id: \.self) { ev in
                if let frame = layout.frame(for: ev, dayAnchor: day, calendar: cal) {
                    eventBlock(
                        event: ev,
                        dayIndex: dayIndex,
                        frame: frame,
                        columnX: columnX,
                        columnWidth: columnWidth,
                        hProxy: hProxy
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func eventBlock(
        event: CalendarEvent,
        dayIndex: Int,
        frame: (y: CGFloat, height: CGFloat),
        columnX: CGFloat,
        columnWidth: CGFloat,
        hProxy: ScrollViewProxy
    ) -> some View {
        let isDragging = (draggingId == compositeID(event))
        let isResizing = (resizingId == compositeID(event))

        let dragDX = isDragging ? dragTranslation.width : 0
        let dragDY = isDragging ? dragTranslation.height : 0
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
        .frame(width: max(0, columnWidth - 6), height: displayHeight)
        .offset(x: columnX + 3 + dragDX, y: frame.y + dragDY)
        .zIndex((isDragging || isResizing) ? 10 : 1)
        .gesture(
            event.isReadOnly
                ? nil
                : moveAndTapGesture(for: event, dayIndex: dayIndex, columnWidth: columnWidth, hProxy: hProxy)
        )
        // 읽기 전용은 탭만 허용 (편집 시트는 열리되 저장 비활성)
        .simultaneousGesture(
            event.isReadOnly
                ? TapGesture().onEnded { openEditor(event) }
                : nil
        )
        .overlay(alignment: .bottom) {
            if !event.isReadOnly {
                Color.clear
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture(for: event))
                    .offset(x: columnX + 3, y: 0) // overlay 내부라 columnX 불필요 (이미 부모에서 offset)
                    .allowsHitTesting(!isDragging)
            }
        }
    }

    // MARK: - Gestures (v6)

    /// 이동 드래그 + 탭 통합 제스처.
    ///
    /// codex 피드백 반영:
    ///  - `DragGesture(minimumDistance: 4)` — 손가락을 거의 안 움직이면 tap으로 해석.
    ///  - onEnded에서 `hypot(tx, ty) < tapThreshold(8)` → EventEditSheet 오픈.
    ///  - 그 이상이면 (newDay, newStart) 적용.
    private func moveAndTapGesture(
        for event: CalendarEvent,
        dayIndex: Int,
        columnWidth: CGFloat,
        hProxy: ScrollViewProxy
    ) -> some Gesture {
        DragGesture(minimumDistance: dragMinDistance)
            .onChanged { value in
                if draggingId != compositeID(event) {
                    draggingId = compositeID(event)
                    Self.impact(.light)
                }
                dragTranslation = value.translation

                // Edge autoscroll — 가로 스크롤 viewport 좌/우 근처에 있을 때
                maybeAutoscroll(
                    currentDayIndex: dayIndex,
                    translationWidth: value.translation.width,
                    columnWidth: columnWidth,
                    hProxy: hProxy
                )
            }
            .onEnded { value in
                let tx = value.translation.width
                let ty = value.translation.height
                let dist = hypot(tx, ty)

                dragTranslation = .zero
                draggingId = nil

                // tap 판정 → 편집 시트 오픈
                if dist < tapThreshold {
                    openEditor(event)
                    return
                }

                // 드래그 종료 → 날짜 + 시간 재계산 (duration 유지)
                let dayDelta = Int((tx / columnWidth).rounded())
                let snappedMin = layout.snappedMinutes(forDeltaY: ty)

                if dayDelta == 0 && snappedMin == 0 { return }

                let newIndex = max(0, min(weekDays.count - 1, dayIndex + dayDelta))
                let newDay = weekDays[newIndex]

                // 기존 시작 시각의 시/분/초 요소 보존 + snappedMin 가산
                let originalStart = event.startDate
                let timeComps = cal.dateComponents(
                    [.hour, .minute, .second],
                    from: originalStart
                )
                let baseDay = cal.startOfDay(for: newDay)
                guard let restored = cal.date(
                    byAdding: .minute,
                    value: (timeComps.hour ?? 0) * 60 + (timeComps.minute ?? 0) + snappedMin,
                    to: baseDay
                ) else { return }

                let duration = event.endDate.timeIntervalSince(event.startDate)
                let newStart = restored
                let newEnd = newStart.addingTimeInterval(duration)

                var updated = event
                updated.startDate = newStart
                updated.endDate = newEnd
                Self.impact(.medium)
                commitUpdate(updated, original: event, operation: "이동")
            }
    }

    private func resizeGesture(for event: CalendarEvent) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if resizingId != compositeID(event) {
                    resizingId = compositeID(event)
                    Self.impact(.light)
                }
                resizeTranslation = value.translation.height
            }
            .onEnded { value in
                let snappedMin = layout.snappedMinutes(forDeltaY: value.translation.height)
                resizeTranslation = 0
                resizingId = nil

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

    /// 드래그 상태 단일 소스 — horizontal + vertical scroll 모두 이것으로 제어.
    private var isDraggingEvent: Bool {
        draggingId != nil || resizingId != nil
    }

    // MARK: - Edge autoscroll

    /// 드래그 중 손가락이 좌/우 가장자리에 근접하면 ScrollViewReader로 다음 day ID로 스크롤.
    /// 300ms throttle로 연속 호출 방지.
    private func maybeAutoscroll(
        currentDayIndex: Int,
        translationWidth: CGFloat,
        columnWidth: CGFloat,
        hProxy: ScrollViewProxy
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastAutoscrollAt) > 0.3 else { return }

        // translation이 오른쪽으로 columnWidth * 0.8 이상 벗어나면 다음 day로
        // 왼쪽도 대칭
        let advance = translationWidth / columnWidth
        let threshold: CGFloat = 0.7

        var nextIndex: Int? = nil
        if advance > threshold {
            nextIndex = min(weekDays.count - 1, currentDayIndex + 1)
        } else if advance < -threshold {
            nextIndex = max(0, currentDayIndex - 1)
        }

        guard let idx = nextIndex, idx != currentDayIndex else { return }
        lastAutoscrollAt = now
        withAnimation(.easeInOut(duration: 0.3)) {
            hProxy.scrollTo(dayID(for: weekDays[idx]), anchor: .center)
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
                withAnimation(.easeOut(duration: 0.3)) {
                    repo.replaceInMemory(original)
                }
                Self.impact(.heavy)
                showToast("\(operation) 실패 — 되돌림")
            }
        }
    }

    // MARK: - Edit sheet flow

    private func openEditor(_ event: CalendarEvent) {
        editingEvent = event
        Self.impact(.light)
    }

    /// EventEditSheet에서 저장 요청 → repo.update. 실패 throw 그대로 전파 (sheet 내부 에러 배너).
    private func saveFromEditSheet(_ updated: CalendarEvent) async throws -> CalendarEvent {
        // optimistic 미리 반영 → 성공/실패 분기
        let original = repo.events.first(where: { $0 == updated }) ?? updated
        repo.replaceInMemory(updated)
        do {
            return try await repo.update(updated)
        } catch {
            // rollback
            repo.replaceInMemory(original)
            throw error
        }
    }

    /// EventEditSheet에서 삭제 요청. optimistic remove → 실패 시 복원 + 토스트.
    private func deleteFromEditSheet(_ event: CalendarEvent) async throws {
        let snapshot = event
        repo.removeInMemory(event)
        do {
            try await repo.delete(event)
        } catch {
            repo.insertInMemory(snapshot)
            showToast("삭제 실패 — 복원됨")
            throw error
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

    private func nowLine(y: CGFloat, columnX: CGFloat, columnWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .offset(x: columnX - 3.5, y: -3.5)
            Rectangle()
                .fill(Color.red)
                .frame(width: columnWidth, height: 1)
                .offset(x: columnX, y: 0)
        }
        .offset(y: y)
        .allowsHitTesting(false)
    }

    // MARK: - Identity helpers

    private func compositeID(_ event: CalendarEvent) -> String {
        "\(event.calendarId)::\(event.id)"
    }

    private func dayID(for day: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "day-\(fmt.string(from: day))"
    }

    // MARK: - Haptics

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Preview

#Preview("WeekTimeGridSheet v6") {
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
