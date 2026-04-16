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
    @State private var reviewedItems: [(title: String, status: CompletionStatus, start: Date, end: Date)] = []
    // 저녁 리뷰: 카드별 상태 표시 (선택 후 잠깐 보여주고 제거)
    @State private var cardStatuses: [String: CompletionStatus] = [:]
    // 저녁 리뷰: 숨겨진 todo IDs
    @State private var hiddenTodoIDs: Set<UUID> = []

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

    private var progressSection: some View {
        let (done, total) = progressCounts(for: selectedPeriod)
        let rate = total > 0 ? Double(done) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 10) {
            // 기간 탭
            HStack(spacing: 2) {
                ForEach([
                    (GoalService.CompletionPeriod.day,   String(localized: "common.today")),
                    (.week,  String(localized: "review.period.week")),
                    (.month, String(localized: "review.period.month")),
                    (.year,  String(localized: "review.period.year")),
                ], id: \.1) { period, label in
                    Button { selectedPeriod = period } label: {
                        Text(label)
                            .font(.system(size: 10, weight: selectedPeriod == period ? .semibold : .regular))
                            .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedPeriod == period ? Color.orange : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.08)))

            if total > 0 {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%d / %d", done, total))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(rate >= 0.7 ? .green : rate >= 0.4 ? .orange : .red)
                        Text(String(localized: "review.completion.rate"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(rate * 100))%")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(rate >= 0.7 ? Color.green : rate >= 0.4 ? Color.orange : Color.red)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: rate >= 0.7 ? [.green, .mint] : rate >= 0.4 ? [.orange, .yellow] : [.red, .orange],
                                    startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: max(geo.size.width * CGFloat(rate), rate > 0 ? 8 : 0))
                            .animation(.spring(duration: 0.4), value: rate)
                    }
                }
                .frame(height: 8)
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

    private var todayPendingTodos: [TodoItem] {
        let cal = Calendar.current
        let localPending = viewModel.todos.filter {
            !$0.isCompleted && cal.isDateInToday($0.date) && !hiddenTodoIDs.contains($0.id)
        }
        let reminderPending = viewModel.appleReminders.filter {
            !$0.isCompleted && cal.isDateInToday($0.date) && !hiddenTodoIDs.contains($0.id)
        }
        return localPending + reminderPending
    }

    private var eveningStatsRow: some View {
        let (done, total) = progressCounts(for: .day)
        let rate = total > 0 ? Double(done) / Double(total) : 0

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(Int(rate * 100))%")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(rate >= 0.7 ? Color.green : rate >= 0.4 ? Color.orange : Color.red)
                    Text("달성")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 3)
                }
                Text("\(done) / \(total)개 완료")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: rate >= 0.7 ? [.green, .mint] : rate >= 0.4 ? [.orange, .yellow] : [.red, .orange],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * CGFloat(rate), rate > 0 ? 8 : 0))
                        .animation(.spring(duration: 0.4), value: rate)
                }
            }
            .frame(width: 100, height: 8)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(
            rate >= 0.7 ? Color.green.opacity(0.06) : rate >= 0.4 ? Color.orange.opacity(0.06) : Color.red.opacity(0.06)
        ))
    }

    @ViewBuilder
    private var eveningEventsSection: some View {
        if !reviewService.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(String(localized: "review.today.lookback"), systemImage: "list.bullet.clipboard")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%d", reviewService.suggestions.count))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.indigo.opacity(0.1)))
                }
                .padding(.horizontal, 2)
                ForEach(Array(reviewService.suggestions.enumerated()), id: \.element.id) { idx, s in
                    eveningCard(s, index: idx)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private var eveningTodosSection: some View {
        let pending = todayPendingTodos
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(String(localized: "review.today.todos"), systemImage: "checkmark.square")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%d", pending.count))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.1)))
                }
                .padding(.horizontal, 2)
                ForEach(pending) { todo in
                    eveningTodoCard(todo)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private var eveningEmptySection: some View {
        if reviewService.suggestions.isEmpty && todayPendingTodos.isEmpty {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    private var eveningHasContent: Bool {
        !reviewService.suggestions.isEmpty || !todayPendingTodos.isEmpty
    }

    private var eveningView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    eveningStatsRow
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                    eveningEmptySection
                    eveningEventsSection
                    eveningTodosSection
                }
                .padding(.bottom, 10)
            }

            Divider()

            HStack(spacing: 8) {
                if eveningHasContent {
                    // 전체 완료
                    Button { markAllDone() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.square.fill")
                                .font(.system(size: 10))
                            Text(String(localized: "review.done.all"))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.5), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 전체 내일로
                    Button { moveAllToTomorrow() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.to.line")
                                .font(.system(size: 10))
                            Text(String(localized: "review.move.all"))
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

                Button { generatePlan() } label: {
                    if isGenerating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text(String(localized: "review.generating.button"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.indigo))
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11))
                            Text(String(localized: "review.generate.tomorrow"))
                                .font(.system(size: 11, weight: .semibold))
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

    private func eveningTodoCard(_ todo: TodoItem) -> some View {
        let selectedStatus = cardStatuses["todo-\(todo.id)"]

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(selectedStatus == .done)
                Text(String(localized: "review.todo.label"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let status = selectedStatus {
                // 상태 선택 후 표시
                Image(systemName: status == .done ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(status == .done ? Color.green : Color.secondary)
                    .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 2) {
                    statusButton(sfSymbol: "checkmark.circle.fill", color: .green,
                                 help: String(localized: "review.help.done")) {
                        completeTodo(todo)
                    }
                    statusButton(sfSymbol: "xmark.circle.fill", color: .secondary,
                                 help: String(localized: "review.help.skip")) {
                        skipTodo(todo)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(
            selectedStatus == .done ? Color.green.opacity(0.06) : Color.platformControlBackground
        ))
        .animation(.easeInOut(duration: 0.2), value: selectedStatus != nil)
    }

    private func eveningCard(_ s: ReviewSuggestion, index: Int) -> some View {
        let cardKey = s.id.uuidString
        let selectedStatus = cardStatuses[cardKey]

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(selectedStatus == .done)
                if let start = s.proposedStart, let end = s.proposedEnd {
                    Text("\(formatTime(start)) – \(formatTime(end))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(s.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let status = selectedStatus {
                // 상태 선택 후 아이콘 표시 (0.5초 후 제거)
                Group {
                    switch status {
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                    case .moved:
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.orange)
                    default:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.secondary)
                    }
                }
                .font(.system(size: 22))
                .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 2) {
                    statusButton(sfSymbol: "checkmark.circle.fill", color: .green,
                                 help: String(localized: "review.help.done")) {
                        markCompletionWithFeedback(suggestion: s, at: index, status: .done)
                    }
                    statusButton(sfSymbol: "arrow.right.circle.fill", color: .orange,
                                 help: String(localized: "review.help.tomorrow")) {
                        markCompletionWithFeedback(suggestion: s, at: index, status: .moved)
                    }
                    statusButton(sfSymbol: "xmark.circle.fill", color: .secondary,
                                 help: String(localized: "review.help.skip")) {
                        markCompletionWithFeedback(suggestion: s, at: index, status: .skipped)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(
            selectedStatus == .done ? Color.green.opacity(0.06)
            : selectedStatus == .moved ? Color.orange.opacity(0.06)
            : Color.platformControlBackground
        ))
        .animation(.easeInOut(duration: 0.2), value: selectedStatus != nil)
    }

    private func statusButton(sfSymbol: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sfSymbol)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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

    private func markAllDone() {
        // 이벤트 전체 완료
        for i in (0..<reviewService.suggestions.count).reversed() {
            markCompletion(at: i, status: .done)
        }
        // 할 일 전체 완료
        for todo in todayPendingTodos {
            completeTodo(todo)
        }
    }

    private func completeTodo(_ todo: TodoItem) {
        withAnimation {
            cardStatuses["todo-\(todo.id)"] = .done
        }
        reviewedItems.append((
            title: todo.title,
            status: .done,
            start: Calendar.current.startOfDay(for: todo.date),
            end: Calendar.current.startOfDay(for: todo.date).addingTimeInterval(1800)
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation { _ = hiddenTodoIDs.insert(todo.id) }
        }
        // 실제 완료 처리
        if todo.source == .appleReminder, let identifier = todo.appleReminderIdentifier {
            viewModel.toggleAppleReminder(identifier: identifier)
        } else {
            viewModel.toggleTodo(id: todo.id)
        }
    }

    private func skipTodo(_ todo: TodoItem) {
        withAnimation {
            cardStatuses["todo-\(todo.id)"] = .skipped
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation { _ = hiddenTodoIDs.insert(todo.id) }
        }
    }

    private func markCompletionWithFeedback(suggestion s: ReviewSuggestion, at index: Int, status: CompletionStatus) {
        withAnimation {
            cardStatuses[s.id.uuidString] = status
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            markCompletion(at: index, status: status)
            cardStatuses.removeValue(forKey: s.id.uuidString)
        }
    }

    private func generatePlan() {
        isGenerating = true
        let remaining = reviewService.suggestions.map { s in
            (title: s.title,
             status: CompletionStatus.moved,
             start: s.proposedStart ?? Date(),
             end: s.proposedEnd ?? Date())
        }
        moveAllToTomorrow()
        let allReviewed = reviewedItems + remaining

        Task {
            let plan = await reviewService.generateAITomorrowPlan(reviewed: allReviewed)
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
