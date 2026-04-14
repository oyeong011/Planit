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
    // 저녁 리뷰 중 사용자가 마킹한 이벤트 추적
    @State private var reviewedItems: [(title: String, status: CompletionStatus, start: Date, end: Date)] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if showPlanResult, let plan = aiPlan {
                aiPlanResultView(plan)
            } else if reviewService.currentMode == .evening {
                eveningReviewContent
            } else {
                dailyModeContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: headerIcon)
                .font(.system(size: 13))
                .foregroundStyle(headerColor)

            Text(headerTitle)
                .font(.system(size: 14, weight: .bold))

            if reviewService.currentMode == .evening && !showPlanResult {
                Text("· \(todayDateString)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerIcon: String {
        if showPlanResult { return "calendar.badge.checkmark" }
        return reviewService.currentMode == .evening ? "moon.fill" : "calendar.badge.clock"
    }

    private var headerColor: Color {
        if showPlanResult { return .green }
        return reviewService.currentMode == .evening ? .indigo : .purple
    }

    private var headerTitle: String {
        if showPlanResult { return "내일 계획 완성" }
        return reviewService.currentMode == .evening ? "저녁 리뷰" : "오늘의 조정"
    }

    // MARK: - Evening Review Content

    private var eveningReviewContent: some View {
        VStack(spacing: 0) {
            if reviewService.suggestions.isEmpty {
                emptyTodayState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("오늘 돌아보기")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(Array(reviewService.suggestions.enumerated()), id: \.element.id) { idx, suggestion in
                            eveningCard(suggestion, index: idx)
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack {
                if !reviewService.suggestions.isEmpty {
                    Button { moveAllToTomorrow() } label: {
                        Text("모두 내일로")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button { generatePlan() } label: {
                    if isGenerating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("계획 생성 중...")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.indigo)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11))
                            Text("내일 계획 자동 생성")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.indigo))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty Today State

    private var emptyTodayState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "moon.stars")
                .font(.system(size: 28))
                .foregroundStyle(.indigo)
            Text("오늘 지난 일정이 없어요")
                .font(.system(size: 13, weight: .semibold))
            Text("바로 내일 계획을 생성할 수 있어요")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Evening Card

    private func eveningCard(_ suggestion: ReviewSuggestion, index: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .medium))
                Text(suggestion.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Button { markCompletion(at: index, status: .done) } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("완료")

                Button { markCompletion(at: index, status: .moved) } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("내일로")

                Button { markCompletion(at: index, status: .skipped) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("건너뜀")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Daily Mode Content (simplified)

    private var dailyModeContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    weeklyProgressCard

                    if reviewService.suggestions.isEmpty {
                        VStack(spacing: 6) {
                            Spacer().frame(height: 12)
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 26))
                                .foregroundStyle(.green)
                            Text("순조롭게 진행 중이에요")
                                .font(.system(size: 12, weight: .semibold))
                            Text("저녁에 내일 계획을 자동으로 생성해 드려요")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(Array(reviewService.suggestions.enumerated()), id: \.element.id) { idx, s in
                            morningCard(s, index: idx)
                        }
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    reviewService.dismissReview()
                    onDismiss()
                } label: {
                    Text("확인")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Morning Card (daily mode suggestions)

    private func morningCard(_ suggestion: ReviewSuggestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: iconFor(suggestion.type))
                    .font(.system(size: 9))
                Text(labelFor(suggestion.type))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(colorFor(suggestion.type))

            Text(suggestion.title)
                .font(.system(size: 12, weight: .semibold))

            Text(suggestion.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if suggestion.status != .accepted {
                HStack(spacing: 6) {
                    Button { acceptSuggestion(at: index) } label: {
                        HStack {
                            Text("추가")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.purple))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { declineSuggestion(at: index) } label: {
                        Text("건너뜀")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(
            suggestion.status == .accepted
                ? Color.green.opacity(0.06)
                : Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Progress Card

    /// 기간별 (완료, 전체) 카운트 반환
    private func progressCounts(for period: GoalService.CompletionPeriod) -> (done: Int, total: Int) {
        // 그레고리력, 일요일 시작, minimumDaysInFirstWeek=1로 고정 (로케일 독립)
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

        // 할일로 등록된 Google 이벤트 ID — calendarEvents와 중복 제외
        let todoEventIds = Set(viewModel.todos.compactMap { $0.googleEventId })
        let completedIDs = viewModel.completedEventIDs

        // 이벤트: 구간 겹침 테스트 (멀티데이·종일 이벤트 포함)
        let events = viewModel.calendarEvents.filter { event in
            guard !todoEventIds.contains(event.id) else { return false }
            let eventEnd = event.endDate > event.startDate ? event.endDate : event.startDate.addingTimeInterval(1)
            return event.startDate < interval.end && eventEnd > interval.start
        }

        // 할일: 모든 기간 동일 로직 — appleReminders는 캐시 날짜와 interval이 일치할 때만 포함됨
        let localTodos = viewModel.todos.filter {
            let d = cal.startOfDay(for: $0.date)
            return d >= interval.start && d < interval.end
        }
        let reminderTodos = viewModel.appleReminders.filter {
            let d = cal.startOfDay(for: $0.date)
            return d >= interval.start && d < interval.end
        }
        let baseTodos = localTodos + reminderTodos

        // 완료 판정: todo+event 쌍은 어느 쪽이든 완료면 done
        let doneTodos = baseTodos.filter { todo in
            todo.isCompleted || (todo.googleEventId.map { completedIDs.contains($0) } ?? false)
        }.count
        let doneEvents = events.filter { completedIDs.contains($0.id) }.count

        return (doneTodos + doneEvents, baseTodos.count + events.count)
    }

    private var weeklyProgressCard: some View {
        let (done, total) = progressCounts(for: selectedPeriod)
        let rate = total > 0 ? Double(done) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 8) {
            // 기간 탭
            HStack(spacing: 2) {
                ForEach([
                    (GoalService.CompletionPeriod.day, "오늘"),
                    (.week, "이번주"),
                    (.month, "이번달"),
                    (.year, "올해"),
                ], id: \.1) { period, label in
                    Button { selectedPeriod = period } label: {
                        Text(label)
                            .font(.system(size: 10, weight: selectedPeriod == period ? .semibold : .regular))
                            .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selectedPeriod == period ? Color.purple : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))

            if total > 0 {
                HStack {
                    Text("할일 달성률")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(rate * 100))%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(rate >= 0.7 ? .green : rate >= 0.4 ? .orange : .red)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(rate >= 0.7 ? Color.green : rate >= 0.4 ? Color.orange : Color.red)
                            .frame(width: geo.size.width * CGFloat(rate))
                            .animation(.easeInOut(duration: 0.3), value: rate)
                    }
                }
                .frame(height: 6)
                Text("\(done) / \(total) 완료")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("등록된 할일이 없어요")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - AI Plan Result View

    private func aiPlanResultView(_ plan: ReviewAIPlan) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 헤더
                    HStack(spacing: 10) {
                        Image(systemName: plan.isEmpty ? "calendar.badge.checkmark" : "calendar.badge.plus")
                            .font(.system(size: 18))
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tomorrowDateString)
                                .font(.system(size: 13, weight: .bold))
                            if !plan.summary.isEmpty {
                                Text(plan.summary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.07)))

                    if plan.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 26))
                                .foregroundStyle(.green)
                            Text("내일 일정이 이미 충분해요")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        // 캘린더에 추가된 이벤트 목록
                        VStack(alignment: .leading, spacing: 6) {
                            Label("캘린더에 추가됨", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)

                            ForEach(Array(plan.events.enumerated()), id: \.offset) { _, event in
                                aiPlanEventRow(event)
                            }
                        }
                    }

                    if let error = plan.error {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10))
                            Text(error)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    reviewService.dismissReview()
                    onDismiss()
                } label: {
                    Text("닫기")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func aiPlanEventRow(_ event: ReviewAIPlan.PlannedEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.green)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                Text("\(formatTime(event.start))~\(formatTime(event.end))")
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
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.green.opacity(0.05)))
    }

    // MARK: - Actions

    private func generatePlan() {
        isGenerating = true

        // 아직 마킹 안 된 항목 = 오늘 못 한 것 → 내일로
        let remaining = reviewService.suggestions.map { s in
            (title: s.title,
             status: CompletionStatus.moved,
             start: s.proposedStart ?? Date(),
             end: s.proposedEnd ?? Date())
        }
        moveAllToTomorrow()

        let allReviewed = reviewedItems + remaining

        Task {
            // AI가 내일 계획 생성
            let plan = await reviewService.generateAITomorrowPlan(reviewed: allReviewed)

            // 각 이벤트를 실제로 캘린더에 추가
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
            eventId: s.proposedTitle ?? s.title,
            goalId: s.goalId,
            status: status,
            plannedMinutes: max(minutes, 30)
        )
        // AI에게 넘길 리뷰 데이터 기록
        reviewedItems.append((
            title: s.title,
            status: status,
            start: s.proposedStart ?? Date(),
            end: s.proposedEnd ?? Date()
        ))
        reviewService.suggestions.remove(at: index)
    }

    private func moveAllToTomorrow() {
        for i in (0..<reviewService.suggestions.count).reversed() {
            markCompletion(at: i, status: .moved)
        }
    }

    // MARK: - Helpers

    private var todayDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M월 d일"
        fmt.locale = Locale(identifier: "ko_KR")
        return fmt.string(from: Date())
    }

    private var tomorrowDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M월 d일 (E)"
        fmt.locale = Locale(identifier: "ko_KR")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return fmt.string(from: tomorrow)
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return fmt.string(from: date)
    }

    // MARK: - Styling Helpers

    private func iconFor(_ type: SuggestionType) -> String {
        switch type {
        case .carryover: return "arrow.uturn.right"
        case .deadline: return "exclamationmark.triangle"
        case .habitGap: return "repeat"
        case .deadlineSpread: return "calendar.badge.clock"
        case .prep: return "doc.text"
        case .focusQuota: return "brain.head.profile"
        case .health: return "heart"
        case .buffer: return "car"
        }
    }

    private func labelFor(_ type: SuggestionType) -> String {
        switch type {
        case .carryover: return "미완료"
        case .deadline: return "마감 임박"
        case .habitGap: return "습관"
        case .deadlineSpread: return "분산"
        case .prep: return "준비"
        case .focusQuota: return "집중"
        case .health: return "건강"
        case .buffer: return "이동"
        }
    }

    private func colorFor(_ type: SuggestionType) -> Color {
        switch type {
        case .carryover: return .orange
        case .deadline: return .red
        case .habitGap: return .blue
        case .deadlineSpread: return .purple
        case .prep: return .teal
        case .focusQuota: return .indigo
        case .health: return .green
        case .buffer: return .brown
        }
    }
}
