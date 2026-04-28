import SwiftUI

private struct StatisticsProgressCount: Equatable {
    let done: Int
    let total: Int

    static let zero = StatisticsProgressCount(done: 0, total: 0)
}

private struct CachedStatisticsProgressCounts: Equatable {
    let day: StatisticsProgressCount
    let week: StatisticsProgressCount
    let month: StatisticsProgressCount
    let year: StatisticsProgressCount

    static let empty = CachedStatisticsProgressCounts(
        day: .zero,
        week: .zero,
        month: .zero,
        year: .zero
    )

    func count(for period: GoalService.CompletionPeriod) -> StatisticsProgressCount {
        switch period {
        case .day: return day
        case .week: return week
        case .month: return month
        case .year: return year
        }
    }
}

private enum StatisticsSectionID: String, CaseIterable, Codable, Identifiable {
    case habitGraph = "habit_graph"
    case weeklyChart = "weekly_chart"
    case todoGrass = "todo_grass"
    case progress = "progress"

    var id: String { rawValue }

    static let defaultOrder: [StatisticsSectionID] = [.habitGraph, .weeklyChart, .todoGrass, .progress]
    private static let defaultsKey = "planit.statistics.sectionOrder"

    static func loadFromDefaults() -> [StatisticsSectionID] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([StatisticsSectionID].self, from: data) else {
            return defaultOrder
        }
        return normalized(decoded)
    }

    static func normalized(_ decoded: [StatisticsSectionID]) -> [StatisticsSectionID] {
        var normalized: [StatisticsSectionID] = []
        var seen = Set<StatisticsSectionID>()
        for sid in decoded where allCases.contains(sid) && !seen.contains(sid) {
            normalized.append(sid)
            seen.insert(sid)
        }
        for sid in allCases where !seen.contains(sid) {
            normalized.append(sid)
            seen.insert(sid)
        }
        return Set(normalized) == Set(allCases) ? normalized : defaultOrder
    }

    static func save(_ order: [StatisticsSectionID]) {
        if let data = try? JSONEncoder().encode(normalized(order)) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

struct StatisticsView: View {
    @ObservedObject var goalMemoryService: GoalMemoryService
    @ObservedObject var habitService: HabitService
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject private var themeService = CalendarThemeService.shared

    @State private var selectedPeriod: GoalService.CompletionPeriod = .day
    @State private var cachedMetricsSnapshot = ReviewMetricsSnapshot.empty()
    @State private var cachedMetricsSignature: ReviewMetricsSnapshot.InputSignature? = nil
    @State private var cachedProgressCounts = CachedStatisticsProgressCounts.empty
    @State private var cachedHabitCompletionSets: [UUID: Set<String>] = [:]
    @State private var metricsRefreshGeneration = 0
    @State private var sectionOrder: [StatisticsSectionID] = StatisticsSectionID.loadFromDefaults()
    @State private var draggingID: StatisticsSectionID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var pendingOrder: [StatisticsSectionID] = StatisticsSectionID.loadFromDefaults()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statisticsContent
        }
        .background(
            ZStack {
                Color.platformWindowBackground
                themeService.current.subtleBackgroundTint
            }
        )
        .animation(.easeInOut(duration: 0.28), value: themeService.current.id)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(themeService.current.gradient)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "statistics.title"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(themeService.current.primary)
                Text(String(localized: "statistics.subtitle"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statisticsContent: some View {
        GeometryReader { proxy in
            let layout = ReviewSectionLayout.forContainerSize(proxy.size)

            ScrollView {
                VStack(spacing: layout.sectionSpacing) {
                    ForEach(sectionOrder) { sid in
                        if shouldShowSection(sid) {
                            draggableCard(sid: sid, layout: layout)
                        }
                    }
                }
                .padding(.top, layout.contentVerticalInset)
                .padding(.bottom, layout.contentVerticalInset)
            }
        }
        .onAppear {
            scheduleMetricsSnapshotRefresh()
        }
        .onReceive(viewModel.$todos) { _ in scheduleMetricsSnapshotRefresh() }
        .onReceive(viewModel.$appleReminders) { _ in scheduleMetricsSnapshotRefresh() }
        .onReceive(viewModel.$calendarEvents) { _ in scheduleMetricsSnapshotRefresh() }
        .onReceive(viewModel.$historyEvents) { _ in scheduleMetricsSnapshotRefresh() }
        .onReceive(viewModel.$completedEventIDs) { _ in scheduleMetricsSnapshotRefresh() }
        .onReceive(habitService.$habits) { _ in scheduleMetricsSnapshotRefresh() }
        .onReceive(goalMemoryService.$goals) { _ in scheduleMetricsSnapshotRefresh() }
        .task(id: metricsRefreshGeneration) {
            guard metricsRefreshGeneration > 0 else { return }
            await deferredMetricsSnapshotRefresh()
        }
    }

    private var currentMetricsSignature: ReviewMetricsSnapshot.InputSignature {
        ReviewMetricsSnapshot.InputSignature.make(
            todos: viewModel.todos,
            reminders: viewModel.appleReminders,
            calendarEvents: viewModel.calendarEvents,
            historyEvents: viewModel.historyEvents,
            completedEventIDs: viewModel.completedEventIDs,
            habits: habitService.habits,
            habitCount: habitService.habits.count,
            goalCount: goalMemoryService.goals.count
        )
    }

    private func makeMetricsSnapshot(now: Date) -> ReviewMetricsSnapshot {
        let calendar = Calendar.current
        let weekDates = ReviewMetricsSnapshot.weekDates(endingAt: now, calendar: calendar)
        let eventsByDay = ReviewMetricsSnapshot.eventsByDay(
            weekDates: weekDates,
            calendarEvents: viewModel.calendarEvents,
            todos: viewModel.todos,
            calendar: calendar
        )

        return ReviewMetricsSnapshot.make(
            weekDates: weekDates,
            eventsByDay: eventsByDay,
            todos: viewModel.todos,
            reminders: viewModel.appleReminders,
            historyEvents: viewModel.historyEvents,
            completedEventIDs: viewModel.completedEventIDs,
            habits: habitService.habits,
            goals: goalMemoryService.goals,
            now: now,
            calendar: calendar
        )
    }

    private func refreshMetricsSnapshotIfNeeded() {
        let newSignature = currentMetricsSignature
        guard cachedMetricsSignature != newSignature else { return }

        cachedProgressCounts = makeProgressCounts(now: newSignature.today)
        cachedHabitCompletionSets = Dictionary(uniqueKeysWithValues: habitService.habits.map {
            ($0.id, Set($0.completedDates))
        })

        cachedMetricsSnapshot = makeMetricsSnapshot(now: newSignature.today)
        cachedMetricsSignature = newSignature
    }

    private func scheduleMetricsSnapshotRefresh() {
        metricsRefreshGeneration &+= 1
    }

    private func deferredMetricsSnapshotRefresh() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            refreshMetricsSnapshotIfNeeded()
        }
    }

    private func shouldShowSection(_ sid: StatisticsSectionID) -> Bool {
        switch sid {
        case .habitGraph:
            return !habitService.habits.isEmpty
        case .weeklyChart, .todoGrass, .progress:
            return true
        }
    }

    private func estimatedHeight(for sid: StatisticsSectionID) -> CGFloat {
        switch sid {
        case .habitGraph:
            return 80 + CGFloat(habitService.habits.count) * 22
        case .weeklyChart:
            return 104
        case .todoGrass:
            return 184
        case .progress:
            return 128
        }
    }

    private func displacement(for sid: StatisticsSectionID, spacing: CGFloat) -> CGFloat {
        guard let dID = draggingID, dID != sid,
              let origIdx = sectionOrder.firstIndex(of: sid),
              let pendIdx = pendingOrder.firstIndex(of: sid),
              origIdx != pendIdx else { return 0 }
        let slotH = estimatedHeight(for: dID) + spacing
        return CGFloat(pendIdx - origIdx) * slotH
    }

    private func computePendingOrder(
        dragging sid: StatisticsSectionID,
        offset: CGFloat,
        spacing: CGFloat
    ) -> [StatisticsSectionID] {
        guard let fromIdx = sectionOrder.firstIndex(of: sid) else { return sectionOrder }
        let slotH = estimatedHeight(for: sid) + spacing
        let steps = Int((offset / slotH).rounded())
        let toIdx = max(0, min(sectionOrder.count - 1, fromIdx + steps))
        guard toIdx != fromIdx else { return sectionOrder }
        var result = sectionOrder
        result.move(fromOffsets: IndexSet(integer: fromIdx),
                    toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        return result
    }

    private func saveSectionOrder() {
        StatisticsSectionID.save(sectionOrder)
    }

    @ViewBuilder
    private func sectionContent(for sid: StatisticsSectionID) -> some View {
        switch sid {
        case .habitGraph:
            habitGraphSection
        case .weeklyChart:
            weeklyChartSection(snapshot: cachedMetricsSnapshot)
        case .todoGrass:
            todoGrassSection(snapshot: cachedMetricsSnapshot)
        case .progress:
            progressSection
        }
    }

    private func draggableCard(
        sid: StatisticsSectionID,
        layout: ReviewSectionLayout
    ) -> some View {
        let isDragging = draggingID == sid
        let yOffset: CGFloat = isDragging
            ? dragOffset
            : displacement(for: sid, spacing: layout.sectionSpacing)

        return sectionContent(for: sid)
            .padding(.horizontal, layout.cardHorizontalInset)
            .scaleEffect(isDragging ? 1.025 : 1.0, anchor: .center)
            .shadow(color: .black.opacity(isDragging ? 0.22 : 0),
                    radius: isDragging ? 14 : 0, y: isDragging ? 6 : 0)
            .offset(y: yOffset)
            .zIndex(isDragging ? 100 : 0)
            .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.72),
                       value: yOffset)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if draggingID == nil {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                draggingID = sid
                                pendingOrder = sectionOrder
                            }
                        }
                        dragOffset = value.translation.height
                        let newPending = computePendingOrder(
                            dragging: sid,
                            offset: dragOffset,
                            spacing: layout.sectionSpacing
                        )
                        if newPending != pendingOrder {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                                pendingOrder = newPending
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                            sectionOrder = pendingOrder
                            draggingID = nil
                            dragOffset = 0
                        }
                        saveSectionOrder()
                    }
            )
    }

    // MARK: - Weekly Chart (7일 달성 바 차트)

    private func weeklyChartSection(snapshot: ReviewMetricsSnapshot) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "review.weekly.chart.title"), systemImage: "chart.bar.xaxis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(themeService.current.accent)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(snapshot.weeklyCompletion, id: \.date) { day in
                    weekDayBar(day)
                }
            }
            .frame(height: 56)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.platformControlBackground).overlay(RoundedRectangle(cornerRadius: 10).fill(themeService.current.cardTint)))
    }

    private func weekDayBar(_ day: ReviewMetricsSnapshot.DayCompletion) -> some View {
        let cal = Calendar.current
        let done = day.done
        let total = day.total
        let rate = total > 0 ? Double(done) / Double(total) : 0
        let isToday = cal.isDateInToday(day.date)
        let barColor = progressColor(for: rate)
        let maxBarH: CGFloat = 40

        return VStack(spacing: 3) {
            // 바 — bottom-aligned
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(height: maxBarH)

                if total > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isToday
                              ? AnyShapeStyle(themeService.current.gradient)
                              : AnyShapeStyle(barColor.opacity(0.65)))
                        .frame(height: max(maxBarH * CGFloat(rate), 4))
                        .animation(.spring(duration: 0.4), value: rate)
                }
            }
            // 요일 레이블
            Text(weekDayLabel(day.date))
                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private let weekDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "E"; return f
    }()

    private func weekDayLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? String(localized: "review.day.today.short")
            : weekDayFormatter.string(from: date)
    }

    // MARK: - Todo Grass Section (최근 1년 할일 잔디)

    private func todoGrassSection(snapshot: ReviewMetricsSnapshot) -> some View {
        let stats = snapshot.todoGrassStats

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(String(localized: "review.todo.grass.title"), systemImage: "square.grid.3x3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeService.current.accent)
                Spacer()
                if viewModel.isLoadingHistory {
                    ProgressView()
                        .scaleEffect(0.5)
                }
                Text(String(format: String(localized: "review.todo.grass.total"), stats.totalDone, stats.totalTodos))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(stats.totalDone > 0 ? themeService.current.accent : .secondary)
            }

            yearGrassGrid(stats: stats)

            HStack(spacing: 12) {
                todoGrassMetric(
                    title: String(localized: "review.todo.grass.best"),
                    value: "\(stats.maxDoneInDay)/\(stats.maxTotalInDay)"
                )
                Divider().frame(height: 18)
                todoGrassMetric(
                    title: String(localized: "review.todo.grass.streak"),
                    value: String(format: String(localized: "review.todo.grass.days"), stats.currentFullCompletionStreak)
                )
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.platformControlBackground).overlay(RoundedRectangle(cornerRadius: 10).fill(themeService.current.cardTint)))
    }

    private func yearGrassGrid(stats: TodoGrassStats) -> some View {
        let cellSize: CGFloat = 9
        let gap: CGFloat = 2
        let dayLabelWidth: CGFloat = 10
        let dayLabels = todoGrassWeekdayLabels()

        return GeometryReader { geo in
            // 카드 너비에 맞는 최대 주 수 계산 후 가장 최근 N주만 표시
            let available = geo.size.width - dayLabelWidth - 4
            let maxWeeks = max(1, Int(floor((available + gap) / (cellSize + gap))))
            let visibleWeeks = Array(stats.weeks.suffix(maxWeeks))

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: gap) {
                    Color.clear.frame(width: dayLabelWidth, height: cellSize + 2)
                    ForEach(0..<7, id: \.self) { index in
                        Text(index % 2 == 1 ? dayLabels[index] : "")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                            .frame(width: dayLabelWidth, height: cellSize)
                    }
                }

                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(visibleWeeks.enumerated()), id: \.offset) { weekIndex, week in
                        VStack(spacing: gap) {
                            monthLabel(for: week, weekIndex: weekIndex)
                                .frame(height: cellSize + 2)
                            ForEach(0..<7, id: \.self) { dayIndex in
                                grassCell(dayIndex < week.count ? week[dayIndex] : nil, size: cellSize)
                            }
                        }
                        .frame(width: cellSize)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: cellSize + 2 + 7 * (cellSize + gap) - gap)
    }

    @ViewBuilder
    private func monthLabel(for week: [TodoGrassDay?], weekIndex: Int) -> some View {
        let dates = week.compactMap { $0?.date }
        let firstOfMonth = dates.first { Calendar.current.component(.day, from: $0) == 1 }
        let leadingDate = weekIndex == 0 ? dates.first : nil
        let labelDate = firstOfMonth ?? leadingDate.flatMap { date in
            Calendar.current.component(.day, from: date) <= 7 ? date : nil
        }

        if let labelDate {
            Text(todoGrassMonthFormatter.string(from: labelDate))
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            Color.clear
        }
    }

    private func grassCell(_ day: TodoGrassDay?, size: CGFloat) -> some View {
        Group {
            if let day {
                let isToday = Calendar.current.isDateInToday(day.date)
                let label = "\(todoGrassDateLabel(day.date)) · \(day.done)/\(day.total)"
                RoundedRectangle(cornerRadius: 2)
                    .fill(todoGrassColor(for: day))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(isToday ? Color.primary.opacity(0.45) : Color.clear, lineWidth: 1)
                    )
                    .help(label)
                    .accessibilityLabel(label)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.clear)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    private func todoGrassWeekdayLabels() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let start = max(0, Calendar.current.firstWeekday - 1)
        return (0..<7).map { symbols[(start + $0) % symbols.count] }
    }

    private func todoGrassColor(for day: TodoGrassDay) -> Color {
        guard day.total > 0, day.done > 0 else {
            return Color.secondary.opacity(day.total > 0 ? 0.18 : 0.10)
        }
        return accentShade(for: day.rate)
    }

    /// hue만 accent를 따르고, S·B는 절대 고정값 4단계 — 테마·밝기에 무관하게 색 차이가 명확
    /// L1: 연한 tint / L2: 파스텔 / L3: 선명 / L4: 짙음 / L5: accent 원색
    private func accentShade(for rate: Double) -> Color {
        guard let ns = NSColor(themeService.current.accent).usingColorSpace(.sRGB) else {
            return themeService.current.accent
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        switch rate {
        case ..<0.25: return Color(hue: h, saturation: 0.22, brightness: 0.88)  // 연한 tint
        case ..<0.50: return Color(hue: h, saturation: 0.52, brightness: 0.80)  // 파스텔
        case ..<0.75: return Color(hue: h, saturation: 0.80, brightness: 0.74)  // 선명·짙음
        case ..<1.0:  return Color(hue: h, saturation: min(s, 1.0), brightness: max(b, 0.62)) // accent에 근접
        default:      return themeService.current.accent                          // accent 원색
        }
    }

    private func todoGrassMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private let todoGrassDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d (E)"
        return f
    }()

    private let todoGrassMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private func todoGrassDateLabel(_ date: Date) -> String {
        todoGrassDateFormatter.string(from: date)
    }

    // MARK: - Habit Graph Section (주간 달성률 추이)

    // DateFormatter는 뷰 수명 동안 재사용 (매 호출 생성 방지)
    private let graphDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 편집 시트에 보여줄 "N일간 · Apr 6 – Apr 12" 스타일 요약.
    /// start > end 인 stale 입력도 방어적으로 swap 후 계산.
    private func rangeSummary(start: Date, end: Date) -> String {
        let cal = Calendar.current
        let s = cal.startOfDay(for: min(start, end))
        let e = cal.startOfDay(for: max(start, end))
        let days = (cal.dateComponents([.day], from: s, to: e).day ?? 0) + 1
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        // %d days 는 단수 "1 days" 깨짐 — 1일일 때 별도 키로 분기.
        let daysLabel: String
        if days == 1 {
            daysLabel = String(localized: "habit.field.range.days.one")
        } else {
            daysLabel = String.localizedStringWithFormat(
                String(localized: "habit.field.range.days"), days)
        }
        return "\(daysLabel) · \(fmt.string(from: s)) – \(fmt.string(from: e))"
    }

    /// 특정 습관의 최근 4주 주간 달성률 (0.0~1.0) 배열 (오래된 순, index 0=4주전, 3=이번주)
    private func weeklyRates(for habit: Habit) -> [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let completedDates = cachedHabitCompletionSets[habit.id] ?? []
        // reversed: weekOffset 3→2→1→0 → rates[0]=4주전, rates[3]=이번주
        return (0..<4).reversed().map { weekOffset in
            let count = (0..<7).filter { dayOffset in
                guard let day = cal.date(byAdding: .day, value: -(weekOffset * 7 + dayOffset), to: today) else { return false }
                return completedDates.contains(graphDateFormatter.string(from: day))
            }.count
            return min(Double(count) / Double(max(1, habit.weeklyTarget)), 1.0)
        }
    }

    // 4주 라벨 (index 0=4주전, 1=3주전, 2=지난주, 3=이번주) — rates 순서와 1:1 매칭
    private let graphWeekLabels: [LocalizedStringKey] = [
        "habit.graph.4weeksago",
        "habit.graph.3weeksago",
        "habit.graph.lastweek",
        "habit.graph.thisweek",
    ]

    /// 모든 습관의 이번 주 전체 평균 달성률
    private var habitsWeeklyAverage: Double {
        guard !habitService.habits.isEmpty else { return 0 }
        let rates = habitService.habits.map { habit in
            let rates = weeklyRates(for: habit)
            return rates.last ?? 0  // 이번 주
        }
        return rates.reduce(0, +) / Double(rates.count)
    }

    private var habitGraphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 헤더 + 이번 주 전체 평균
            HStack {
                Label(String(localized: "habit.graph.title"), systemImage: "flame.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeService.current.accent)
                Spacer()
                let weekly = habitsWeeklyAverage
                if weekly > 0 {
                    Text(String(format: NSLocalizedString("review.habit.weekly.average", comment: ""), Int(weekly * 100)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(weekly >= 0.8 ? themeService.current.accent : weekly >= 0.5 ? .orange : .secondary)
                }
            }

            if habitsWeeklyAverage == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 10))
                    Text(String(localized: "review.habit.empty.encourage"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            // 날짜 컬럼 헤더 (최근 28일, 7열 기준)
            habitGrassHeader

            // 습관별 잔디 행
            VStack(spacing: 5) {
                ForEach(habitService.habits) { habit in
                    habitGrassRow(habit)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.platformControlBackground).overlay(RoundedRectangle(cornerRadius: 10).fill(themeService.current.cardTint)))
    }

    /// 4주 헤더: 주 라벨 (4주전 / 3주전 / 지난주 / 이번주)
    private var habitGrassHeader: some View {
        HStack(spacing: 3) {
            Spacer().frame(width: 68)
            ForEach(graphWeekLabels.indices, id: \.self) { i in
                Text(graphWeekLabels[i])
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            Spacer().frame(width: 24)
        }
    }

    /// 특정 날짜에 습관이 완료됐는지 확인 (28일 범위)
    private func grassCompleted(_ habit: Habit, daysAgo: Int) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let d = cal.date(byAdding: .day, value: -daysAgo, to: today) else { return false }
        return cachedHabitCompletionSets[habit.id, default: []].contains(graphDateFormatter.string(from: d))
    }

    /// 이번 주(최근 7일) 달성 횟수
    private func thisWeekCount(_ habit: Habit) -> Int {
        (0..<7).filter { grassCompleted(habit, daysAgo: $0) }.count
    }

    /// 주간 달성률 (weekOffset: 0=이번주, 1=지난주, ... 3=4주전)
    private func weekRate(_ habit: Habit, weekOffset: Int) -> Double {
        let count = (0..<7).filter { grassCompleted(habit, daysAgo: weekOffset * 7 + $0) }.count
        return min(1.0, Double(count) / Double(max(1, habit.weeklyTarget)))
    }

    private func habitGrassRow(_ habit: Habit) -> some View {
        let accent = habit.accentColor
        let thisRate = weekRate(habit, weekOffset: 0)

        return HStack(spacing: 3) {
            // 이름
            HStack(spacing: 3) {
                Text(habit.emoji).font(.system(size: 10))
                Text(habit.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 68, alignment: .leading)

            // 4주 × 7일 잔디 (오래된 순: 왼=4주전, 오=이번주)
            // weekIdx 0=4주전, 3=이번주
            ForEach(0..<4, id: \.self) { weekIdx in
                let weekOffset = 3 - weekIdx  // 3=4주전, 0=이번주
                HStack(spacing: 1.5) {
                    ForEach(0..<7, id: \.self) { dayIdx in
                        // dayIdx 0=해당 주 가장 오래된 날, 6=가장 최근
                        let daysAgo = weekOffset * 7 + (6 - dayIdx)
                        let done = grassCompleted(habit, daysAgo: daysAgo)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(done ? accent : Color.secondary.opacity(0.12))
                            .frame(height: 9)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // 이번 주 달성률
            Text(String(format: "%.0f%%", thisRate * 100))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(thisRate >= 0.8 ? accent : thisRate >= 0.5 ? .orange : .secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .frame(height: 18)
    }

    // MARK: - Progress Section

    /// 4단계 discrete opacity — 바 차트에서 레벨 간 색 차이가 명확하도록
    private func progressColor(for rate: Double) -> Color {
        let clamped = max(0, min(1, rate))
        let opacity: Double = clamped < 0.25 ? 0.42
                            : clamped < 0.50 ? 0.62
                            : clamped < 0.75 ? 0.82
                            : 1.0
        return themeService.current.accent.opacity(opacity)
    }

    private var progressSection: some View {
        let count = cachedProgressCounts.count(for: selectedPeriod)
        let done = count.done
        let total = count.total
        let rate = total > 0 ? Double(done) / Double(total) : 0
        let barColor = progressColor(for: rate)

        return VStack(alignment: .leading, spacing: 10) {
            // 기간 탭 — 언더라인 스타일 (탭 색도 현재 달성률 색으로)
            HStack(spacing: 0) {
                ForEach([
                    (GoalService.CompletionPeriod.day,   String(localized: "common.today")),
                    (.week,  String(localized: "review.period.week")),
                    (.month, String(localized: "review.period.month")),
                    (.year,  String(localized: "review.period.year")),
                ], id: \.1) { period, label in
                    let isSelected = selectedPeriod == period
                    Button { selectedPeriod = period } label: {
                        VStack(spacing: 3) {
                            Text(label)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            Capsule()
                                .fill(isSelected ? barColor : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.25), value: isSelected)
                }
            }

            if total > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    // 카운트 + 비율 한 줄
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(done)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("/ \(total)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "review.completion.rate"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(rate * 100))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(barColor)
                            .animation(.easeInOut(duration: 0.4), value: rate)
                    }

                    // 단색 진행 바 — 진행률에 따라 색이 빨강→노랑→연두로 변함
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // 배경 트랙
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.12))
                            // 진행된 영역 — 단색 (rate에 따라 색 자체가 변함)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(barColor)
                                .frame(width: max(geo.size.width * CGFloat(rate), rate > 0 ? 8 : 0))
                                .animation(.spring(duration: 0.5), value: rate)
                        }
                    }
                    .frame(height: 10)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "review.no.todos"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.platformControlBackground).overlay(RoundedRectangle(cornerRadius: 10).fill(themeService.current.cardTint)))
    }

    // MARK: - Progress Helpers

    private func makeProgressCounts(now: Date) -> CachedStatisticsProgressCounts {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        cal.minimumDaysInFirstWeek = 1

        return CachedStatisticsProgressCounts(
            day: makeDayProgressCount(now: now),
            week: makePeriodProgressCount(component: .weekOfYear, now: now, calendar: cal),
            month: makePeriodProgressCount(component: .month, now: now, calendar: cal),
            year: makePeriodProgressCount(component: .year, now: now, calendar: cal)
        )
    }

    private func makeDayProgressCount(now: Date) -> StatisticsProgressCount {
        let items = viewModel.itemsForDate(Calendar.current.startOfDay(for: now))
        let done = items.filter { item in
            switch item {
            case .event(let e): return viewModel.isEventCompleted(e.id)
            case .todo(let t):  return t.isCompleted
            }
        }.count
        PlanitLoggers.review.info(
            "makeDayProgressCount items=\(items.count, privacy: .public) done=\(done, privacy: .public)"
        )
        return StatisticsProgressCount(done: done, total: items.count)
    }

    private func makePeriodProgressCount(
        component: Calendar.Component,
        now: Date,
        calendar cal: Calendar
    ) -> StatisticsProgressCount {
        guard let interval = cal.dateInterval(of: component, for: now) else {
            return .zero
        }

        let todoEventIds = Set(viewModel.todos.compactMap { $0.googleEventId })
        let completedIDs = viewModel.completedEventIDs

        let events = viewModel.calendarEvents.filter { event in
            guard !todoEventIds.contains(event.id) else { return false }
            let eventEnd = event.endDate > event.startDate ? event.endDate : event.startDate.addingTimeInterval(1)
            return event.startDate < interval.end && eventEnd > interval.start
        }

        let localTodos = viewModel.todos.filter {
            let d = cal.startOfDay(for: $0.date)
            return d >= interval.start && d < interval.end
        }
        let reminderTodos = viewModel.appleReminders.filter {
            let d = cal.startOfDay(for: $0.date)
            return d >= interval.start && d < interval.end
        }
        let baseTodos = localTodos + reminderTodos

        let doneTodos = baseTodos.filter { todo in
            todo.isCompleted || (todo.googleEventId.map { completedIDs.contains($0) } ?? false)
        }.count
        let doneEvents = events.filter { completedIDs.contains($0.id) }.count

        return StatisticsProgressCount(done: doneTodos + doneEvents, total: baseTodos.count + events.count)
    }

    // MARK: - Formatting Helpers

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current; return f
    }()

    private func formatTime(_ date: Date) -> String { timeFormatter.string(from: date) }
}
