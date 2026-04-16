import SwiftUI

struct ReviewView: View {
    @ObservedObject var reviewService: ReviewService
    @ObservedObject var goalService: GoalService
    @ObservedObject var viewModel: CalendarViewModel
    let onCreateEvent: (String, Date, Date) -> Void
    let onDismiss: () -> Void

    @State private var isGenerating = false
    @State private var showPlanResult = false
    @State private var aiPlan: ReviewAIPlan?
    @State private var selectedPeriod: GoalService.CompletionPeriod = .day

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if showPlanResult, let plan = aiPlan {
                planResultView(plan)
            } else if reviewService.currentMode == .evening {
                eveningView
            } else {
                morningView
            }
        }
        .background(Color.platformWindowBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(headerColor.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: headerIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(headerColor)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .bold))
                Text(todayDateString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.secondary.opacity(0.1)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerIcon: String {
        if showPlanResult { return "calendar.badge.checkmark" }
        return reviewService.currentMode == .evening ? "moon.fill" : "sun.max.fill"
    }

    private var headerColor: Color {
        if showPlanResult { return .green }
        return reviewService.currentMode == .evening ? .indigo : .orange
    }

    private var headerTitle: String {
        if showPlanResult { return String(localized: "review.plan.complete.title") }
        return reviewService.currentMode == .evening
            ? String(localized: "review.evening.title")
            : String(localized: "review.daily.title")
    }

    // MARK: - Morning View

    private var morningView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    progressSection
                    suggestionsSection
                }
                .padding(10)
            }

            Divider()

            HStack(spacing: 8) {
                // 제안이 있을 때만 "전부 추가" 버튼 표시
                if !reviewService.suggestions.isEmpty {
                    Button {
                        acceptAllSuggestions()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.square")
                                .font(.system(size: 10))
                            Text(String(localized: "review.accept.all"))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    reviewService.dismissReview()
                    onDismiss()
                } label: {
                    Text(String(localized: "review.ok.button"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.orange))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Progress Section

    /// HSB 공간에서 빨강(0°) → 노랑(60°) → 연두(120°)를 rate에 따라 연속 보간
    /// pastel 톤: saturation 0.48, brightness 0.90
    private func progressColor(for rate: Double) -> Color {
        let clamped = max(0, min(1, rate))
        // hue: 0.0(빨강) → 0.167(노랑) → 0.333(연두)
        let hue = clamped * (120.0 / 360.0)
        return Color(hue: hue, saturation: 0.48, brightness: 0.90)
    }

    private var progressSection: some View {
        let (done, total) = progressCounts(for: selectedPeriod)
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.platformControlBackground))
    }

    // MARK: - Suggestions Section

    @ViewBuilder
    private var suggestionsSection: some View {
        if reviewService.suggestions.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "review.on.track"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "review.evening.auto.plan"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.06)))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "review.today.lookback"), systemImage: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                ForEach(Array(reviewService.suggestions.enumerated()), id: \.element.id) { idx, s in
                    morningSuggestionCard(s, index: idx)
                }
            }
        }
    }

    private func morningSuggestionCard(_ s: ReviewSuggestion, index: Int) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(colorFor(s.type))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: iconFor(s.type))
                        .font(.system(size: 9))
                        .foregroundStyle(colorFor(s.type))
                    Text(labelFor(s.type))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(colorFor(s.type))
                }
                Text(s.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(s.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if s.status != .accepted {
                    HStack(spacing: 6) {
                        Button { acceptSuggestion(at: index) } label: {
                            Text(String(localized: "review.add.button"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(colorFor(s.type)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button { declineSuggestion(at: index) } label: {
                            Text(String(localized: "review.skip.button"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(s.status == .accepted ? colorFor(s.type).opacity(0.06) : Color.platformControlBackground)
        )
    }

    // MARK: - Evening View

    // 오늘 이벤트 (Google Calendar + Apple Calendar)
    private var todayEvents: [CalendarEvent] {
        viewModel.eventsForDate(Calendar.current.startOfDay(for: Date()))
            .filter { !$0.isAllDay }
    }

    // 오늘 할 일
    private var todayTodos: [TodoItem] {
        viewModel.todosForDate(Calendar.current.startOfDay(for: Date()))
    }

    // 자동 계산: 완료한 항목 수
    private var todayDoneCount: Int {
        let doneEvents = todayEvents.filter { viewModel.isEventCompleted($0.id) }.count
        let doneTodos = todayTodos.filter { $0.isCompleted }.count
        return doneEvents + doneTodos
    }

    // 자동 계산: 전체 항목 수
    private var todayTotalCount: Int {
        todayEvents.count + todayTodos.count
    }

    // MARK: - Evening Stats Row (자동 계산)

    private var eveningStatsRow: some View {
        let done = todayDoneCount
        let total = todayTotalCount
        let rate = total > 0 ? Double(done) / Double(total) : 0
        let color = progressColor(for: rate)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(Int(rate * 100))%")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(color)
                    Text(String(localized: "review.achievement"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 3)
                }
                Text(String(format: String(localized: "review.count.done"), done, total))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: max(geo.size.width * CGFloat(rate), rate > 0 ? 8 : 0))
                        .animation(.spring(duration: 0.5), value: rate)
                }
            }
            .frame(width: 110, height: 10)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.06)))
    }

    // MARK: - Evening View (읽기 전용 — AI가 자동 분석)

    private var eveningView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    eveningStatsRow
                        .padding(.horizontal, 10)
                        .padding(.top, 10)

                    if todayEvents.isEmpty && todayTodos.isEmpty {
                        // 오늘 일정 없음
                        VStack(spacing: 10) {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.indigo)
                            Text(String(localized: "review.no.past.events"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(String(localized: "review.generate.now.hint"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        // 오늘 이벤트 (읽기 전용)
                        if !todayEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(String(localized: "review.today.lookback"), systemImage: "calendar")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)

                                ForEach(todayEvents) { event in
                                    eveningReadOnlyEventRow(event)
                                }
                            }
                        }

                        // 오늘 할 일 (읽기 전용)
                        if !todayTodos.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(String(localized: "review.today.todos"), systemImage: "checkmark.square")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)

                                ForEach(todayTodos) { todo in
                                    eveningReadOnlyTodoRow(todo)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }

            Divider()

            // 단일 AI 버튼
            Button { generatePlan() } label: {
                HStack(spacing: 7) {
                    if isGenerating {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(String(localized: "review.generating.button"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 13))
                        Text(String(localized: "review.generate.tomorrow"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(.indigo))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // 읽기 전용 이벤트 행
    private func eveningReadOnlyEventRow(_ event: CalendarEvent) -> some View {
        let done = viewModel.isEventCompleted(event.id)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(done ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(done ? .primary : .primary)
                    .strikethrough(done)
                    .lineLimit(1)
                Text("\(formatTime(event.startDate)) – \(formatTime(event.endDate))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.platformControlBackground))
        .padding(.horizontal, 10)
    }

    // 읽기 전용 할 일 행
    private func eveningReadOnlyTodoRow(_ todo: TodoItem) -> some View {
        let done = todo.isCompleted
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(done ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 3)
            Text(todo.title)
                .font(.system(size: 12, weight: .medium))
                .strikethrough(done)
                .lineLimit(1)
            Spacer()
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.platformControlBackground))
        .padding(.horizontal, 10)
    }

    // MARK: - AI Plan Result View

    private func planResultView(_ plan: ReviewAIPlan) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 내일 날짜 헤더
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.indigo.opacity(0.12))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: plan.isEmpty ? "calendar.badge.checkmark" : "calendar.badge.plus")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.indigo)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tomorrowDateString)
                                .font(.system(size: 13, weight: .bold))
                            Text(plan.summary.isEmpty ? String(localized: "review.added.to.calendar") : plan.summary)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.06)))

                    if plan.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                            Text(String(localized: "review.tomorrow.sufficient"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.06)))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(plan.events.enumerated()), id: \.offset) { _, event in
                                planEventRow(event)
                            }
                        }
                    }

                    if let error = plan.error {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.orange.opacity(0.07)))
                    }
                }
                .padding(10)
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    reviewService.dismissReview()
                    onDismiss()
                } label: {
                    Text(String(localized: "review.close.button"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.indigo))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func planEventRow(_ event: ReviewAIPlan.PlannedEvent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.indigo)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                Text("\(formatTime(event.start)) – \(formatTime(event.end))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.platformControlBackground))
    }

    // MARK: - Actions

    private func acceptAllSuggestions() {
        for i in (0..<reviewService.suggestions.count).reversed() {
            acceptSuggestion(at: i)
        }
    }

    private func generatePlan() {
        isGenerating = true
        // 앱이 이미 알고 있는 완료 상태 자동 수집 (수동 입력 불필요)
        var reviewed: [(title: String, status: CompletionStatus, start: Date, end: Date)] = []
        for event in todayEvents {
            let status: CompletionStatus = viewModel.isEventCompleted(event.id) ? .done : .moved
            reviewed.append((title: event.title, status: status,
                             start: event.startDate, end: event.endDate))
        }
        for todo in todayTodos {
            let status: CompletionStatus = todo.isCompleted ? .done : .moved
            reviewed.append((title: todo.title, status: status,
                             start: todo.date,
                             end: todo.date.addingTimeInterval(1800)))
        }

        Task {
            let plan = await reviewService.generateAITomorrowPlan(reviewed: reviewed)
            for event in plan.events {
                onCreateEvent(event.title, event.start, event.end)
            }
            aiPlan = plan
            isGenerating = false
            showPlanResult = true
        }
    }

    private func acceptSuggestion(at index: Int) {
        guard index < reviewService.suggestions.count else { return }
        let s = reviewService.suggestions[index]
        if let start = s.proposedStart, let end = s.proposedEnd, let title = s.proposedTitle {
            onCreateEvent(title, start, end)
        }
        reviewService.suggestions[index].status = .accepted
        reviewService.suggestions.remove(at: index)
    }

    private func declineSuggestion(at index: Int) {
        guard index < reviewService.suggestions.count else { return }
        reviewService.suggestions[index].status = .declined
        reviewService.suggestions.remove(at: index)
    }

    private func markCompletion(at index: Int, status: CompletionStatus) {
        guard index < reviewService.suggestions.count else { return }
        let s = reviewService.suggestions[index]
        let minutes = Int((s.proposedEnd ?? Date()).timeIntervalSince(s.proposedStart ?? Date()) / 60)
        goalService.markCompletion(
            eventId: s.sourceEventId ?? s.title,
            eventTitle: s.title,
            goalId: s.goalId,
            status: status,
            plannedMinutes: max(minutes, 30)
        )
        reviewService.suggestions.remove(at: index)
    }

    // MARK: - Progress Helpers

    private func progressCounts(for period: GoalService.CompletionPeriod) -> (done: Int, total: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        cal.minimumDaysInFirstWeek = 1

        let component: Calendar.Component
        switch period {
        case .day:   component = .day
        case .week:  component = .weekOfYear
        case .month: component = .month
        case .year:  component = .year
        }
        guard let interval = cal.dateInterval(of: component, for: Date()) else { return (0, 0) }

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

        return (doneTodos + doneEvents, baseTodos.count + events.count)
    }

    // MARK: - Formatting Helpers

    private var todayDateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: Date())
    }

    private var tomorrowDateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return fmt.string(from: tomorrow)
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date)
    }

    // MARK: - Type Styling

    private func iconFor(_ type: SuggestionType) -> String {
        switch type {
        case .carryover:      return "arrow.uturn.right"
        case .deadline:       return "exclamationmark.triangle"
        case .habitGap:       return "repeat"
        case .deadlineSpread: return "calendar.badge.clock"
        case .prep:           return "doc.text"
        case .focusQuota:     return "brain.head.profile"
        case .health:         return "heart"
        case .buffer:         return "car"
        }
    }

    private func labelFor(_ type: SuggestionType) -> String {
        switch type {
        case .carryover:      return String(localized: "suggestion.carryover")
        case .deadline:       return String(localized: "suggestion.deadline")
        case .habitGap:       return String(localized: "suggestion.habit")
        case .deadlineSpread: return String(localized: "suggestion.spread")
        case .prep:           return String(localized: "suggestion.prep")
        case .focusQuota:     return String(localized: "suggestion.focus")
        case .health:         return String(localized: "suggestion.health")
        case .buffer:         return String(localized: "suggestion.buffer")
        }
    }

    private func colorFor(_ type: SuggestionType) -> Color {
        switch type {
        case .carryover:      return .orange
        case .deadline:       return .red
        case .habitGap:       return .blue
        case .deadlineSpread: return .purple
        case .prep:           return .teal
        case .focusQuota:     return .indigo
        case .health:         return .green
        case .buffer:         return .brown
        }
    }
}
