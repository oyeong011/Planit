import SwiftUI

// MARK: - Section drag-reorder support

/// 드래그로 순서를 바꿀 수 있는 섹션 ID
private enum ReviewSectionID: String, CaseIterable, Codable, Identifiable {
    case myHabits     = "my_habits"
    case longTermGoals = "long_term_goals"

    var id: String { rawValue }

    static let defaultOrder: [ReviewSectionID] = [
        .myHabits, .longTermGoals
    ]

    static func loadFromDefaults() -> [ReviewSectionID] {
        guard let data = UserDefaults.standard.data(forKey: "planit.review.sectionOrder"),
              let decoded = try? JSONDecoder().decode([ReviewSectionID].self, from: data) else {
            return defaultOrder
        }
        var normalized: [ReviewSectionID] = []
        var seen = Set<ReviewSectionID>()
        for sid in decoded where ReviewSectionID.allCases.contains(sid) && !seen.contains(sid) {
            normalized.append(sid)
            seen.insert(sid)
        }
        for sid in ReviewSectionID.allCases where !seen.contains(sid) {
            normalized.append(sid)
            seen.insert(sid)
        }
        return Set(normalized) == Set(ReviewSectionID.allCases) ? normalized : defaultOrder
    }
}

// 단일 sheet route — 목표·습관 시트를 하나의 enum으로 통합 (SwiftUI sheet 충돌 방지)
private enum ReviewSheetRoute: Identifiable {
    case addGoal
    case editGoal(ChatGoal)
    case addHabit
    case editHabit(Habit)

    var id: String {
        switch self {
        case .addGoal:           return "goal.add"
        case .editGoal(let g):   return "goal.\(g.id.uuidString)"
        case .addHabit:          return "habit.add"
        case .editHabit(let h):  return "habit.\(h.id.uuidString)"
        }
    }
}

struct ReviewView: View {
    @ObservedObject var reviewService: ReviewService
    @ObservedObject var goalService: GoalService
    @ObservedObject var goalMemoryService: GoalMemoryService
    @ObservedObject var habitService: HabitService
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject private var themeService = CalendarThemeService.shared
    let onCreateEvent: (String, Date, Date) -> Void
    let onDismiss: () -> Void
    /// "오늘 재계획" CTA — focusQuota 같은 경고 suggestion에서 채팅 탭으로 이동 후 재계획 트리거.
    /// MainView에서 leftPanelMode = .chat + 채팅의 runReplanDay() 호출로 연결.
    var onRequestReplanDay: (() -> Void)? = nil

    @State private var isGenerating = false
    @State private var showPlanResult = false
    @State private var aiPlan: ReviewAIPlan?
    // CRUD sheet — 목표·습관 모두 하나의 route로 관리 (SwiftUI sheet 충돌 방지)
    @State private var sheetRoute: ReviewSheetRoute? = nil
    // 목표 편집 임시값
    @State private var editTitle = ""
    @State private var editTargets = ""
    @State private var editTimeline: GoalTimeline = .thisYear
    @State private var hoveredGoalID: UUID? = nil
    @State private var tappedGoalID: UUID? = nil
    // 습관 편집 임시값
    @State private var editHabitName = ""
    @State private var editHabitEmoji = "⭐"
    @State private var editHabitColor = "blue"
    @State private var editHabitTarget = 5
    @State private var hoveredHabitID: UUID? = nil
    // 범위 습관(v0.4.9) — 기간이 있으면 매일 체크 진행률 게이지로 표시
    @State private var editHabitHasRange = false
    @State private var editHabitStart = Date()
    @State private var editHabitEnd = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()

    // MARK: - Drag-to-reorder state
    @State private var sectionOrder: [ReviewSectionID] = ReviewSectionID.loadFromDefaults()
    @State private var draggingID: ReviewSectionID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var pendingOrder: [ReviewSectionID] = ReviewSectionID.loadFromDefaults()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if showPlanResult, let plan = aiPlan {
                planResultView(plan)
            } else {
                unifiedReviewView
            }
        }
        .background(
            ZStack {
                Color.platformWindowBackground
                themeService.current.subtleBackgroundTint
            }
        )
        .animation(.easeInOut(duration: 0.28), value: themeService.current.id)
        // 단일 sheet — 목표·습관 시트 충돌 방지 (별도 subtree에 두지 않음)
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .addGoal:            goalEditSheet(editing: nil)
            case .editGoal(let g):    goalEditSheet(editing: g)
            case .addHabit:           habitEditSheet(editing: nil)
            case .editHabit(let h):   habitEditSheet(editing: h)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(themeService.current.gradient)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: headerIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(themeService.current.primary)
                Text(todayDateString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerIcon: String {
        if showPlanResult { return "calendar.badge.checkmark" }
        return reviewService.currentMode == .evening ? "moon.fill" : "sun.max.fill"
    }

    private var headerTitle: String {
        if showPlanResult { return String(localized: "review.plan.complete.title") }
        if reviewService.currentMode == .evening { return String(localized: "review.evening.title") }
        if reviewService.currentMode == .daily  { return String(localized: "review.daily.title") }
        return String(localized: "review.tab.title")
    }

    // MARK: - Morning View

    // MARK: - Unified Review View

    /// 섹션별 추정 높이 (드래그 임계값 계산용)
    private func estimatedHeight(for sid: ReviewSectionID) -> CGFloat {
        switch sid {
        case .myHabits:      return 70 + CGFloat(habitService.habits.count) * 66
        case .longTermGoals: return 80 + CGFloat(max(1, goalMemoryService.goals.count)) * 64
        }
    }

    /// 드래그 중 다른 섹션이 비켜야 할 Y 오프셋 계산
    private func displacement(for sid: ReviewSectionID) -> CGFloat {
        guard let dID = draggingID, dID != sid,
              let origIdx = sectionOrder.firstIndex(of: sid),
              let pendIdx = pendingOrder.firstIndex(of: sid),
              origIdx != pendIdx else { return 0 }
        let slotH = estimatedHeight(for: dID) + 10
        return CGFloat(pendIdx - origIdx) * slotH
    }

    /// 드래그 위치에 따른 예상 순서 계산
    private func computePendingOrder(dragging sid: ReviewSectionID, offset: CGFloat) -> [ReviewSectionID] {
        guard let fromIdx = sectionOrder.firstIndex(of: sid) else { return sectionOrder }
        let slotH = estimatedHeight(for: sid) + 10
        let steps = Int((offset / slotH).rounded())
        let toIdx = max(0, min(sectionOrder.count - 1, fromIdx + steps))
        guard toIdx != fromIdx else { return sectionOrder }
        var result = sectionOrder
        result.move(fromOffsets: IndexSet(integer: fromIdx),
                    toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        return result
    }

    private func saveSectionOrder() {
        if let data = try? JSONEncoder().encode(sectionOrder) {
            UserDefaults.standard.set(data, forKey: "planit.review.sectionOrder")
        }
    }

    @ViewBuilder
    private func sectionContent(for sid: ReviewSectionID) -> some View {
        switch sid {
        case .myHabits:
            myHabitsSection
        case .longTermGoals:
            longTermGoalsSection
        }
    }

    private func draggableCard(sid: ReviewSectionID) -> some View {
        let isDragging = draggingID == sid
        let yOffset: CGFloat = isDragging ? dragOffset : displacement(for: sid)

        return sectionContent(for: sid)
            .padding(.horizontal, 10)
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
                        let newPending = computePendingOrder(dragging: sid, offset: dragOffset)
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

    private var unifiedReviewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    // 드래그로 순서 조절 가능한 섹션들
                    ForEach(sectionOrder) { sid in
                        draggableCard(sid: sid)
                    }
                    .padding(.top, 10)

                    // 시간 의존 섹션 (드래그 불가, 항상 하단)
                    if reviewService.currentMode == .evening {
                        tomorrowPreviewSection
                            .padding(.horizontal, 10)
                    } else {
                        suggestionsSection
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.bottom, 10)
            }

            Divider()

            if reviewService.currentMode == .evening {
                Button { generatePlan() } label: {
                    HStack(spacing: 7) {
                        if isGenerating {
                            ProgressView().controlSize(.small).tint(.white)
                            Text(String(localized: "review.generating.button"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "wand.and.stars").font(.system(size: 13))
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
            } else if !reviewService.suggestions.isEmpty {
                HStack {
                    Button { acceptAllSuggestions() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.square").font(.system(size: 10))
                            Text(String(localized: "review.accept.all")).font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - My Habits Section (사용자 정의 습관 추적)

    private var myHabitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 섹션 헤더
            HStack {
                Label(String(localized: "habit.section.title"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeService.current.accent)
                Spacer()
                Button {
                    editHabitName = ""
                    editHabitEmoji = "⭐"
                    editHabitColor = "blue"
                    editHabitTarget = 5
                    sheetRoute = .addHabit
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if habitService.habits.isEmpty {
                // 빈 상태
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "habit.empty.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(habitService.habits) { habit in
                        habitCard(habit)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.platformControlBackground).overlay(RoundedRectangle(cornerRadius: 10).fill(themeService.current.cardTint)))
    }

    private func habitCard(_ habit: Habit) -> some View {
        let dots = habitService.completions(habit, days: 7)
        let streak = habitService.streak(for: habit)
        let weekCount = habitService.thisWeekCount(for: habit)
        let isDone = habitService.isCompletedToday(habit)
        let accent = habit.accentColor

        let isHovered = hoveredHabitID == habit.id

        return HStack(spacing: 10) {
            // 이모지 아이콘 — 원형 배경
            Text(habit.emoji)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Circle().fill(accent.opacity(0.13)))

            VStack(alignment: .leading, spacing: 5) {
                // 이름 + 이번 주 달성 수
                HStack(spacing: 4) {
                    Text(habit.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    // 호버 시 수정/삭제 버튼 표시
                    if isHovered {
                        HStack(spacing: 4) {
                            Button {
                                editHabitName = habit.name
                                editHabitEmoji = habit.emoji
                                editHabitColor = habit.colorName
                                editHabitTarget = habit.weeklyTarget
                                sheetRoute = .editHabit(habit)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.secondary.opacity(0.1)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                habitService.delete(habit)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red.opacity(0.7))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.red.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else {
                        Text("\(weekCount)/\(habit.weeklyTarget)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(weekCount >= habit.weeklyTarget ? accent : .secondary)
                            .animation(.easeInOut, value: weekCount)
                    }
                }

                // 7일 완료 점 + 스트릭
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            Circle()
                                .fill(dots[i] ? accent : Color.secondary.opacity(0.15))
                                .frame(width: 7, height: 7)
                        }
                    }
                    Spacer()
                    if streak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text(String(format: String(localized: "habit.streak.days"), streak))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // 오늘 완료 토글 버튼
            Button {
                habitService.toggleToday(habit)
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isDone ? accent : Color.secondary.opacity(0.35))
                    .animation(.spring(duration: 0.25), value: isDone)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.platformWindowBackground))
        .onHover { hoveredHabitID = $0 ? habit.id : nil }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button {
                editHabitName = habit.name
                editHabitEmoji = habit.emoji
                editHabitColor = habit.colorName
                editHabitTarget = habit.weeklyTarget
                sheetRoute = .editHabit(habit)
            } label: {
                Label(String(localized: "habit.edit"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                habitService.delete(habit)
            } label: {
                Label(String(localized: "habit.delete"), systemImage: "trash")
            }
        }
    }

    private func habitEditSheet(editing habit: Habit?) -> some View {
        let isEditing = habit != nil
        let accent = Color(hue: editHabitColor == "blue" ? 0.58 : editHabitColor == "green" ? 0.38 :
                           editHabitColor == "orange" ? 0.08 : editHabitColor == "purple" ? 0.72 :
                           editHabitColor == "red" ? 0.00 : 0.50,
                           saturation: 0.65, brightness: 0.82)

        return VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text(editHabitEmoji)
                        .font(.system(size: 22))
                }
                Text(isEditing ? String(localized: "habit.edit") : String(localized: "habit.add.title"))
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            VStack(spacing: 14) {
                // 이름 필드
                VStack(alignment: .leading, spacing: 5) {
                    Label(String(localized: "habit.field.name"), systemImage: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    TextField(String(localized: "habit.field.name.placeholder"), text: $editHabitName)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(!editHabitName.isEmpty ? accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                )
                        )
                        .textFieldStyle(.plain)
                }

                // 이모지 선택 (프리셋)
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "habit.field.emoji"), systemImage: "face.smiling")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    let emojis = ["🏋️","🌅","📚","🧘","💧","📖","😴","🥗","🏃","✍️","🎯","🎵","🖊️","🌿","☀️","🧹"]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                        ForEach(emojis, id: \.self) { e in
                            Button { editHabitEmoji = e } label: {
                                Text(e)
                                    .font(.system(size: 16))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(editHabitEmoji == e ? accent.opacity(0.2) : Color.secondary.opacity(0.07))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(editHabitEmoji == e ? accent : Color.clear, lineWidth: 1.5)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 색상 선택
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "habit.field.color"), systemImage: "paintpalette")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(["blue","green","orange","purple","red","teal"], id: \.self) { c in
                            let col = Habit(name:"", emoji:"", colorName:c, weeklyTarget:1).accentColor
                            Button { editHabitColor = c } label: {
                                Circle()
                                    .fill(col)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().strokeBorder(.white, lineWidth: editHabitColor == c ? 2 : 0)
                                    )
                                    .overlay(
                                        Circle().strokeBorder(col.opacity(0.5), lineWidth: editHabitColor == c ? 2.5 : 0)
                                            .scaleEffect(1.25)
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.spring(duration: 0.2), value: editHabitColor)
                        }
                    }
                }

                // 주간 목표 횟수
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "habit.field.weekly"), systemImage: "calendar.badge.checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { n in
                            Button { editHabitTarget = n } label: {
                                Text("\(n)")
                                    .font(.system(size: 12, weight: editHabitTarget == n ? .bold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(editHabitTarget == n ? .white : .secondary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(editHabitTarget == n ? accent : Color.secondary.opacity(0.07))
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.spring(duration: 0.15), value: editHabitTarget)
                        }
                    }
                }

                // 기간 (v0.4.9): 시작·종료 날짜 지정 시 달력에 게이지 바로 표시
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $editHabitHasRange.animation(.easeInOut(duration: 0.15))) {
                        Label(String(localized: "habit.field.range.toggle"),
                              systemImage: "calendar.badge.clock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    if editHabitHasRange {
                        HStack(spacing: 8) {
                            DatePicker(String(localized: "habit.field.range.start"),
                                       selection: $editHabitStart, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .font(.system(size: 11))
                            Text("→").foregroundStyle(.secondary).font(.system(size: 11))
                            DatePicker(String(localized: "habit.field.range.end"),
                                       selection: $editHabitEnd, in: editHabitStart...,
                                       displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .font(.system(size: 11))
                        }
                        Text(rangeSummary(start: editHabitStart, end: editHabitEnd))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 10) {
                Button { sheetRoute = nil } label: {
                    Text(String(localized: "goal.cancel"))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    let fmt = HabitService.dayKeyFormatter
                    let sKey: String? = editHabitHasRange ? fmt.string(from: editHabitStart) : nil
                    let eKey: String? = editHabitHasRange ? fmt.string(from: editHabitEnd) : nil
                    if var h = habit {
                        h.name = editHabitName; h.emoji = editHabitEmoji
                        h.colorName = editHabitColor; h.weeklyTarget = editHabitTarget
                        h.startDateKey = sKey
                        h.endDateKey = eKey
                        habitService.update(h)
                    } else {
                        habitService.add(name: editHabitName, emoji: editHabitEmoji,
                                         colorName: editHabitColor, weeklyTarget: editHabitTarget,
                                         startDate: editHabitHasRange ? editHabitStart : nil,
                                         endDate: editHabitHasRange ? editHabitEnd : nil)
                    }
                    sheetRoute = nil
                } label: {
                    Text(String(localized: "goal.save"))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(editHabitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? Color.secondary.opacity(0.15) : accent)
                        )
                        .foregroundStyle(editHabitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? Color.secondary : .white)
                }
                .buttonStyle(.plain)
                .disabled(editHabitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 320)
        .background(Color.platformWindowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            if let h = habit {
                editHabitName = h.name; editHabitEmoji = h.emoji
                editHabitColor = h.colorName; editHabitTarget = h.weeklyTarget
                editHabitHasRange = h.isRanged
                let fmt = HabitService.dayKeyFormatter
                if let s = h.startDateKey.flatMap(fmt.date(from:)) { editHabitStart = s }
                if let e = h.endDateKey.flatMap(fmt.date(from:)) { editHabitEnd = e }
            } else {
                editHabitHasRange = false
                editHabitStart = Date()
                editHabitEnd = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
            }
        }
        // start를 end 뒤로 옮기면 end를 start로 클램프 (DatePicker 범위 밖 stale 상태 방지)
        .onChange(of: editHabitStart) { _, newStart in
            if editHabitEnd < newStart { editHabitEnd = newStart }
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
                    .foregroundStyle(themeService.current.accent)
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
                        // 생성 가능한 제안(proposed* 있음)만 "추가" 버튼 표시.
                        // 경고성 suggestion(focusQuota 등 proposed가 nil)은 "확인"만.
                        let isActionable = s.proposedStart != nil
                            && s.proposedEnd != nil
                            && s.proposedTitle != nil

                        if isActionable {
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
                        } else {
                            // 경고형 suggestion (예: focusQuota) — 재계획 CTA 제공
                            HStack(spacing: 6) {
                                if s.type == .focusQuota, let replan = onRequestReplanDay {
                                    Button {
                                        replan()
                                        declineSuggestion(at: index)
                                    } label: {
                                        Text(String(localized: "review.focusQuota.replan"))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 3)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(colorFor(s.type)))
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button { declineSuggestion(at: index) } label: {
                                    Text(s.type == .focusQuota && onRequestReplanDay != nil
                                         ? String(localized: "review.focusQuota.ignore")
                                         : String(localized: "common.confirm", defaultValue: "확인"))
                                        .font(.system(size: 10, weight: s.type == .focusQuota ? .regular : .semibold))
                                        .foregroundStyle(s.type == .focusQuota && onRequestReplanDay != nil ? Color.secondary : Color.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(
                                            s.type == .focusQuota && onRequestReplanDay != nil
                                                ? Color.clear
                                                : colorFor(s.type)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(
                                                    s.type == .focusQuota && onRequestReplanDay != nil
                                                        ? Color.secondary.opacity(0.3)
                                                        : Color.clear,
                                                    lineWidth: 1
                                                )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
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

    // 오늘 날짜를 UI 상태(currentMonth/selectedDate)와 무관하게 실제 현재 시각으로 고정.
    // itemsForDate가 DailyDetailView(오른쪽 패널)와 동일한 소스라 숫자 불일치/중복 이슈를
    // 원천적으로 제거한다 (todosForDate는 source 필터가 없어 Apple mirror가 2중 카운트됐음).
    private var todayItems: [CalendarViewModel.DayItem] {
        // all-day 이벤트도 포함 — DailyDetailView와 동일 기준
        viewModel.itemsForDate(Calendar.current.startOfDay(for: Date()))
    }

    private var todayEvents: [CalendarEvent] {
        todayItems.compactMap { if case .event(let e) = $0 { return e } else { return nil } }
    }

    private var todayTodos: [TodoItem] {
        todayItems.compactMap { if case .todo(let t) = $0 { return t } else { return nil } }
    }

    /// 편집 시트에 보여줄 "N일간 · Apr 6 - Apr 12" 스타일 요약.
    /// start > end 인 stale 입력도 방어적으로 swap 후 계산.
    private func rangeSummary(start: Date, end: Date) -> String {
        let cal = Calendar.current
        let s = cal.startOfDay(for: min(start, end))
        let e = cal.startOfDay(for: max(start, end))
        let days = (cal.dateComponents([.day], from: s, to: e).day ?? 0) + 1
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        let daysLabel: String
        if days == 1 {
            daysLabel = String(localized: "habit.field.range.days.one")
        } else {
            daysLabel = String.localizedStringWithFormat(
                String(localized: "habit.field.range.days"), days)
        }
        return "\(daysLabel) · \(fmt.string(from: s)) - \(fmt.string(from: e))"
    }

    // MARK: - Tomorrow Preview Section (저녁 전용)

    private var tomorrowEvents: [CalendarEvent] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return viewModel.eventsForDate(Calendar.current.startOfDay(for: tomorrow))
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    @ViewBuilder
    private var tomorrowPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tomorrowDateString, systemImage: "calendar.badge.plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            if tomorrowEvents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.indigo)
                    Text(String(localized: "review.tomorrow.empty"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(tomorrowEvents.prefix(4))) { event in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(event.color)
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text("\(formatTime(event.startDate)) – \(formatTime(event.endDate))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.platformWindowBackground))
                    }
                    if tomorrowEvents.count > 4 {
                        Text(String(format: String(localized: "review.tomorrow.more"), tomorrowEvents.count - 4))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.06)))
    }

    // MARK: - Long-Term Goals Section

    private var longTermGoalsSection: some View {
        let events = viewModel.calendarEvents.map {
            (id: $0.id, title: $0.title, startDate: $0.startDate)
        }
        let todos = viewModel.todos.map {
            (id: $0.id.uuidString, title: $0.title, date: $0.date, isCompleted: $0.isCompleted)
        }
        let completedIDs = viewModel.completedEventIDs

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(String(localized: "goal.section.title"), systemImage: "flag.checkered")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeService.current.accent)
                Spacer()
                Button {
                    editTitle = ""; editTargets = ""; editTimeline = .thisYear
                    sheetRoute = .addGoal
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                ForEach(goalMemoryService.goals) { goal in
                    goalCard(goal, events: events, completedIDs: completedIDs)
                }
                // 목표 없을 때 — 예시 제시 + 직접 추가 버튼
                if goalMemoryService.goals.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "flag.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text(String(localized: "goal.empty.hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        VStack(spacing: 4) {
                            Text(String(localized: "review.goal.empty.example"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            ForEach(["\"정보처리기사 취득하기\"", "\"올해 10kg 감량\"", "\"3개월 안에 토익 900점\""], id: \.self) { ex in
                                Text(ex)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            editTitle = ""; editTargets = ""; editTimeline = .thisYear
                            sheetRoute = .addGoal
                        } label: {
                            Label(String(localized: "review.goal.empty.add"), systemImage: "plus.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.platformControlBackground).overlay(RoundedRectangle(cornerRadius: 10).fill(themeService.current.cardTint)))
        .task(id: refreshMatchKey(events: events, todos: todos)) {
            await goalMemoryService.refreshMatches(events: events, todos: todos)
        }
    }

    /// goals/events/todos 중 하나라도 바뀌면 분류 재실행 (task의 id 값).
    /// **순서 무관** — Set으로 정렬된 ID만 비교해 정렬만 바뀌는 경우
    /// classify(Claude CLI) 재실행을 피한다 (CPU 과부하 원인이었음).
    private func refreshMatchKey(
        events: [(id: String, title: String, startDate: Date)],
        todos: [(id: String, title: String, date: Date, isCompleted: Bool)]
    ) -> String {
        let goalPart = goalMemoryService.goals.map(\.id.uuidString).sorted().joined(separator: ",")
        let eventIDs = events.map(\.id).sorted().joined(separator: ",")
        // 완료 상태 변화만 재분류 유발. 단순 순서/제목 변경은 무시.
        let todoIDs = todos.filter { !$0.isCompleted }.map(\.id).sorted().joined(separator: ",")
        return "\(goalPart)|\(eventIDs)|\(todoIDs)"
    }

    private func goalEditSheet(editing goal: ChatGoal?) -> some View {
        let isEditing = goal != nil
        let accent = isEditing ? goalAccentColor(for: editTimeline) : Color.indigo

        return VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent)
                }
                Text(isEditing ? String(localized: "goal.edit.title") : String(localized: "goal.add.title"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // 폼 영역
            VStack(spacing: 14) {
                // 목표 이름 필드
                VStack(alignment: .leading, spacing: 5) {
                    Label(String(localized: "goal.field.name"), systemImage: "flag.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    TextField(String(localized: "goal.field.name.placeholder"), text: $editTitle)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(!editTitle.isEmpty ? accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                )
                        )
                        .textFieldStyle(.plain)
                }

                // 타깃 필드
                VStack(alignment: .leading, spacing: 5) {
                    Label(String(localized: "goal.field.targets"), systemImage: "building.2")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "goal.field.targets.placeholder"), text: $editTargets)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.07))
                        )
                        .textFieldStyle(.plain)
                    Text(String(localized: "review.goal.multi.hint"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                // 기간 선택
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "goal.field.timeline"), systemImage: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(GoalTimeline.allCases, id: \.self) { t in
                            let isSelected = editTimeline == t
                            Button {
                                withAnimation(.spring(duration: 0.2)) { editTimeline = t }
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: t.icon)
                                        .font(.system(size: 12))
                                    Text(t.label)
                                        .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? goalAccentColor(for: t) : Color.secondary.opacity(0.07))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Divider()

            // 액션 버튼
            HStack(spacing: 10) {
                Button {
                    sheetRoute = nil
                } label: {
                    Text(String(localized: "goal.cancel"))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    // 입력값 정규화: 제목 최대 100자, 세부목표 최대 20개
                    let cleanTitle = String(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
                    let targets = editTargets.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .prefix(20)
                        .map { String($0.prefix(80)) }  // 세부목표 항목도 최대 80자
                    guard !cleanTitle.isEmpty else { return }
                    if var g = goal {
                        g.title = cleanTitle; g.targets = targets; g.timeline = editTimeline
                        goalMemoryService.update(g)
                    } else {
                        goalMemoryService.add(title: cleanTitle, targets: targets, timeline: editTimeline)
                    }
                    sheetRoute = nil
                } label: {
                    Text(String(localized: "goal.save"))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? Color.secondary.opacity(0.15) : accent)
                        )
                        .foregroundStyle(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : .white)
                }
                .buttonStyle(.plain)
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 320)
        .background(Color.platformWindowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            if let g = goal {
                editTitle = g.title
                editTargets = g.targets.joined(separator: ", ")
                editTimeline = g.timeline
            }
        }
    }

    private func goalCard(
        _ goal: ChatGoal,
        events: [(id: String, title: String, startDate: Date)],
        completedIDs: Set<String>
    ) -> some View {
        let rate = goalMemoryService.progressRate(for: goal, events: events, completedIDs: completedIDs)
        let trend = goalMemoryService.trend(for: goal)
        let barColor = progressColor(for: rate)
        let matches = goalMemoryService.monthlyMatches[goal.id] ?? []
        let hasActivity = !matches.isEmpty || goal.weeklyActivity.reduce(0, +) > 0
        let accentColor = goalAccentColor(for: goal.timeline)
        let isHovered = hoveredGoalID == goal.id
        let isTapped = tappedGoalID == goal.id

        return VStack(alignment: .leading, spacing: 0) {
            // 탭시 인라인 액션 패널
            if isTapped {
                HStack(spacing: 0) {
                    Button {
                        editTitle = goal.title
                        editTargets = goal.targets.joined(separator: ", ")
                        editTimeline = goal.timeline
                        tappedGoalID = nil
                        sheetRoute = .editGoal(goal)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text(String(localized: "goal.edit.title"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accentColor)
                    }
                    .buttonStyle(.plain)

                    Divider().frame(width: 1).background(Color.white.opacity(0.3))

                    Button {
                        tappedGoalID = nil
                        goalMemoryService.delete(goal)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text(String(localized: "goal.delete"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 메인 카드
            HStack(spacing: 10) {
                // 왼쪽 액센트 바
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 6) {
                    // 헤더: 타이틀 + 트렌드 + 호버 액션 버튼
                    HStack(spacing: 5) {
                        Text(goal.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if hasActivity && !isHovered {
                            Image(systemName: trend.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(trend.color)
                        }
                        if isHovered {
                            HStack(spacing: 4) {
                                Button {
                                    editTitle = goal.title
                                    editTargets = goal.targets.joined(separator: ", ")
                                    editTimeline = goal.timeline
                                    sheetRoute = .editGoal(goal)
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(accentColor)
                                        .padding(5)
                                        .background(Circle().fill(accentColor.opacity(0.15)))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    goalMemoryService.delete(goal)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.red)
                                        .padding(5)
                                        .background(Circle().fill(Color.red.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                            }
                            .transition(.opacity)
                        }
                        // 타임라인 뱃지
                        Text(goal.timeline.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(accentColor))
                    }

                    // 타깃 태그
                    if !goal.targets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(goal.targets.prefix(5), id: \.self) { target in
                                    Text(target)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(accentColor)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Capsule().fill(accentColor.opacity(0.13)))
                                }
                            }
                        }
                    }

                    // 주별 스파크라인 + 진행 바
                    HStack(spacing: 8) {
                        // 미니 스파크라인 (4주)
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(0..<4, id: \.self) { i in
                                let maxVal = max(goal.weeklyActivity.max() ?? 1, 1)
                                let h = max(CGFloat(goal.weeklyActivity[i]) / CGFloat(maxVal) * 14, goal.weeklyActivity[i] > 0 ? 3 : 2)
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(i == 3 ? accentColor : accentColor.opacity(0.35))
                                    .frame(width: 4, height: h)
                            }
                        }
                        .frame(height: 14)

                        if hasActivity {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .frame(width: max(geo.size.width * CGFloat(rate), rate > 0 ? 4 : 0))
                                        .animation(.spring(duration: 0.5), value: rate)
                                }
                            }
                            .frame(height: 5)
                            Text("\(Int(rate * 100))%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(barColor)
                                .frame(width: 28, alignment: .trailing)
                        } else {
                            Text(String(localized: "goal.no.activity"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 매칭된 활동 리스트 (최대 3개, 더 있으면 "+N")
                    if !matches.isEmpty {
                        matchedActivitiesRow(matches: matches, events: events, todos: viewModel.todos, accent: accentColor)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.platformWindowBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isHovered ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.06 : 0.02), radius: isHovered ? 4 : 1, y: isHovered ? 2 : 1)
            .onHover { hoveredGoalID = $0 ? goal.id : nil }
            .onTapGesture {
                withAnimation(.spring(duration: 0.2)) {
                    tappedGoalID = tappedGoalID == goal.id ? nil : goal.id
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .contextMenu {
            Button {
                editTitle = goal.title
                editTargets = goal.targets.joined(separator: ", ")
                editTimeline = goal.timeline
                sheetRoute = .editGoal(goal)
            } label: {
                Label(String(localized: "goal.edit.title"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                goalMemoryService.delete(goal)
            } label: {
                Label(String(localized: "goal.delete"), systemImage: "trash")
            }
        }
    }

    /// 목표 카드 하단에 매칭된 활동 3개까지 pill로 표시.
    /// 🤖 뱃지는 AI가 분류한 활동(키워드 매칭이 아닌 경우)에 붙는다.
    @ViewBuilder
    private func matchedActivitiesRow(
        matches: [GoalActivityClassifier.Match],
        events: [(id: String, title: String, startDate: Date)],
        todos: [TodoItem],
        accent: Color
    ) -> some View {
        let titleByID: [String: (title: String, isAI: Bool)] = {
            var map: [String: (title: String, isAI: Bool)] = [:]
            for m in matches {
                let isAI = m.source == .ai
                if let ev = events.first(where: { $0.id == m.activityID }) {
                    map[m.activityID] = (ev.title, isAI)
                } else if let todo = todos.first(where: { $0.id.uuidString == m.activityID }) {
                    map[m.activityID] = (todo.title, isAI)
                }
            }
            return map
        }()

        let visible = matches.prefix(3).compactMap { titleByID[$0.activityID] }
        let hidden = max(matches.count - visible.count, 0)

        HStack(spacing: 4) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    if item.isAI {
                        Text("🤖").font(.system(size: 9))
                    }
                    Text(item.title)
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(accent.opacity(0.12)))
                .foregroundStyle(accent.opacity(0.9))
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func goalAccentColor(for timeline: GoalTimeline) -> Color {
        switch timeline {
        case .thisMonth:   return Color(hue: 0.58, saturation: 0.7, brightness: 0.85)   // 파랑
        case .thisQuarter: return Color(hue: 0.28, saturation: 0.7, brightness: 0.75)   // 초록
        case .thisYear:    return Color(hue: 0.72, saturation: 0.6, brightness: 0.80)   // 보라
        case .longTerm:    return Color(hue: 0.08, saturation: 0.75, brightness: 0.90)  // 주황
        }
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

    // MARK: - Formatting Helpers

    // DateFormatter 캐싱 — 뷰 수명 동안 재사용 (매 호출 생성 방지)
    private let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current; return f
    }()

    private var todayDateString: String { mediumDateFormatter.string(from: Date()) }

    private var tomorrowDateString: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return mediumDateFormatter.string(from: tomorrow)
    }

    private func formatTime(_ date: Date) -> String { timeFormatter.string(from: date) }

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
