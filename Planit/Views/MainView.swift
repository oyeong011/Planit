import SwiftUI
import UserNotifications

struct MainView: View {
    @StateObject private var authManager = GoogleAuthManager()
    @State private var newTodoTitle: String = ""
    @AppStorage("planit.skipGoogleAuth") private var skipGoogleAuth = false

    private var shouldShowLogin: Bool {
        !authManager.isAuthenticated && !skipGoogleAuth
    }

    var body: some View {
        if shouldShowLogin {
            LoginView(authManager: authManager)
        } else {
            MainCalendarView(authManager: authManager, newTodoTitle: $newTodoTitle)
        }
    }
}

// MARK: - Left Panel Mode

enum LeftPanelMode: String {
    case chat
    case review
    case onboarding
}

struct MainCalendarView: View {
    @ObservedObject var authManager: GoogleAuthManager
    @Binding var newTodoTitle: String
    @StateObject private var viewModel: CalendarViewModel
    @StateObject private var aiService: AIService
    @StateObject private var goalService: GoalService
    @StateObject private var reviewService: ReviewService
    @StateObject private var notificationService = NotificationService()
    @StateObject private var userContextService = UserContextService()
    @StateObject private var goalMemoryService = GoalMemoryService()
    @StateObject private var habitService = HabitService()
    @StateObject private var hermesMemoryService = HermesMemoryService()
    @StateObject private var updater = UpdaterService.shared
    @ObservedObject private var themeService = CalendarThemeService.shared
    @State private var showLeftPanel: Bool = true
    @State private var leftPanelMode: LeftPanelMode = .chat
    @State private var showSettings: Bool = false
    @State private var updateBannerDismissedFor: String?
    /// updater.checkForUpdatesInBackground()를 세션당 1회로 제한.
    /// 팝오버를 자주 여닫을 때 Sparkle 체크가 반복 호출되는 부하 방지.
    @State private var didTriggerUpdateCheckThisSession = false
    /// User context 분석 debounce — 이벤트 배열이 빠르게 바뀔 때 Claude CLI 폭주 방지
    @State private var contextRefreshTask: Task<Void, Never>?
    /// Hermes → CloudKit 단방향 업로드 sync. planit.hermesCloudKitSyncEnabled 플래그가 켜지면 자동 시작.
    @State private var hermesSync: HermesMemorySync?

    init(authManager: GoogleAuthManager, newTodoTitle: Binding<String>) {
        self.authManager = authManager
        self._newTodoTitle = newTodoTitle
        let vm = CalendarViewModel(authManager: authManager)
        self._viewModel = StateObject(wrappedValue: vm)
        let ai = AIService(authManager: authManager, calendarService: vm.googleService)
        self._aiService = StateObject(wrappedValue: ai)
        let gs = GoalService()
        vm.goalService = gs
        self._goalService = StateObject(wrappedValue: gs)
        self._reviewService = StateObject(wrappedValue: ReviewService(
            goalService: gs,
            calendarService: vm.googleService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = viewModel.lastCRUDError {
                CRUDErrorInlineNotice(notice: notice) {
                    viewModel.dismissLastCRUDError()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            HStack(spacing: 0) {
                if showLeftPanel {
                    leftPanel
                        .frame(width: 280)
                    Divider()
                }

                CalendarGridView(viewModel: viewModel, showChat: $showLeftPanel)
                    .frame(maxWidth: .infinity)

                Divider()

                DailyDetailView(viewModel: viewModel, newTodoTitle: $newTodoTitle, showSettings: $showSettings)
                    .frame(width: 330)
            }

            if shouldShowUpdateBanner {
                UpdateAvailableBanner(
                    currentVersion: updater.currentVersion,
                    latestVersion: updater.latestVersion ?? "",
                    onInstall: { updater.checkForUpdates() },
                    onDismiss: { updateBannerDismissedFor = updater.latestVersion }
                )
            }
        }
        .frame(width: showLeftPanel ? 1320 : 1040, height: 860)
        .task {
            // Hermes CloudKit upstream sync 시작 (UserDefaults 플래그 기반).
            // 활성화 안 돼 있으면 startIfEnabled가 nil 반환 → no-op.
            if hermesSync == nil {
                hermesSync = HermesMemorySync.startIfEnabled(service: hermesMemoryService)
            }
        }
        .background(
            ZStack {
                Color.platformControlBackground
                themeService.current.paneTint
            }
        )
        .animation(.easeInOut(duration: 0.28), value: themeService.current.id)
        .onChange(of: authManager.isAuthenticated) {
            viewModel.refreshEvents()
        }
        .onAppear {
            checkLeftPanelMode()
            scheduleNotifications()
            // 초개인화: aiService에 컨텍스트 서비스 주입
            aiService.userContextService = userContextService
            aiService.hermesMemoryService = hermesMemoryService
            aiService.userProfileProvider = { goalService.profile }
            refreshUserContextAnalysis()
            // 업데이트 배너용 appcast 직접 폴링 — Sparkle의 background check가
            // menubar(accessory) 앱에서 didFindValidUpdate delegate를 호출하지 않는
            // 케이스가 있어 자체 경로로 확인한다. 팝오버 열 때마다 한 번씩 호출 (가벼운 HTTP GET).
            Task { await updater.pollAppcastForBanner() }
            // Sparkle background check는 세션당 1회. 설치 다이얼로그 UI는 그대로 유지.
            if !didTriggerUpdateCheckThisSession {
                didTriggerUpdateCheckThisSession = true
                updater.checkForUpdatesInBackground()
            }
        }
        .onChange(of: viewModel.calendarEvents) {
            updateEventReminders()
            // refreshUserContextAnalysis는 debounce — 이벤트 배열이 fetch/merge로
            // 초단위 변화할 때마다 매번 돌면 CPU 폭주 원인이 된다.
            scheduleDebouncedContextRefresh()
        }
        .onChange(of: viewModel.todos.count) {
            scheduleDebouncedContextRefresh()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                goalService: goalService,
                authManager: authManager,
                aiService: aiService,
                viewModel: viewModel,
                userContextService: userContextService,
                hermesMemoryService: hermesMemoryService,
                onDismiss: { showSettings = false }
            )
        }
        // popover가 바깥 클릭으로 닫히면 설정 시트도 함께 닫기
        .onReceive(NotificationCenter.default.publisher(for: .calenPopoverDidClose)) { _ in
            showSettings = false
        }
    }

    /// 연쇄 변화(fetch/merge/optimistic update)마다 refreshUserContextAnalysis가
    /// 즉시 실행되면 Claude CLI가 과도하게 실행되고 CPU/메모리가 폭주한다.
    /// 5초 debounce 로 마지막 변경 이후 조용해진 다음 한 번만 실행.
    private func scheduleDebouncedContextRefresh() {
        contextRefreshTask?.cancel()
        contextRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5s
            if Task.isCancelled { return }
            refreshUserContextAnalysis()
        }
    }

    /// 업데이트 배너는 (1) 새 버전이 감지되었고 (2) 현재 버전보다 높고
    /// (3) 사용자가 이 버전에 대해 닫기 누른 적이 없을 때만 표시.
    private var shouldShowUpdateBanner: Bool {
        guard updater.updateAvailable,
              let latest = updater.latestVersion,
              !latest.isEmpty else { return false }
        if updateBannerDismissedFor == latest { return false }
        return latest.compare(updater.currentVersion, options: .numeric) == .orderedDescending
    }

    private func refreshUserContextAnalysis() {
        let todoTitles = viewModel.todos.map(\.title)
        let eventTitles = viewModel.calendarEvents.prefix(30).map(\.title)
        userContextService.analyzePlanningStyle(todos: todoTitles, events: Array(eventTitles))
        userContextService.analyzePersonalContext(
            todos: viewModel.todos,
            events: viewModel.calendarEvents,
            categories: viewModel.categories,
            goals: goalService.goals,
            completions: goalService.completions
        )
    }

    // MARK: - Left Panel

    @ViewBuilder
    private var leftPanel: some View {
        VStack(spacing: 0) {
            // Panel mode toggle (only if onboarding done)
            if goalService.profile.onboardingDone && leftPanelMode != .onboarding {
                HStack(spacing: 0) {
                    panelTab(String(localized: "panel.review"), mode: .review, icon: "sparkles")
                    panelTab(String(localized: "panel.chat"), mode: .chat, icon: "bubble.left")
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }

            // Panel content
            switch leftPanelMode {
            case .onboarding:
                OnboardingView(goalService: goalService, onComplete: {
                    leftPanelMode = .chat
                    reviewService.checkAndActivate()
                }, onSkip: {
                    goalService.profile.onboardingDone = true
                    goalService.saveProfile()
                    leftPanelMode = .chat
                })

            case .review:
                ReviewView(
                    reviewService: reviewService,
                    goalService: goalService,
                    goalMemoryService: goalMemoryService,
                    habitService: habitService,
                    viewModel: viewModel,
                    onCreateEvent: { title, start, end in
                        Task {
                            do {
                                if try await viewModel.googleService.createEvent(
                                    title: title, startDate: start, endDate: end, isAllDay: false) == nil {
                                    viewModel.reportCRUDFailure(operation: .create, source: .google)
                                }
                            } catch {
                                viewModel.reportCRUDFailure(operation: .create, source: .google, error: error)
                            }
                            viewModel.refreshEvents()
                        }
                    },
                    onDismiss: {
                        reviewService.dismissReview()
                        leftPanelMode = .chat
                    },
                    onRequestReplanDay: {
                        // 리뷰탭에서 경고형 suggestion 누르면 채팅으로 전환.
                        // 사용자가 채팅에서 "오늘 재계획" 버튼을 의식적으로 눌러 실행하게 함.
                        leftPanelMode = .chat
                    }
                )

            case .chat:
                ChatView(aiService: aiService, viewModel: viewModel,
                         goalMemoryService: goalMemoryService,
                         habitService: habitService,
                         hermesMemoryService: hermesMemoryService)
            }
        }
    }

    private func panelTab(_ label: String, mode: LeftPanelMode, icon: String) -> some View {
        Button {
            leftPanelMode = mode
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: leftPanelMode == mode ? .semibold : .regular))
            }
            .foregroundStyle(leftPanelMode == mode ? themeService.current.accent : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(leftPanelMode == mode ? themeService.current.accent.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode Detection

    private func checkLeftPanelMode() {
        if !goalService.profile.onboardingDone {
            leftPanelMode = .onboarding
            return
        }

        // Check if it's review time
        reviewService.checkAndActivate()
        if reviewService.currentMode != .none {
            leftPanelMode = .review
        }
    }

    // MARK: - Notifications

    private func scheduleNotifications() {
        notificationService.scheduleDailyBriefing(hour: goalService.profile.morningBriefHour)
        notificationService.scheduleEveningReview(hour: goalService.profile.eveningReviewHour)
        updateEventReminders()
    }

    private func updateEventReminders() {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let todayEvents = viewModel.calendarEvents
            .filter { $0.startDate >= today && $0.startDate < tomorrow && !$0.isAllDay }
            .map { (id: $0.id, title: $0.title, startDate: $0.startDate) }
        notificationService.scheduleRemindersForEvents(todayEvents)
    }
}

struct CRUDErrorInlineNotice: View {
    let notice: CRUDErrorNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(notice.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Calendar Grid

struct CalendarGridView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var showChat: Bool
    @ObservedObject private var themeService = CalendarThemeService.shared
    private let weekdays = [
        String(localized: "calendar.weekdays.sun"),
        String(localized: "calendar.weekdays.mon"),
        String(localized: "calendar.weekdays.tue"),
        String(localized: "calendar.weekdays.wed"),
        String(localized: "calendar.weekdays.thu"),
        String(localized: "calendar.weekdays.fri"),
        String(localized: "calendar.weekdays.sat")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with connection status
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showChat.toggle() } } label: {
                    Image(systemName: showChat ? "bubble.left.fill" : "bubble.left")
                        .font(.system(size: 14))
                        .foregroundStyle(showChat ? themeService.current.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "calendar.help.chat"))

                Text(viewModel.monthTitle())
                    .font(.system(size: 28, weight: .bold))

                if viewModel.authManager.isAuthenticated {
                    if viewModel.needsReauth {
                        Button {
                            viewModel.authManager.logout()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                                Text("캘린더 권한 업데이트 필요")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("일부 캘린더가 표시되지 않습니다. 탭하여 재로그인 → 전체 캘린더 권한 허용")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                            .help(String(localized: "calendar.help.google.connected"))
                    }
                }

                Spacer()
                HStack(spacing: 12) {
                    // 미완료 할 일 즉시 재배치 버튼
                    let overdueCount = viewModel.overdueLocalTodoCount()
                    if overdueCount > 0 {
                        Button {
                            viewModel.rescheduleNow()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.right.circle.fill")
                                    .font(.system(size: 12))
                                Text("\(overdueCount)")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(themeService.current.accent)
                        }
                        .buttonStyle(.plain)
                        .help("밀린 할 일 \(overdueCount)개를 지금 재배치")
                    }

                    Button(action: viewModel.previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                    Button(action: viewModel.nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // 주간 일정 밀도 바
            WeekDensityBar(events: viewModel.calendarEvents)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            index == 0 ? Color.red.opacity(0.7) :
                            index == 6 ? Color.blue.opacity(0.7) :
                            Color.secondary
                        )
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            let rows = viewModel.monthGridRows()

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(row) { day in
                            if let date = day.date {
                                DayCellView(
                                    date: date,
                                    isSelected: day.isSelected,
                                    isToday: day.isToday,
                                    isSunday: day.isSunday,
                                    isSaturday: day.isSaturday,
                                    isCurrentMonth: day.isCurrentMonth,
                                    events: day.events,
                                    todos: day.todos,
                                    categoryFor: { viewModel.category(for: $0) },
                                    categoryForEvent: { viewModel.categoryForEvent($0) },
                                    onDrop: { payload, targetDate in
                                        switch CalendarDragPayload(payload) {
                                        case .todo(let id):
                                            viewModel.moveTodo(id: id, toDate: targetDate)
                                        case .event(let id):
                                            viewModel.moveCalendarEvent(id: id, toDate: targetDate)
                                        case nil:
                                            return
                                        }
                                        viewModel.selectedDate = targetDate
                                    }
                                )
                                .onTapGesture { viewModel.selectedDate = date }
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Day Cell

struct DayCellView: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isSunday: Bool
    let isSaturday: Bool
    let isCurrentMonth: Bool
    let events: [CalendarEvent]
    let todos: [TodoItem]
    let categoryFor: (UUID) -> TodoCategory
    var categoryForEvent: ((CalendarEvent) -> TodoCategory?)? = nil
    var onDrop: ((String, Date) -> Void)? = nil

    @State private var isDropTarget = false
    @ObservedObject private var themeService = CalendarThemeService.shared

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var textColor: Color {
        if !isCurrentMonth { return .secondary.opacity(0.35) }
        if isToday { return .white }
        if isSunday { return Color.red.opacity(0.85) }
        if isSaturday { return Color.blue.opacity(0.85) }
        return .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            dayCellHeader
            dayCellItems
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(cellBackground))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(themeService.current.accent.opacity(isDropTarget ? 0.7 : 0), lineWidth: 2))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            onDrop?(payload, date)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private var cellBackground: Color {
        if isDropTarget { return themeService.current.accent.opacity(0.12) }
        // 다크 모드에서 0.65 오버레이가 너무 밝아 이벤트 텍스트가 묻히던 문제 수정.
        // accent를 낮은 투명도로 얇게 틴트하는 방식으로 변경.
        if isSelected { return themeService.current.accent.opacity(0.14) }
        return Color.clear
    }

    @ViewBuilder private var dayCellHeader: some View {
        HStack {
            if isToday {
                Text(dayNumber)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(themeService.current.gradient)
                            .shadow(color: themeService.current.primary.opacity(0.35), radius: 3, x: 0, y: 1)
                    )
            } else {
                Text(dayNumber)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(textColor)
                    .frame(width: 26, height: 26)
            }
            Spacer()
        }
    }

    @ViewBuilder private var dayCellItems: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(events.prefix(4)), id: \.id) { event in
                let displayColor = categoryForEvent?(event)?.color ?? themeService.current.eventTint
                Text(event.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 3).fill(displayColor.opacity(0.15)))
                    .foregroundStyle(isCurrentMonth ? displayColor.opacity(0.85) : .secondary.opacity(0.3))
            }
            ForEach(Array(todos.prefix(max(0, 4 - events.count))), id: \.id) { todo in
                DayCellTodoRow(todo: todo, cat: categoryFor(todo.categoryID), isCurrentMonth: isCurrentMonth)
            }
        }
    }
}

private struct DayCellTodoRow: View {
    let todo: TodoItem
    let cat: TodoCategory
    let isCurrentMonth: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(cat.color.opacity(0.7)).frame(width: 5, height: 5)
            Text(todo.title)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 3).fill(cat.color.opacity(0.1)))
        .foregroundStyle(isCurrentMonth ? cat.color.opacity(0.85) : .secondary.opacity(0.3))
    }
}

// MARK: - Daily Detail

struct DailyDetailView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var newTodoTitle: String
    @Binding var showSettings: Bool

    @StateObject private var updater = UpdaterService.shared
    @ObservedObject private var themeService = CalendarThemeService.shared
    @State private var selectedCategoryID: UUID?
    @State private var isRepeating: Bool = false
    @State private var showCategoryManager = false
    @State private var showAddForm = false
    @State private var tappedTodo: TodoItem? = nil
    @State private var tappedEvent: CalendarEvent? = nil
    @State private var addTitle = ""
    @State private var addCategoryID: UUID?
    @State private var addType: TodoType = .normal

    /// 빈 하루 아이콘/메시지 — 오늘/과거/미래에 따라 변화
    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(viewModel.selectedDate)
    }
    private var isPastSelected: Bool {
        viewModel.selectedDate < Calendar.current.startOfDay(for: Date())
    }
    private var emptyDayIcon: String {
        if isTodaySelected { return "sparkles" }
        if isPastSelected { return "moon.stars" }
        return "sun.max"
    }
    private var emptyDayMessage: String {
        if isTodaySelected { return "오늘은 여유로운 하루" }
        if isPastSelected { return "기록된 일정 없음" }
        return "비어있는 하루"
    }
    private var emptyDayHint: String {
        if isTodaySelected { return "채팅으로 계획을 세워보거나\n아래 '할 일 추가'를 눌러보세요" }
        if isPastSelected { return "" }
        return "채팅으로 미리 준비하거나\n직접 일정을 추가해보세요"
    }

    // 통합 드래그 재배치 상태 (events + todos 한 리스트)
    @State private var draggingItemID: String? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var pendingItemOrder: [String] = []
    /// 각 행의 예상 높이 — 행 콘텐츠(패딩 포함) + 행 간 간격
    private let rowSlotHeight: CGFloat = 58

    private var dDayText: String {
        let diff = viewModel.daysSinceToday(viewModel.selectedDate)
        if diff == 0 { return String(localized: "detail.dday.today") }
        return diff > 0 ? "D - \(diff)" : "D + \(abs(diff))"
    }

    private var showModal: Bool {
        tappedTodo != nil || tappedEvent != nil
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.formattedDate(viewModel.selectedDate))
                            .font(.system(size: 18, weight: .bold))
                        HStack(spacing: 8) {
                            Text(dDayText)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            if viewModel.appleRemindersEnabled && viewModel.appleRemindersAccessGranted {
                                Text(String(localized: "detail.reminders"))
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(themeService.current.accent.opacity(0.15)))
                                    .foregroundStyle(themeService.current.accent)
                            }
                        }
                    }
                    Spacer()

                    HStack(spacing: 8) {
                        // 업데이트 알림은 팝오버 하단 UpdateAvailableBanner가 담당 —
                        // 여기 헤더의 capsule 배지는 폭이 좁은 DailyDetailView에서
                        // 텍스트가 세로로 쥐어지는 레이아웃 깨짐 때문에 제거.

                        Button {
                            showCategoryManager.toggle()
                        } label: {
                            Image(systemName: "tag")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("카테고리 관리")

                        Button {
                            showSettings = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                // 업데이트 있으면 빨간 점 뱃지
                                if updater.updateAvailable {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 2, y: -2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("설정")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                if let notice = viewModel.lastCRUDError {
                    CRUDErrorInlineNotice(notice: notice) {
                        viewModel.dismissLastCRUDError()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                // Events & Todos list
                ScrollView {
                    // 행 사이 gap(spacing) 대신 각 행의 vertical padding으로 처리 —
                    // 이래야 드롭 타겟 사이 "dead zone"이 생기지 않는다.
                    VStack(alignment: .leading, spacing: 0) {
                        let items = viewModel.itemsForDate(viewModel.selectedDate)
                        ForEach(items) { item in
                            let isDragging = draggingItemID == item.id
                            let offset = isDragging ? dragOffset : itemDisplacement(for: item.id, in: items)
                            switch item {
                            case .event(let event):
                                EventRowView(
                                    event: event,
                                    category: viewModel.categoryForEvent(event),
                                    isCompleted: viewModel.isEventCompleted(event.id),
                                    onTap: {
                                        tappedEvent = event
                                        tappedTodo = nil
                                    },
                                    onToggle: { viewModel.toggleEventCompleted(event.id, title: event.title) },
                                    isDragging: isDragging,
                                    yOffset: offset,
                                    handleDragGesture: itemReorderGesture(for: item.id, allItems: items)
                                )
                                .padding(.vertical, 4)
                            case .todo(let todo):
                                let cat = viewModel.category(for: todo.categoryID)
                                TodoRowView(
                                    todo: todo,
                                    category: cat,
                                    isRescheduled: viewModel.rescheduledTodoIDs.contains(todo.id),
                                    onTap: {
                                        tappedTodo = todo
                                        tappedEvent = nil
                                    },
                                    onToggle: { viewModel.toggleTodo(id: todo.id) },
                                    isDragging: isDragging,
                                    yOffset: offset,
                                    handleDragGesture: todo.source == .local
                                        ? itemReorderGesture(for: item.id, allItems: items)
                                        : nil
                                )
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity
                                ))
                            }
                        }

                        if items.isEmpty && !showAddForm {
                            VStack(spacing: 10) {
                                Image(systemName: emptyDayIcon)
                                    .font(.system(size: 32))
                                    .foregroundStyle(themeService.current.accent.opacity(0.4))
                                Text(emptyDayMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Text(emptyDayHint)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 0)

                // Add form
                if showAddForm {
                    InlineAddTodoForm(
                        viewModel: viewModel,
                        selectedDate: viewModel.selectedDate,
                        onAdd: { title, categoryID, date, isRepeat in
                            viewModel.addTodo(title: title, categoryID: categoryID, date: date, isRepeating: isRepeat)
                            showAddForm = false
                        },
                        onCancel: { showAddForm = false }
                    )
                } else {
                    Button {
                        showAddForm = true
                        tappedTodo = nil
                        tappedEvent = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 16))
                            Text(String(localized: "detail.add.todo")).font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(themeService.current.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(themeService.current.backgroundOverlay.opacity(0.65)))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

            // Modal overlay
            if showModal {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        tappedTodo = nil
                        tappedEvent = nil
                    }

                VStack {
                    Spacer()
                    if let event = tappedEvent {
                        ModalEventDetail(
                            viewModel: viewModel,
                            event: event,
                            onClose: { tappedEvent = nil }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let todo = tappedTodo {
                        ModalTodoDetail(
                            viewModel: viewModel,
                            todo: todo,
                            onClose: { tappedTodo = nil }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.2), value: tappedTodo?.id)
                .animation(.easeInOut(duration: 0.2), value: tappedEvent?.id)
            }
        }
        .background(
            ZStack {
                Color.platformWindowBackground.opacity(0.5)
                themeService.current.paneTint
            }
        )
        .popover(isPresented: $showCategoryManager) {
            CategoryManagerView(viewModel: viewModel)
        }
    }

    // MARK: - Unified Item Reorder Drag (events + todos, 리뷰페이지 스타일)

    /// 드래그 중이 아닐 때 다른 행이 비켜야 할 y 변위. pendingOrder 기준.
    /// Apple Reminder는 재배치 대상이 아니므로 displacement 계산에서 제외.
    private func itemDisplacement(for id: String, in items: [CalendarViewModel.DayItem]) -> CGFloat {
        guard let dID = draggingItemID, dID != id else { return 0 }
        let reorderable = items.filter { !isReminder($0) }.map(\.id)
        guard let origIdx = reorderable.firstIndex(of: id),
              let pendIdx = pendingItemOrder.firstIndex(of: id),
              origIdx != pendIdx else { return 0 }
        return CGFloat(pendIdx - origIdx) * rowSlotHeight
    }

    private func isReminder(_ item: CalendarViewModel.DayItem) -> Bool {
        if case .todo(let t) = item, t.source == .appleReminder { return true }
        return false
    }

    /// 현재 드래그 offset으로 통합 예상 순서를 계산.
    private func computePendingItemOrder(
        dragging id: String, offset: CGFloat, allItems: [CalendarViewModel.DayItem]
    ) -> [String] {
        let ids = allItems.filter { !isReminder($0) }.map(\.id)
        guard let fromIdx = ids.firstIndex(of: id) else { return ids }
        let steps = Int((offset / rowSlotHeight).rounded())
        let toIdx = max(0, min(ids.count - 1, fromIdx + steps))
        guard toIdx != fromIdx else { return ids }
        var result = ids
        result.move(fromOffsets: IndexSet(integer: fromIdx),
                    toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        return result
    }

    /// 통합 재배치 제스처 — 이벤트와 할일을 하나의 풀에서 재배치.
    /// coordinateSpace: .global — 행이 .offset으로 움직여도 translation이 절대 좌표 기준이므로 lag 없음.
    private func itemReorderGesture(
        for id: String, allItems: [CalendarViewModel.DayItem]
    ) -> AnyGesture<DragGesture.Value> {
        AnyGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if draggingItemID != id {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                        draggingItemID = id
                        pendingItemOrder = allItems.filter { !isReminder($0) }.map(\.id)
                    }
                }
                dragOffset = value.translation.height
                let newPending = computePendingItemOrder(
                    dragging: id, offset: dragOffset, allItems: allItems
                )
                if newPending != pendingItemOrder {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        pendingItemOrder = newPending
                    }
                }
            }
            .onEnded { _ in
                if !pendingItemOrder.isEmpty {
                    viewModel.setDayItemOrder(pendingItemOrder, on: viewModel.selectedDate)
                }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    draggingItemID = nil
                    dragOffset = 0
                    pendingItemOrder = []
                }
            })
    }
}

// MARK: - Category Manager (Popover)
// TODO(calendar-theme): migrate remaining calendar editor/form accents after separating semantic action colors from palette colors.

struct CategoryManagerView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @State private var newName = ""
    @State private var newColorHex = CategoryColor.presets[0].hex

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "category.manage.title"))
                .font(.system(size: 14, weight: .bold))

            ForEach(viewModel.categories) { cat in
                HStack(spacing: 8) {
                    Circle().fill(cat.color).frame(width: 12, height: 12)
                    Text(cat.name).font(.system(size: 13))
                    Spacer()
                    if viewModel.categories.count > 1 {
                        Button {
                            viewModel.deleteCategory(id: cat.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Text(String(localized: "category.new"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(CategoryColor.presets) { preset in
                    Circle()
                        .fill(Color(hex: preset.hex) ?? .blue)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: newColorHex == preset.hex ? 2 : 0)
                        )
                        .onTapGesture { newColorHex = preset.hex }
                }
            }

            HStack(spacing: 8) {
                TextField(String(localized: "category.name.placeholder"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Button {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        viewModel.addCategory(name: trimmed, colorHex: newColorHex)
                        newName = ""
                    }
                } label: {
                    Text(String(localized: "common.add"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - Modal Event Detail (overlay)

struct ModalEventDetail: View {
    @ObservedObject var viewModel: CalendarViewModel
    let event: CalendarEvent
    let onClose: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editIsAllDay = false
    @State private var editStartDate = Date()
    @State private var editEndDate = Date()

    private var timeText: String {
        if event.isAllDay { return String(localized: "event.detail.allday") }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }

    private var dateText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateStyle = .medium
        return fmt.string(from: event.startDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "event.detail.title")).font(.system(size: 15, weight: .bold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if isEditing {
                    TextField(String(localized: "event.field.title"), text: $editTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.platformTextBackground.opacity(0.5)))

                    Toggle(String(localized: "event.toggle.allday"), isOn: $editIsAllDay).font(.system(size: 13))

                    if !editIsAllDay {
                        DatePicker(String(localized: "event.detail.start"), selection: $editStartDate, displayedComponents: [.date, .hourAndMinute]).font(.system(size: 12))
                        DatePicker(String(localized: "event.detail.end"), selection: $editEndDate, displayedComponents: [.date, .hourAndMinute]).font(.system(size: 12))
                    }
                } else {
                    // 카테고리 매핑이 있으면 카테고리 색상, 없으면 Google 캘린더 색상
                    let mappedCatID = viewModel.eventCategoryMappings[event.id]?.categoryID
                    let barColor: Color = mappedCatID.flatMap { id in viewModel.categories.first(where: { $0.id == id })?.color } ?? event.color

                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(barColor).frame(width: 5)
                        Text(event.title).font(.system(size: 16, weight: .semibold))
                    }.frame(height: 24)

                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(dateText).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(timeText).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    if !event.calendarName.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "tray").font(.system(size: 13)).foregroundStyle(.secondary)
                            Text(event.calendarName).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isEventCompleted(event.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(viewModel.isEventCompleted(event.id) ? .green : .secondary)
                        Text(viewModel.isEventCompleted(event.id) ? String(localized: "common.completed") : String(localized: "common.incomplete")).font(.system(size: 13)).foregroundStyle(.secondary)
                    }

                    // 이벤트 카테고리 매핑 (이 이벤트 독립적으로 적용)
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "event.category.label"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Button {
                                    viewModel.setEventCategory(eventID: event.id, eventTitle: event.title, categoryID: nil)
                                } label: {
                                    Text(String(localized: "event.category.none"))
                                        .font(.system(size: 11))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(mappedCatID == nil ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.1)))
                                        .foregroundStyle(mappedCatID == nil ? .primary : .secondary)
                                }.buttonStyle(.plain)

                                ForEach(viewModel.categories) { cat in
                                    Button {
                                        viewModel.setEventCategory(eventID: event.id, eventTitle: event.title, categoryID: cat.id)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle().fill(cat.color).frame(width: 8, height: 8)
                                            Text(cat.name).font(.system(size: 11))
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(mappedCatID == cat.id ? cat.color.opacity(0.25) : cat.color.opacity(0.08)))
                                        .foregroundStyle(mappedCatID == cat.id ? cat.color : .secondary)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Spacer(minLength: 0)
            Divider()

            if isEditing {
                HStack(spacing: 12) {
                    Button { isEditing = false } label: {
                        Text(String(localized: "common.cancel")).font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.plain)
                    Button {
                        let t = editTitle.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty {
                            let end = editIsAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: editStartDate)! : editEndDate
                            _ = viewModel.updateCalendarEvent(eventID: event.id, calendarID: event.calendarID, title: t, startDate: editStartDate, endDate: end, isAllDay: editIsAllDay)
                        }
                        onClose()
                    } label: {
                        Text(String(localized: "common.save")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            } else {
                HStack(spacing: 8) {
                    Button { viewModel.toggleEventCompleted(event.id, title: event.title); onClose() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isEventCompleted(event.id) ? "arrow.uturn.backward" : "checkmark").font(.system(size: 12))
                            Text(viewModel.isEventCompleted(event.id) ? String(localized: "common.incomplete") : String(localized: "common.done")).font(.system(size: 13))
                        }.foregroundStyle(.green).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
                    }.buttonStyle(.plain)

                    Button {
                        editTitle = event.title; editStartDate = event.startDate; editEndDate = event.endDate; editIsAllDay = event.isAllDay
                        isEditing = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil").font(.system(size: 12))
                            Text(String(localized: "common.edit")).font(.system(size: 13))
                        }.foregroundStyle(.blue).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                    }.buttonStyle(.plain)

                    Button {
                        _ = viewModel.deleteCalendarEvent(eventID: event.id, calendarID: event.calendarID)
                        onClose()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash").font(.system(size: 12))
                            Text(String(localized: "common.delete")).font(.system(size: 13))
                        }.foregroundStyle(.red).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .frame(width: 280, height: 320)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.platformWindowBackground))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 5)
    }
}

// MARK: - Modal Todo Detail (overlay)

struct ModalTodoDetail: View {
    @ObservedObject var viewModel: CalendarViewModel
    let todo: TodoItem
    let onClose: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editCategoryID = UUID()
    @State private var editDate = Date()
    @State private var selectedCategoryID: UUID? = nil

    private var category: TodoCategory {
        viewModel.category(for: selectedCategoryID ?? todo.categoryID)
    }

    private var dateText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateStyle = .medium
        return fmt.string(from: todo.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Text(String(localized: "todo.detail.title")).font(.system(size: 15, weight: .bold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if isEditing {
                    // 수정 모드: 제목 입력
                    TextField(String(localized: "event.field.title"), text: $editTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.platformTextBackground.opacity(0.5)))

                    // 날짜 선택
                    DatePicker(String(localized: "event.detail.start"), selection: $editDate, displayedComponents: [.date])
                        .font(.system(size: 12))
                } else {
                    // 보기 모드: image2 스타일 — 컬러 바 + 제목
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(category.color).frame(width: 5)
                        Text(todo.title).font(.system(size: 16, weight: .semibold))
                            .strikethrough(todo.isCompleted)
                            .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    }.frame(height: 24)

                    // 날짜 행
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(dateText).font(.system(size: 13)).foregroundStyle(.secondary)
                        if todo.isRepeating {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)).foregroundStyle(.blue)
                        }
                    }

                    // 소스 행 (앱 내 할 일)
                    HStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(String(localized: "todo.source.local")).font(.system(size: 13)).foregroundStyle(.secondary)
                    }

                    // 완료 상태 행
                    HStack(spacing: 8) {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        Text(todo.isCompleted ? String(localized: "common.completed") : String(localized: "common.incomplete"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }

                    // 카테고리 피커 (image2 스타일)
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "event.category.label"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(viewModel.categories) { cat in
                                    let isSelected = (selectedCategoryID ?? todo.categoryID) == cat.id
                                    Button {
                                        selectedCategoryID = cat.id
                                        viewModel.updateTodo(id: todo.id, title: todo.title, categoryID: cat.id)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle().fill(cat.color).frame(width: 8, height: 8)
                                            Text(cat.name).font(.system(size: 11))
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? cat.color.opacity(0.25) : cat.color.opacity(0.08)))
                                        .foregroundStyle(isSelected ? cat.color : .secondary)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .onAppear { selectedCategoryID = todo.categoryID }

            Spacer(minLength: 0)
            Divider()

            if isEditing {
                HStack(spacing: 12) {
                    Button { isEditing = false } label: {
                        Text(String(localized: "common.cancel")).font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.plain)
                    Button {
                        let t = editTitle.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { viewModel.updateTodo(id: todo.id, title: t, categoryID: editCategoryID, date: editDate) }
                        onClose()
                    } label: {
                        Text(String(localized: "common.save")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            } else {
                HStack(spacing: 8) {
                    Button { viewModel.toggleTodo(id: todo.id); onClose() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: todo.isCompleted ? "arrow.uturn.backward" : "checkmark").font(.system(size: 12))
                            Text(todo.isCompleted ? String(localized: "common.incomplete") : String(localized: "common.done")).font(.system(size: 13))
                        }.foregroundStyle(.green).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
                    }.buttonStyle(.plain)

                    Button {
                        editTitle = todo.title; editCategoryID = todo.categoryID; editDate = todo.date; isEditing = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil").font(.system(size: 12))
                            Text(String(localized: "common.edit")).font(.system(size: 13))
                        }.foregroundStyle(.blue).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)))
                    }.buttonStyle(.plain)

                    Button { viewModel.deleteTodo(id: todo.id); onClose() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash").font(.system(size: 12))
                            Text(String(localized: "common.delete")).font(.system(size: 13))
                        }.foregroundStyle(.red).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .frame(width: 280, height: 320)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.platformWindowBackground))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 5)
    }
}

// MARK: - Inline Add Todo Form

enum TodoType: String, CaseIterable {
    case normal = "일반"
    case repeating = "반복"
}

struct InlineAddTodoForm: View {
    @ObservedObject var viewModel: CalendarViewModel
    let selectedDate: Date
    let onAdd: (_ title: String, _ categoryID: UUID, _ date: Date, _ isRepeat: Bool) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var categoryID: UUID?
    @State private var todoType: TodoType = .normal

    private var effectiveCategoryID: UUID {
        categoryID ?? viewModel.defaultCategoryID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(viewModel.category(for: effectiveCategoryID).color).frame(width: 8, height: 8)
                TextField(String(localized: "todo.input.placeholder"), text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .onSubmit { submit() }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(viewModel.categories) { cat in
                        Button { categoryID = cat.id } label: {
                            Text(cat.name)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(effectiveCategoryID == cat.id ? cat.color.opacity(0.25) : Color.platformControlBackground))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(effectiveCategoryID == cat.id ? cat.color : Color.clear, lineWidth: 1))
                                .foregroundStyle(effectiveCategoryID == cat.id ? cat.color : .secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Button { todoType = todoType == .normal ? .repeating : .normal } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                        Text(String(localized: "common.repeat")).font(.system(size: 10))
                    }
                    .foregroundStyle(todoType == .repeating ? .blue : .secondary.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(todoType == .repeating ? Color.blue.opacity(0.1) : Color.clear))
                }.buttonStyle(.plain)

                Spacer()
            }

            HStack(spacing: 8) {
                Spacer()
                Button { onCancel() } label: {
                    Text(String(localized: "common.cancel")).font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)

                Button { submit() } label: {
                    Text(String(localized: "common.add")).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.15), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed, effectiveCategoryID, selectedDate, todoType == .repeating)
    }
}

// MARK: - Drag Payload

enum CalendarDragPayload {
    case event(String)
    case todo(UUID)

    init?(_ raw: String) {
        if raw.hasPrefix("event:") {
            let id = String(raw.dropFirst("event:".count))
            guard !id.isEmpty else { return nil }
            self = .event(id)
        } else if raw.hasPrefix("todo:") {
            let rawID = String(raw.dropFirst("todo:".count))
            guard let uuid = UUID(uuidString: rawID) else { return nil }
            self = .todo(uuid)
        } else {
            return nil
        }
    }
}

// MARK: - Drag Ghost Preview

/// 드래그 중 커서 옆에 표시되는 고스트 블록
struct DragGhostRow: View {
    let title: String
    let color: Color
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.platformControlBackground)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        )
        .opacity(0.92)
    }
}

// MARK: - Event Row

struct EventRowView: View {
    let event: CalendarEvent
    var category: TodoCategory? = nil    // 매핑된 카테고리 (있으면 색상 오버라이드)
    var isCompleted: Bool = false
    var onTap: () -> Void = {}
    var onToggle: (() -> Void)? = nil
    /// 리뷰페이지 스타일 드래그 재배치 지원용 상태 (부모가 주입)
    var isDragging: Bool = false
    var yOffset: CGFloat = 0
    /// 드래그 핸들 영역에만 부착할 제스처. nil이면 핸들 숨김.
    var handleDragGesture: AnyGesture<DragGesture.Value>? = nil

    @State private var isHandleHover: Bool = false

    private var displayColor: Color { category?.color ?? event.color }

    private var timeText: String {
        if event.isAllDay { return String(localized: "event.detail.allday") }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }

    var body: some View {
        HStack(spacing: 10) {
            // 드래그 핸들 — 리오더 전용
            if let reorderGesture = handleDragGesture {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHandleHover || isDragging ? .primary : Color.secondary.opacity(0.5))
                    .frame(width: 20, height: 32)
                    .contentShape(Rectangle())
                    .onHover { isHandleHover = $0 }
                    .help("드래그해서 순서 변경")
                    .highPriorityGesture(reorderGesture)
            }

            RoundedRectangle(cornerRadius: 2).fill(displayColor).frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                    if let cat = category {
                        Text(cat.name)
                            .font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(cat.color.opacity(0.15)))
                            .foregroundStyle(cat.color)
                    }
                }
                Text(timeText).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer()

            Button { onToggle?() } label: {
                ZStack {
                    Circle()
                        .stroke(isCompleted ? displayColor : Color.secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isCompleted {
                        Circle().fill(displayColor.opacity(0.15)).frame(width: 22, height: 22)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(displayColor)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.platformControlBackground)
                .shadow(color: .black.opacity(isDragging ? 0.22 : 0.04),
                        radius: isDragging ? 14 : 2,
                        y: isDragging ? 6 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .scaleEffect(isDragging ? 1.025 : 1.0, anchor: .center)
        .offset(y: yOffset)
        .zIndex(isDragging ? 100 : 0)
        .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.72),
                   value: yOffset)
        .draggable("event:\(event.id)") {
            DragGhostRow(title: event.title, color: displayColor, subtitle: timeText)
        }
    }
}

// MARK: - Todo Row

struct TodoRowView: View {
    let todo: TodoItem
    let category: TodoCategory
    @ObservedObject private var themeService = CalendarThemeService.shared
    var isSelected: Bool = false
    var isRescheduled: Bool = false   // Calen이 자동 재배치한 항목
    var onTap: () -> Void = {}
    let onToggle: () -> Void
    /// 리뷰페이지 스타일 드래그 재배치 지원용 상태 (부모가 주입)
    var isDragging: Bool = false
    var yOffset: CGFloat = 0
    /// 리오더 모드 진입됨 — 드래그 핸들을 잡았을 때 true.
    var isReorderMode: Bool = false
    /// 드래그 핸들 영역에만 부착할 제스처. nil이면 핸들 숨김 (재배치 불가).
    var handleDragGesture: AnyGesture<DragGesture.Value>? = nil

    @State private var isHandleHover: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // 드래그 핸들 — 리오더 전용 hit 영역. highPriorityGesture로 .draggable보다 우선.
            if let reorderGesture = handleDragGesture {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHandleHover || isDragging ? .primary : Color.secondary.opacity(0.5))
                    .frame(width: 20, height: 32)
                    .contentShape(Rectangle())
                    .onHover { isHandleHover = $0 }
                    .help("드래그해서 순서 변경")
                    .highPriorityGesture(reorderGesture)
            }

            RoundedRectangle(cornerRadius: 2)
                .fill(todo.source == .appleReminder ? Color.orange : category.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(todo.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(todo.isCompleted)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    if todo.source == .appleReminder {
                        Text(String(localized: "detail.reminders"))
                            .font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    } else {
                        Text(category.name)
                            .font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(category.color.opacity(0.15)))
                            .foregroundStyle(category.color)
                    }
                    // Calen 자동 재배치 인디케이터
                    if isRescheduled && !todo.isCompleted {
                        Image(systemName: "arrow.uturn.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(themeService.current.accent.opacity(0.7))
                            .help("Calen이 자동으로 재배치한 할 일입니다")
                    }
                }
                if todo.isRepeating {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button { onToggle() } label: {
                let accentColor = todo.source == .appleReminder ? Color.orange : category.color
                ZStack {
                    Circle()
                        .stroke(todo.isCompleted ? accentColor : Color.secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if todo.isCompleted {
                        Circle().fill(accentColor.opacity(0.15)).frame(width: 22, height: 22)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(accentColor)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.platformControlBackground)
                .shadow(color: .black.opacity(isDragging ? 0.22 : 0.04),
                        radius: isDragging ? 14 : 2,
                        y: isDragging ? 6 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .scaleEffect(isDragging ? 1.025 : 1.0, anchor: .center)
        .offset(y: yOffset)
        .zIndex(isDragging ? 100 : 0)
        .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.72),
                   value: yOffset)
        // 전체 행에 .draggable — 핸들 위에서 시작한 드래그는 highPriorityGesture가 가로채므로 안전
        .draggable("todo:\(todo.id.uuidString)") {
            DragGhostRow(
                title: todo.title,
                color: todo.source == .appleReminder ? Color.orange : category.color,
                subtitle: todo.source == .appleReminder ? String(localized: "detail.reminders") : category.name
            )
        }
    }
}

// MARK: - Week Density Bar

/// 이번 주 7일의 일정 밀도를 미니 히트맵으로 표시.
/// 바쁜 날: 빨강, 보통: 노랑, 여유: 초록, 오늘: 테두리 강조
struct WeekDensityBar: View {
    let events: [CalendarEvent]

    private let scheduler = SmartSchedulerService()
    private let calendar = Calendar.current

    private var thisWeekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) - 1  // 0=일
        let monday = calendar.date(byAdding: .day, value: -weekday, to: today)!
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        let days = thisWeekDays
        let analyses = scheduler.analyzeDays(events: events, for: days)
        let dayFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "E"
            f.locale = Locale(identifier: "ko_KR"); return f
        }()

        HStack(spacing: 3) {
            ForEach(Array(zip(days, analyses).enumerated()), id: \.offset) { _, pair in
                let (date, analysis) = pair
                let isToday = calendar.isDateInToday(date)
                let barColor = densityColor(analysis.loadPercent)

                VStack(spacing: 2) {
                    // 밀도 바
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.75))
                        .frame(height: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(isToday ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    // 요일 레이블 (오늘만 강조)
                    Text(dayFmt.string(from: date))
                        .font(.system(size: 8))
                        .foregroundStyle(isToday ? .primary : .tertiary)
                }
                .frame(maxWidth: .infinity)
                .help("\(dayFmt.string(from: date)): 일정 \(analysis.timedEvents.count)개, 여유 \(analysis.totalFreeMinutes / 60)h [\(analysis.loadLabel)]")
            }
        }
    }

    private func densityColor(_ percent: Int) -> Color {
        switch percent {
        case 0..<30:  return .green
        case 30..<60: return .yellow
        default:      return .red
        }
    }
}
