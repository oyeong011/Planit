import SwiftUI

struct ReviewView: View {
    @ObservedObject var reviewService: ReviewService
    @ObservedObject var goalService: GoalService
    let onCreateEvent: (String, Date, Date) -> Void
    let onDismiss: () -> Void
    @State private var isFinalizingEvening = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()

            if reviewService.suggestions.isEmpty {
                emptyState
            } else {
                suggestionList
            }

            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: reviewService.currentMode == .morning ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 14))
                .foregroundStyle(reviewService.currentMode == .morning ? .orange : .indigo)
            Text(reviewService.currentMode == .morning ? "아침 브리핑" : "저녁 리뷰")
                .font(.system(size: 14, weight: .bold))

            if !reviewService.suggestions.isEmpty {
                Text("· \(reviewService.suggestions.count) 제안")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("좋아요!")
                .font(.system(size: 13, weight: .semibold))
            Text("오늘은 그대로 진행하면 됩니다")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Suggestion List

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Weekly progress bar (morning only)
                if reviewService.currentMode == .morning {
                    weeklyProgressCard
                }

                ForEach(Array(reviewService.suggestions.enumerated()), id: \.element.id) { idx, suggestion in
                    if reviewService.currentMode == .evening {
                        eveningCard(suggestion, index: idx)
                    } else {
                        morningCard(suggestion, index: idx)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Morning Card

    private func morningCard(_ suggestion: ReviewSuggestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Type badge
            HStack(spacing: 4) {
                Image(systemName: iconFor(suggestion.type))
                    .font(.system(size: 9))
                Text(labelFor(suggestion.type))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(colorFor(suggestion.type))

            // Title
            Text(suggestion.title)
                .font(.system(size: 12, weight: .semibold))

            // Description
            Text(suggestion.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Action buttons (only for pending suggestions, not auto-created)
            if suggestion.status != .accepted {
                HStack(spacing: 6) {
                    Button {
                        acceptSuggestion(at: index)
                    } label: {
                        Text("확인")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.purple))
                    }
                    .buttonStyle(.plain)

                    Button {
                        declineSuggestion(at: index)
                    } label: {
                        Text("건너뛰기")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
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

            // Completion buttons
            HStack(spacing: 4) {
                Button {
                    markCompletion(at: index, status: .done)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("완료")

                Button {
                    markCompletion(at: index, status: .moved)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("내일로")

                Button {
                    markCompletion(at: index, status: .skipped)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("건너뛰기")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Weekly Progress

    private var weeklyProgressCard: some View {
        let rate = goalService.weeklyCompletionRate()
        let percent = Int(rate * 100)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("이번주 완수율")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(rate >= 0.7 ? .green : rate >= 0.4 ? .orange : .red)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rate >= 0.7 ? Color.green : rate >= 0.4 ? Color.orange : Color.red)
                        .frame(width: geo.size.width * CGFloat(rate))
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Tomorrow Plan Summary

    private var tomorrowPlanSummary: some View {
        Group {
            if let result = reviewService.tomorrowPlanResult,
               !result.created.isEmpty || !result.suggested.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                        Text("내일 계획")
                            .font(.system(size: 11, weight: .bold))
                    }

                    if !result.created.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text("\(result.created.count)개 자동 생성됨")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !result.suggested.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text("\(result.suggested.count)개 제안 (아침 브리핑에서 확인)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("\(result.totalMinutesPlanned)/\(result.capacityMinutes)분 배치")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.06)))
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            tomorrowPlanSummary
                .padding(.bottom, 6)

            Divider()

            HStack {
                if reviewService.currentMode == .evening {
                    Button {
                        moveAllToTomorrow()
                    } label: {
                        Text("미완료 모두 내일로")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if reviewService.currentMode == .evening {
                    Button {
                        isFinalizingEvening = true
                        Task {
                            await reviewService.finalizeEveningAndPlan()
                            isFinalizingEvening = false
                            // Don't dismiss yet — show plan summary, user taps again to close
                        }
                    } label: {
                        if isFinalizingEvening {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("내일 계획 생성 중...")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.purple)
                            }
                        } else if reviewService.tomorrowPlanResult != nil {
                            Text("닫기")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.purple)
                        } else {
                            Text("완료")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.purple)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFinalizingEvening)
                } else {
                    Button {
                        onDismiss()
                    } label: {
                        Text("채팅으로")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

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
        goalService.markCompletion(eventId: s.proposedTitle ?? s.title,
                                    goalId: s.goalId, status: status,
                                    plannedMinutes: max(minutes, 30))
        reviewService.suggestions.remove(at: index)
    }

    private func moveAllToTomorrow() {
        for i in (0..<reviewService.suggestions.count).reversed() {
            markCompletion(at: i, status: .moved)
        }
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
