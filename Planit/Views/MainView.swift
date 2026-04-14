import SwiftUI
import UserNotifications

struct MainView: View {
    @StateObject private var authManager = GoogleAuthManager()
    @State private var newTodoTitle: String = ""

    private var shouldShowLogin: Bool {
        !authManager.isAuthenticated && !UserDefaults.standard.bool(forKey: "planit.skipGoogleAuth")
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
    @State private var showLeftPanel: Bool = true
    @State private var leftPanelMode: LeftPanelMode = .chat
    @State private var showSettings: Bool = false

    init(authManager: GoogleAuthManager, newTodoTitle: Binding<String>) {
        self.authManager = authManager
        self._newTodoTitle = newTodoTitle
        let vm = CalendarViewModel(authManager: authManager)
        self._viewModel = StateObject(wrappedValue: vm)
        self._aiService = StateObject(wrappedValue: AIService(
            authManager: authManager,
            calendarService: vm.googleService
        ))
        let gs = GoalService()
        self._goalService = StateObject(wrappedValue: gs)
        self._reviewService = StateObject(wrappedValue: ReviewService(
            goalService: gs,
            calendarService: vm.googleService
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            if showLeftPanel {
                leftPanel
                    .frame(width: 280)
                Divider()
            }

            CalendarGridView(viewModel: viewModel, showChat: $showLeftPanel)
                .frame(width: showLeftPanel ? 560 : 620)

            DailyDetailView(viewModel: viewModel, newTodoTitle: $newTodoTitle, showSettings: $showSettings)
                .frame(width: 310)
        }
        .frame(width: showLeftPanel ? 1150 : 930, height: 780)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: authManager.isAuthenticated) { _ in
            viewModel.refreshEvents()
        }
        .onAppear {
            checkLeftPanelMode()
            scheduleNotifications()
        }
        .onChange(of: viewModel.calendarEvents) { _ in
            updateEventReminders()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                goalService: goalService,
                authManager: authManager,
                aiService: aiService,
                viewModel: viewModel,
                onDismiss: { showSettings = false }
            )
        }
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
                OnboardingView(goalService: goalService) {
                    leftPanelMode = .chat
                    reviewService.checkAndActivate()
                }

            case .review:
                ReviewView(
                    reviewService: reviewService,
                    goalService: goalService,
                    onCreateEvent: { title, start, end in
                        Task {
                            _ = try? await viewModel.googleService.createEvent(
                                title: title, startDate: start, endDate: end, isAllDay: false)
                            viewModel.refreshEvents()
                        }
                    },
                    onDismiss: {
                        reviewService.dismissReview()
                        leftPanelMode = .chat
                    }
                )

            case .chat:
                ChatView(aiService: aiService, viewModel: viewModel)
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
            .foregroundStyle(leftPanelMode == mode ? .purple : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(leftPanelMode == mode ? Color.purple.opacity(0.1) : Color.clear)
            )
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

// MARK: - Calendar Grid

struct CalendarGridView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var showChat: Bool
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
                        .foregroundStyle(showChat ? .purple : .secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "calendar.help.chat"))

                Text(viewModel.monthTitle())
                    .font(.system(size: 28, weight: .bold))

                if viewModel.authManager.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .help(String(localized: "calendar.help.google.connected"))
                }

                Spacer()
                HStack(spacing: 12) {
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
            }.padding(.horizontal, 12)

            let days = viewModel.daysInMonth()
            let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0+7, days.count)]) }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, date in
                            if let date = date {
                                DayCellView(
                                    date: date,
                                    isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                                    isToday: viewModel.isToday(date),
                                    isSunday: viewModel.isSunday(date),
                                    isSaturday: viewModel.isSaturday(date),
                                    isCurrentMonth: viewModel.isCurrentMonth(date),
                                    events: viewModel.eventsForDate(date),
                                    todos: viewModel.todosForDate(date),
                                    categoryFor: { viewModel.category(for: $0) },
                                    onDrop: { payload, targetDate in
                                        if payload.hasPrefix("todo:"),
                                           let id = UUID(uuidString: String(payload.dropFirst(5))) {
                                            viewModel.moveTodo(id: id, toDate: targetDate)
                                        } else if payload.hasPrefix("event:") {
                                            viewModel.moveCalendarEvent(id: String(payload.dropFirst(6)), toDate: targetDate)
                                        }
                                        viewModel.selectedDate = targetDate
                                    }
                                )
                                .onTapGesture { viewModel.selectedDate = date }
                            } else {
                                VStack { Spacer() }
                                    .frame(maxWidth: .infinity, minHeight: 105)
                            }
                        }
                    }
                }
            }.padding(.horizontal, 8)

            Spacer(minLength: 0)
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
    var onDrop: ((String, Date) -> Void)? = nil

    @State private var isDropTarget = false

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
            HStack {
                if isToday {
                    Text(dayNumber)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.blue))
                } else {
                    Text(dayNumber)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(textColor)
                        .frame(width: 26, height: 26)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                    Text(event.title.count > 10 ? String(event.title.prefix(10)) : event.title)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 3).fill(event.color.opacity(0.15)))
                        .foregroundStyle(isCurrentMonth ? event.color.opacity(0.85) : .secondary.opacity(0.3))
                }
                ForEach(Array(todos.prefix(max(0, 3 - events.count)).enumerated()), id: \.offset) { _, todo in
                    let cat = categoryFor(todo.categoryID)
                    HStack(spacing: 2) {
                        Circle().fill(cat.color.opacity(0.7)).frame(width: 4, height: 4)
                        Text(todo.title.count > 10 ? String(todo.title.prefix(10)) : todo.title)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 3).fill(cat.color.opacity(0.1)))
                    .foregroundStyle(isCurrentMonth ? cat.color.opacity(0.85) : .secondary.opacity(0.3))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6).fill(
            isDropTarget ? Color.purple.opacity(0.12) : (isSelected ? Color.blue.opacity(0.08) : Color.clear)
        ))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.purple.opacity(isDropTarget ? 0.7 : 0), lineWidth: 2)
        )
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            onDrop?(payload, date)
            return true
        } isTargeted: { isDropTarget = $0 }
    }
}

// MARK: - Daily Detail

struct DailyDetailView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var newTodoTitle: String
    @Binding var showSettings: Bool

    @State private var selectedCategoryID: UUID?
    @State private var isRepeating: Bool = false
    @State private var showCategoryManager = false
    @State private var showAddForm = false
    @State private var tappedTodo: TodoItem? = nil
    @State private var tappedEvent: CalendarEvent? = nil
    @State private var addTitle = ""
    @State private var addCategoryID: UUID?
    @State private var addType: TodoType = .normal

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
                            if viewModel.authManager.isAuthenticated {
                                Text("Google")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.15)))
                                    .foregroundStyle(.green)
                            }
                            if viewModel.appleCalendarEnabled && viewModel.appleCalendarAccessGranted {
                                Text("Apple")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.15)))
                                    .foregroundStyle(.orange)
                            }
                            if viewModel.appleRemindersEnabled && viewModel.appleRemindersAccessGranted {
                                Text(String(localized: "detail.reminders"))
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.purple.opacity(0.15)))
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    Spacer()

                    HStack(spacing: 8) {
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
                            Image(systemName: "gearshape")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("설정")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Events & Todos list
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        let events = viewModel.eventsForDate(viewModel.selectedDate)
                        ForEach(events) { event in
                            EventRowView(
                                event: event,
                                isCompleted: viewModel.isEventCompleted(event.id),
                                onTap: {
                                    tappedEvent = event
                                    tappedTodo = nil
                                },
                                onToggle: { viewModel.toggleEventCompleted(event.id) }
                            )
                        }

                        let todos = viewModel.todosForDate(viewModel.selectedDate)
                        ForEach(todos) { todo in
                            let cat = viewModel.category(for: todo.categoryID)
                            TodoRowView(
                                todo: todo,
                                category: cat,
                                onTap: {
                                    tappedTodo = todo
                                    tappedEvent = nil
                                },
                                onToggle: { viewModel.toggleTodo(id: todo.id) }
                            )
                        }

                        if events.isEmpty && todos.isEmpty && !showAddForm {
                            Text(String(localized: "detail.no.events"))
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
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
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.08)))
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
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .popover(isPresented: $showCategoryManager) {
            CategoryManagerView(viewModel: viewModel)
        }
    }
}

// MARK: - Category Manager (Popover)

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
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))

                    Toggle(String(localized: "event.toggle.allday"), isOn: $editIsAllDay).font(.system(size: 13))

                    if !editIsAllDay {
                        DatePicker(String(localized: "event.detail.start"), selection: $editStartDate, displayedComponents: [.date, .hourAndMinute]).font(.system(size: 12))
                        DatePicker(String(localized: "event.detail.end"), selection: $editEndDate, displayedComponents: [.date, .hourAndMinute]).font(.system(size: 12))
                    }
                } else {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(event.color).frame(width: 5)
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
                            _ = viewModel.updateCalendarEvent(eventID: event.id, title: t, startDate: editStartDate, endDate: end, isAllDay: editIsAllDay)
                        }
                        onClose()
                    } label: {
                        Text(String(localized: "common.save")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            } else {
                HStack(spacing: 8) {
                    Button { viewModel.toggleEventCompleted(event.id); onClose() } label: {
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
                        _ = viewModel.deleteCalendarEvent(eventID: event.id)
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
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
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

    private var category: TodoCategory {
        viewModel.category(for: isEditing ? editCategoryID : todo.categoryID)
    }

    private var dateText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateStyle = .medium
        return fmt.string(from: todo.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    HStack(spacing: 10) {
                        Circle().fill(category.color).frame(width: 10, height: 10)
                        TextField(String(localized: "event.field.title"), text: $editTitle)
                            .textFieldStyle(.plain).font(.system(size: 15, weight: .medium))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(viewModel.categories) { cat in
                                Button { editCategoryID = cat.id } label: {
                                    Text(cat.name).font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(editCategoryID == cat.id ? cat.color.opacity(0.25) : Color(nsColor: .controlBackgroundColor)))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(editCategoryID == cat.id ? cat.color : Color.clear, lineWidth: 1))
                                        .foregroundStyle(editCategoryID == cat.id ? cat.color : .secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Circle().fill(category.color).frame(width: 10, height: 10)
                        Text(todo.title).font(.system(size: 15, weight: .medium))
                            .strikethrough(todo.isCompleted)
                            .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(dateText).font(.system(size: 13)).foregroundStyle(.secondary)
                        if todo.isRepeating {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)).foregroundStyle(.blue)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "tag").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(category.name).font(.system(size: 13))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(category.color.opacity(0.15)))
                            .foregroundStyle(category.color)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle").font(.system(size: 13))
                            .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        Text(todo.isCompleted ? String(localized: "common.completed") : String(localized: "common.incomplete")).font(.system(size: 13)).foregroundStyle(.secondary)
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
                        if !t.isEmpty { viewModel.updateTodo(id: todo.id, title: t, categoryID: editCategoryID) }
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
                        editTitle = todo.title; editCategoryID = todo.categoryID; isEditing = true
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
        .frame(width: 280, height: 300)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
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
                                .background(RoundedRectangle(cornerRadius: 5).fill(effectiveCategoryID == cat.id ? cat.color.opacity(0.25) : Color(nsColor: .controlBackgroundColor)))
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
                }.buttonStyle(.plain)

                Button { submit() } label: {
                    Text(String(localized: "common.add")).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
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

// MARK: - Event Row

struct EventRowView: View {
    let event: CalendarEvent
    var isCompleted: Bool = false
    var onTap: () -> Void = {}
    var onToggle: (() -> Void)? = nil

    private var timeText: String {
        if event.isAllDay { return String(localized: "event.detail.allday") }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }

    var body: some View {
        HStack(spacing: 0) {
            // 드래그 핸들 — 여기서만 드래그 가능 (ScrollView 제스처 충돌 방지)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.35))
                .frame(width: 22, height: 44)
                .contentShape(Rectangle())
                .draggable("event:\(event.id)")

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                    Text(timeText).font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Spacer()

                Button { onToggle?() } label: {
                    ZStack {
                        Circle()
                            .stroke(isCompleted ? event.color : Color.secondary.opacity(0.4), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isCompleted {
                            Circle().fill(event.color.opacity(0.15)).frame(width: 22, height: 22)
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(event.color)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
    }
}

// MARK: - Todo Row

struct TodoRowView: View {
    let todo: TodoItem
    let category: TodoCategory
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 드래그 핸들 — 여기서만 드래그 가능 (ScrollView 제스처 충돌 방지)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.35))
                .frame(width: 22, height: 44)
                .contentShape(Rectangle())
                .draggable("todo:\(todo.id.uuidString)")

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(todo.source == .appleReminder ? Color.orange : category.color)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(todo.isCompleted)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    HStack(spacing: 4) {
                        if todo.source == .appleReminder {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 9)).foregroundStyle(.orange)
                            Text(String(localized: "detail.reminders")).font(.system(size: 11)).foregroundStyle(.orange)
                        } else {
                            Text(category.name).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if todo.isRepeating {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
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
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
    }
}
