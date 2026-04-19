import SwiftUI

// MARK: - SuggestionPreviewSheet
// PlanningOrchestrator의 결과를 사용자가 검토 후 선택 적용하는 모달.
// Hermes 철학: AI 제안은 항상 dry-run. 사용자 승인 후에만 실제 캘린더 반영.

struct SuggestionPreviewSheet: View {
    let suggestion: PlanningSuggestion
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject var hermesMemoryService: HermesMemoryService
    var onDismiss: () -> Void

    @State private var acceptedIDs: Set<UUID>
    @State private var isApplying: Bool = false
    @State private var appliedCount: Int = 0

    init(suggestion: PlanningSuggestion, viewModel: CalendarViewModel,
         hermesMemoryService: HermesMemoryService, onDismiss: @escaping () -> Void) {
        self.suggestion = suggestion
        self.viewModel = viewModel
        self.hermesMemoryService = hermesMemoryService
        self.onDismiss = onDismiss
        // 기본값: 모든 액션 선택
        self._acceptedIDs = State(initialValue: Set(suggestion.actions.map { $0.id }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            if suggestion.actions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(suggestion.actions) { action in
                            actionCard(action)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            if !suggestion.warnings.isEmpty {
                warningsSection
            }
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    // MARK: - Components

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text(suggestion.intent.displayName)
                    .font(.system(size: 16, weight: .bold))
            }
            if !suggestion.summary.isEmpty {
                Text(verbatim: suggestion.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
            if !suggestion.rationale.isEmpty {
                Text(verbatim: suggestion.rationale)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("제안할 변경사항이 없습니다.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionCard(_ action: SuggestedAction) -> some View {
        let isSelected = acceptedIDs.contains(action.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggle(action.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .purple : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(isApplying)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: action.kind.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                    Text(action.kind.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.purple)
                }
                Text(verbatim: action.title)
                    .font(.system(size: 13, weight: .semibold))
                if let s = action.startDate, let e = action.endDate {
                    Text(formatTimeRange(start: s, end: e))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !action.reason.isEmpty {
                    Text(verbatim: action.reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.purple.opacity(0.06) : Color.gray.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.purple.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(suggestion.warnings.prefix(3), id: \.self) { w in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 9))
                    Text(verbatim: w)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(acceptedIDs.count) / \(suggestion.actions.count) 선택")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("취소", action: dismiss)
                .buttonStyle(.bordered)
                .disabled(isApplying)
            Button {
                Task { await applySelected() }
            } label: {
                if isApplying {
                    ProgressView().controlSize(.small)
                } else {
                    Text("선택한 제안 적용")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(isApplying || acceptedIDs.isEmpty)
        }
    }

    // MARK: - Logic

    private func toggle(_ id: UUID) {
        if acceptedIDs.contains(id) {
            acceptedIDs.remove(id)
        } else {
            acceptedIDs.insert(id)
        }
    }

    private func applySelected() async {
        isApplying = true
        var applied = 0

        for action in suggestion.actions where acceptedIDs.contains(action.id) {
            guard revalidate(action) else { continue }
            apply(action)
            applied += 1
            // 순차 적용 — race 방지
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        appliedCount = applied
        recordDecision(applied: applied, total: acceptedIDs.count)
        isApplying = false
        dismiss()
    }

    /// apply 직전 재검증 — context에 해당 target이 여전히 존재하는지 확인.
    private func revalidate(_ action: SuggestedAction) -> Bool {
        switch action.kind {
        case .create, .createTodo:
            return action.startDate != nil
        case .move, .delete:
            guard let eid = action.eventID else { return false }
            return viewModel.calendarEvents.contains(where: { $0.id == eid })
        case .moveTodo, .updateTodo:
            guard let tid = action.todoID else { return false }
            return viewModel.todos.contains(where: { $0.id == tid })
        }
    }

    private func apply(_ action: SuggestedAction) {
        switch action.kind {
        case .create:
            guard let s = action.startDate, let e = action.endDate else { return }
            viewModel.addEventToGoogleCalendar(title: action.title, startDate: s, endDate: e, isAllDay: false)
        case .move:
            guard let eid = action.eventID, let s = action.startDate else { return }
            viewModel.moveCalendarEvent(id: eid, toStartDate: s)
        case .delete:
            guard let eid = action.eventID,
                  let ev = viewModel.calendarEvents.first(where: { $0.id == eid }) else { return }
            if ev.source == .google {
                viewModel.deleteGoogleEvent(eventID: eid, calendarID: ev.calendarID)
            } else {
                _ = viewModel.deleteCalendarEvent(eventID: eid, calendarID: ev.calendarID)
            }
        case .createTodo:
            viewModel.addTodo(title: action.title, date: action.startDate)
        case .moveTodo:
            guard let tid = action.todoID, let s = action.startDate else { return }
            viewModel.moveTodo(id: tid, toDate: s)
        case .updateTodo:
            // categoryID 정보 없음 — 기존 category 유지. title만 변경.
            guard let tid = action.todoID,
                  let existing = viewModel.todos.first(where: { $0.id == tid }) else { return }
            viewModel.updateTodo(id: tid, title: action.title, categoryID: existing.categoryID, date: existing.date)
        }
    }

    private func recordDecision(applied: Int, total: Int) {
        let outcome: PlanningDecision.DecisionOutcome
        switch (applied, total) {
        case (0, _):                  outcome = .rejected
        case let (a, t) where a == t: outcome = .accepted
        default:                      outcome = .partial
        }
        hermesMemoryService.recordDecision(PlanningDecision(
            intent: suggestion.intent.rawValue,
            summary: suggestion.summary,
            outcome: outcome,
            learnedFacts: []  // 보수적 기준 — 단일 수락으로는 fact 생성 안 함
        ))
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        let ef = DateFormatter()
        ef.dateFormat = "HH:mm"
        return "\(f.string(from: start)) ~ \(ef.string(from: end))"
    }

    private func dismiss() {
        onDismiss()
    }
}
