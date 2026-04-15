import SwiftUI
import EventKit
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedDate: Date = Date() {
        didSet {
            if appleRemindersEnabled {
                fetchAppleReminders(for: selectedDate)
            }
        }
    }
    @Published var currentMonth: Date = Date()
    @Published var todos: [TodoItem] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var completedEventIDs: Set<String> = []
    @Published var categories: [TodoCategory] = []
    @Published var eventCategoryMappings: [String: EventCategoryMapping] = [:]  // eventID → mapping
    @Published var isOffline: Bool = false
    @Published var pendingEditsCount: Int = 0
    @Published var appleCalendarEnabled: Bool = UserDefaults.standard.bool(forKey: "planit.appleCalendarEnabled") {
        didSet {
            UserDefaults.standard.set(appleCalendarEnabled, forKey: "planit.appleCalendarEnabled")
            if appleCalendarEnabled {
                requestAppleCalendarAccess()
            } else {
                // Google 인증 상태면 Google 이벤트만 다시 불러오기
                if authManager.isAuthenticated {
                    fetchEventsFromGoogle(for: currentMonth)
                }
            }
        }
    }
    @Published var appleCalendarAccessGranted: Bool = false
    @Published var appleRemindersEnabled: Bool = UserDefaults.standard.bool(forKey: "planit.appleRemindersEnabled") {
        didSet {
            UserDefaults.standard.set(appleRemindersEnabled, forKey: "planit.appleRemindersEnabled")
            if appleRemindersEnabled {
                requestAppleRemindersAccess()
            } else {
                appleReminders = []
            }
        }
    }
    @Published var appleRemindersAccessGranted: Bool = false
    @Published var appleReminders: [TodoItem] = []

    // MARK: - Services

    let authManager: GoogleAuthManager
    lazy var googleService = GoogleCalendarService(auth: authManager)
    weak var goalService: GoalService?
    private let eventStore = EKEventStore()
    private let calendar = Calendar.current
    private let fileManager = FileManager.default

    /// Apple Reminders 전용 카테고리 ID (고정)
    static let remindersCategoryID = UUID(uuidString: "00000000-0000-0000-0000-AE1D0DE50001")!

    private var appSupportDir: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Planit", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        return dir
    }

    private var todosPath: URL { appSupportDir.appendingPathComponent("todos.json") }
    private var completedEventsPath: URL { appSupportDir.appendingPathComponent("completed_events.json") }
    private var categoriesPath: URL { appSupportDir.appendingPathComponent("categories.json") }
    private var eventCachePath: URL { appSupportDir.appendingPathComponent("events_cache.json") }
    private var pendingEditsPath: URL { appSupportDir.appendingPathComponent("pending_edits.json") }
    private var eventCategoryMappingsPath: URL { appSupportDir.appendingPathComponent("event_category_mappings.json") }

    // MARK: - Init

    private var refreshTimer: Timer?
    private var dateChangeTimer: Timer?

    private var notificationObserver: Any?
    private var authCancellable: AnyCancellable?
    /// syncPendingEdits 재진입 방지 플래그
    private var isSyncingPendingEdits = false

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
        loadCategories()
        loadTodos()
        loadCompletedEvents()
        loadPendingEdits()
        loadEventCategoryMappings()
        startPeriodicRefresh()

        // 자정 롤오버: 미완료 Todo를 오늘로 자동 이동
        Task { @MainActor in
            MidnightRolloverService.shared.performIfNeeded(viewModel: self)
            MidnightRolloverService.shared.scheduleMidnightTrigger()
        }

        // 날짜 변경 감지 (앱이 켜진 상태로 자정 넘길 때)
        observeDateChange()

        // 로그인/로그아웃 시 캘린더 목록 캐시 초기화
        authCancellable = authManager.$isAuthenticated.dropFirst().sink { [weak self] authenticated in
            guard let self else { return }
            if !authenticated {
                // 로그아웃: 캐시 클리어
                self.googleService.clearCache()
            }
        }

        // Load cached events first (instant display), then try network
        loadCachedEvents()

        if authManager.isAuthenticated {
            fetchEventsFromGoogle(for: currentMonth)
            // Apple Calendar도 활성화되어 있으면 병합
            if appleCalendarEnabled {
                requestAppleCalendarAccess()
            }
        } else {
            requestCalendarAccess()
            observeCalendarChanges()
        }

        // Apple Reminders 활성화되어 있으면 접근 요청
        if appleRemindersEnabled {
            requestAppleRemindersAccess()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
        dateChangeTimer?.invalidate()
        dateChangeTimer = nil
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = reminderObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Periodic refresh every 60 seconds
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }
    }

    /// 자정 넘어갈 때 감지해서 롤오버 실행
    private func observeDateChange() {
        var lastDay = Calendar.current.startOfDay(for: Date())
        dateChangeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let today = Calendar.current.startOfDay(for: Date())
            if today > lastDay {
                lastDay = today
                Task { @MainActor in
                    MidnightRolloverService.shared.performIfNeeded(viewModel: self)
                    self.currentMonth = today
                    self.selectedDate = today
                    self.refreshEvents()
                }
            }
        }
    }

    func refreshEvents() {
        if authManager.isAuthenticated {
            fetchEventsFromGoogle(for: currentMonth)
        } else {
            fetchEventsFromEventKit(for: currentMonth)
        }
        // Reminders도 갱신
        if appleRemindersEnabled {
            fetchAppleReminders(for: selectedDate)
        }
    }

    // MARK: - Apple Calendar (EventKit 병합 모드)

    /// Apple Calendar 접근 권한 요청 (Google 인증 상태에서 병합용)
    func requestAppleCalendarAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                Task { @MainActor in
                    self?.appleCalendarAccessGranted = granted && error == nil
                    if granted {
                        self?.observeCalendarChanges()
                        // 현재 Google 이벤트에 Apple Calendar 이벤트 병합
                        self?.mergeAppleCalendarEvents(for: self?.currentMonth ?? Date())
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                Task { @MainActor in
                    self?.appleCalendarAccessGranted = granted && error == nil
                    if granted {
                        self?.observeCalendarChanges()
                        self?.mergeAppleCalendarEvents(for: self?.currentMonth ?? Date())
                    }
                }
            }
        }
    }

    /// EventKit에서 이벤트를 가져와 로컬 Apple Calendar 이벤트 목록 반환
    func fetchLocalCalendarEvents(for month: Date) -> [CalendarEvent] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let predicate = eventStore.predicateForEvents(
            withStart: monthInterval.start,
            end: monthInterval.end,
            calendars: nil
        )
        let ekEvents = eventStore.events(matching: predicate)
        return ekEvents.map { event in
            let cgColor = event.calendar.cgColor ?? CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
            return CalendarEvent(
                id: "apple-\(event.eventIdentifier ?? UUID().uuidString)",
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                color: Color(cgColor: cgColor),
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                calendarID: "apple:\(event.calendar.calendarIdentifier)",
                source: .apple
            )
        }
    }

    /// Google 이벤트에 Apple Calendar 이벤트를 병합
    func mergeAppleCalendarEvents(for month: Date) {
        guard appleCalendarEnabled, appleCalendarAccessGranted else { return }
        let appleEvents = fetchLocalCalendarEvents(for: month)
        // 기존 Apple 이벤트 제거 후 다시 추가 (중복 방지)
        calendarEvents.removeAll { $0.source == .apple }
        calendarEvents.append(contentsOf: appleEvents)
        applyEventCategoryMappings()
    }

    // MARK: - Apple Reminders (EventKit)

    /// Apple Reminders 접근 권한 요청
    func requestAppleRemindersAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { [weak self] granted, error in
                Task { @MainActor in
                    self?.appleRemindersAccessGranted = granted && error == nil
                    if granted {
                        self?.fetchAppleReminders(for: self?.selectedDate ?? Date())
                        self?.observeReminderChanges()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
                Task { @MainActor in
                    self?.appleRemindersAccessGranted = granted && error == nil
                    if granted {
                        self?.fetchAppleReminders(for: self?.selectedDate ?? Date())
                        self?.observeReminderChanges()
                    }
                }
            }
        }
    }

    private var reminderObserver: Any?

    private func observeReminderChanges() {
        // EKEventStoreChanged는 reminders 변경도 포함
        guard reminderObserver == nil else { return }
        reminderObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.appleRemindersEnabled else { return }
                self.fetchAppleReminders(for: self.selectedDate)
            }
        }
    }

    /// Reminders 카테고리가 없으면 생성
    func ensureRemindersCategory() {
        guard !categories.contains(where: { $0.id == Self.remindersCategoryID }) else { return }
        let cat = TodoCategory(id: Self.remindersCategoryID, name: "미리알림", colorHex: "#FF9500")
        categories.append(cat)
        saveCategories()
    }

    /// 특정 날짜의 Apple Reminders를 가져와 appleReminders에 저장
    func fetchAppleReminders(for date: Date) {
        guard appleRemindersEnabled, appleRemindersAccessGranted else {
            appleReminders = []
            return
        }
        ensureRemindersCategory()

        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        // 미완료 + 완료된 미리알림 모두 가져오기 (해당 날짜)
        let predicate = eventStore.predicateForReminders(in: nil)

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            Task { @MainActor in
                guard let self = self, let reminders = reminders else { return }

                let targetDay = self.calendar.startOfDay(for: date)
                let items: [TodoItem] = reminders.compactMap { reminder in
                    // due date가 있는 경우 해당 날짜만 표시
                    if let dueDateComponents = reminder.dueDateComponents,
                       let dueDate = Calendar.current.date(from: dueDateComponents) {
                        let reminderDay = self.calendar.startOfDay(for: dueDate)
                        guard reminderDay == targetDay else { return nil }
                    } else {
                        // due date가 없는 미리알림은 오늘만 표시
                        guard self.calendar.isDateInToday(date) else { return nil }
                    }

                    let dueDate: Date
                    if let dc = reminder.dueDateComponents,
                       let d = Calendar.current.date(from: dc) {
                        dueDate = d
                    } else {
                        dueDate = date
                    }

                    return TodoItem(
                        title: reminder.title ?? "(제목 없음)",
                        categoryID: Self.remindersCategoryID,
                        isCompleted: reminder.isCompleted,
                        date: dueDate,
                        source: .appleReminder,
                        appleReminderIdentifier: reminder.calendarItemIdentifier
                    )
                }

                self.appleReminders = items
            }
        }
    }

    /// Apple Reminder의 완료 상태를 토글
    func toggleAppleReminder(identifier: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        reminder.isCompleted.toggle()
        do {
            try eventStore.save(reminder, commit: true)
            // UI 업데이트
            if let idx = appleReminders.firstIndex(where: { $0.appleReminderIdentifier == identifier }) {
                appleReminders[idx].isCompleted = reminder.isCompleted
            }
        } catch {
            print("[Calen] Failed to toggle Apple Reminder: \(error)")
        }
    }

    /// 특정 날짜의 Apple Reminders 반환 (이미 fetch된 것에서 필터)
    func appleRemindersForDate(_ date: Date) -> [TodoItem] {
        appleReminders.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Google Calendar API

    func fetchEventsFromGoogle(for month: Date) {
        Task {
            // Try syncing pending edits first
            await syncPendingEdits()

            do {
                var events = try await googleService.fetchEvents(for: month)
                // Google 이벤트에 source 태그 설정
                for i in events.indices {
                    events[i].source = .google
                }
                self.calendarEvents = events
                self.isOffline = false
                cacheEvents(events)
                // Apple Calendar 이벤트 병합
                mergeAppleCalendarEvents(for: month)
                applyEventCategoryMappings()
            } catch {
                print("[Calen] Google Calendar fetch failed — using cached data")
                self.isOffline = true
                loadCachedEvents()
                // 오프라인에서도 Apple Calendar 병합
                mergeAppleCalendarEvents(for: month)
                applyEventCategoryMappings()
            }
        }
    }

    func addEventToGoogleCalendar(title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        Task {
            do {
                let _ = try await googleService.createEvent(title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
                fetchEventsFromGoogle(for: currentMonth)
            } catch {
                print("[Calen] Offline — queuing create event")
                queuePendingEdit(PendingCalendarEdit(
                    action: "create", title: title, startDate: startDate,
                    endDate: endDate, isAllDay: isAllDay))
                // Optimistic local update
                let tempEvent = CalendarEvent(
                    id: "pending-\(UUID().uuidString)", title: title,
                    startDate: startDate, endDate: endDate,
                    color: .blue, isAllDay: isAllDay,
                    calendarName: "Google", calendarID: "google:primary", source: .google)
                calendarEvents.append(tempEvent)
                applyEventCategoryMappings()
                cacheEvents(calendarEvents)
            }
        }
    }

    func updateGoogleEvent(eventID: String, calendarID: String = "google:primary", title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        Task {
            do {
                _ = try await googleService.updateEvent(eventID: eventID, calendarID: calendarID, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
                fetchEventsFromGoogle(for: currentMonth)
            } catch {
                print("[Calen] Offline — queuing update event")
                queuePendingEdit(PendingCalendarEdit(
                    action: "update", title: title, startDate: startDate,
                    endDate: endDate, isAllDay: isAllDay, eventId: eventID))
                // Optimistic local update
                if let idx = calendarEvents.firstIndex(where: { $0.id == eventID }) {
                    calendarEvents[idx].title = title
                    calendarEvents[idx].startDate = startDate
                    calendarEvents[idx].endDate = endDate
                    calendarEvents[idx].isAllDay = isAllDay
                    cacheEvents(calendarEvents)
                }
            }
        }
    }

    func deleteGoogleEvent(eventID: String, calendarID: String = "google:primary") {
        Task {
            do {
                _ = try await googleService.deleteEvent(eventID: eventID, calendarID: calendarID)
                completedEventIDs.remove(eventID)
                goalService?.removeCompletion(eventId: eventID)
                saveCompletedEvents()
                fetchEventsFromGoogle(for: currentMonth)
            } catch {
                print("[Calen] Offline — queuing delete event")
                queuePendingEdit(PendingCalendarEdit(
                    action: "delete", eventId: eventID))
                // Optimistic local removal
                calendarEvents.removeAll { $0.id == eventID }
                completedEventIDs.remove(eventID)
                goalService?.removeCompletion(eventId: eventID)
                saveCompletedEvents()
                cacheEvents(calendarEvents)
            }
        }
    }

    // MARK: - EventKit (fallback when not using Google API)

    private func observeCalendarChanges() {
        // 기존 observer 제거 후 재등록 — 중복 리스너 누수 방지
        if let existing = notificationObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Google 인증 상태일 때 EventKit만 불러오면 Google 이벤트가 유실되므로
                // refreshEvents()를 통해 적절한 소스에서 로드
                if self.authManager.isAuthenticated {
                    self.refreshEvents()
                } else {
                    self.fetchEventsFromEventKit(for: self.currentMonth)
                }
            }
        }
    }

    func requestCalendarAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                guard granted, error == nil else { return }
                Task { @MainActor in
                    self?.fetchEventsFromEventKit(for: self?.currentMonth ?? Date())
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                guard granted, error == nil else { return }
                Task { @MainActor in
                    self?.fetchEventsFromEventKit(for: self?.currentMonth ?? Date())
                }
            }
        }
    }

    func fetchEventsFromEventKit(for month: Date) {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return }
        let predicate = eventStore.predicateForEvents(
            withStart: monthInterval.start,
            end: monthInterval.end,
            calendars: nil
        )
        let ekEvents = eventStore.events(matching: predicate)
        calendarEvents = ekEvents.map { event in
            let cgColor = event.calendar.cgColor ?? CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
            return CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                color: Color(cgColor: cgColor),
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                calendarID: "apple:\(event.calendar.calendarIdentifier)",
                source: .local
            )
        }
        applyEventCategoryMappings()
    }

    // EventKit write methods (fallback)
    func addEventToCalendar(title: String, startDate: Date, endDate: Date, isAllDay: Bool) -> Bool {
        if authManager.isAuthenticated {
            addEventToGoogleCalendar(title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
            return true
        }
        guard let cal = writableCalendar else { return false }
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = title
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.isAllDay = isAllDay
        ekEvent.calendar = cal
        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            fetchEventsFromEventKit(for: currentMonth)
            return true
        } catch {
            print("[Calen] Failed to create event: \(error)")
            return false
        }
    }

    func updateCalendarEvent(eventID: String, calendarID: String = "google:primary", title: String, startDate: Date, endDate: Date, isAllDay: Bool) -> Bool {
        if authManager.isAuthenticated {
            updateGoogleEvent(eventID: eventID, calendarID: calendarID, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
            return true
        }
        guard let ekEvent = eventStore.event(withIdentifier: eventID) else { return false }
        ekEvent.title = title
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.isAllDay = isAllDay
        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            fetchEventsFromEventKit(for: currentMonth)
            return true
        } catch { return false }
    }

    func deleteCalendarEvent(eventID: String, calendarID: String = "google:primary") -> Bool {
        if authManager.isAuthenticated {
            deleteGoogleEvent(eventID: eventID, calendarID: calendarID)
            return true
        }
        guard let ekEvent = eventStore.event(withIdentifier: eventID) else { return false }
        do {
            try eventStore.remove(ekEvent, span: .thisEvent)
            completedEventIDs.remove(eventID)
            goalService?.removeCompletion(eventId: eventID)
            saveCompletedEvents()
            fetchEventsFromEventKit(for: currentMonth)
            return true
        } catch { return false }
    }

    private var writableCalendar: EKCalendar? {
        if let google = eventStore.calendars(for: .event).first(where: {
            $0.source.sourceType == .calDAV && $0.allowsContentModifications
        }) { return google }
        return eventStore.defaultCalendarForNewEvents
    }

    // MARK: - Category Helpers

    func category(for id: UUID) -> TodoCategory {
        categories.first(where: { $0.id == id }) ?? categories.first ?? TodoCategory(name: String(localized: "viewmodel.default.category"), colorHex: "#6699FF")
    }

    var defaultCategoryID: UUID {
        categories.first?.id ?? UUID()
    }

    // MARK: - Calendar Grid

    func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthRange = calendar.range(of: .day, in: .month, for: currentMonth) else {
            return Array(repeating: nil, count: 42)
        }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingNils = firstWeekday - 1
        let totalDays = monthRange.count

        var slots: [Date?] = Array(repeating: nil, count: leadingNils)
        for day in 0..<totalDays {
            if let date = calendar.date(byAdding: .day, value: day, to: firstDay) {
                slots.append(date)
            }
        }
        while slots.count < 42 { slots.append(nil) }
        return slots
    }

    func monthTitle() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMMM")
        return fmt.string(from: currentMonth)
    }
    func yearTitle() -> String { "\(calendar.component(.year, from: currentMonth))" }

    func previousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = prev
            refreshEvents()
        }
    }

    func nextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = next
            refreshEvents()
        }
    }

    func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
    func isSunday(_ date: Date) -> Bool { calendar.component(.weekday, from: date) == 1 }
    func isSaturday(_ date: Date) -> Bool { calendar.component(.weekday, from: date) == 7 }
    func isCurrentMonth(_ date: Date) -> Bool { calendar.isDate(date, equalTo: currentMonth, toGranularity: .month) }

    func daysSinceToday(_ date: Date) -> Int {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMd EEEE")
        return formatter.string(from: date)
    }

    // MARK: - Filtering

    func eventsForDate(_ date: Date) -> [CalendarEvent] {
        // 할 일로 등록된 Google 이벤트는 ID로 제외 (오탐 없는 정확한 방식)
        let todoEventIds = Set(todos.compactMap { $0.googleEventId })

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        return calendarEvents.filter { event in
            guard !todoEventIds.contains(event.id) else { return false }
            if event.isAllDay {
                // All-day: [start, end) 반개구간 — Google은 end가 exclusive
                let eventStart = calendar.startOfDay(for: event.startDate)
                let eventEnd = calendar.startOfDay(for: event.endDate)
                return dayStart >= eventStart && dayStart < eventEnd
            } else {
                // Timed: 구간 겹침 [start, end) vs [dayStart, dayEnd)
                return event.startDate < dayEnd && event.endDate > dayStart
            }
        }
    }

    func todosForDate(_ date: Date) -> [TodoItem] {
        let localTodos = todos.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let reminders = appleRemindersForDate(date)
        return localTodos + reminders
    }

    // MARK: - Todo Bulk Sync

    /// Sync all existing todos that don't have a googleEventId to Google Calendar
    func syncAllTodosToGoogle() async -> Int {
        guard authManager.isAuthenticated else { return 0 }
        var synced = 0
        for i in todos.indices {
            guard todos[i].googleEventId == nil else { continue }
            let todo = todos[i]
            let startOfDay = calendar.startOfDay(for: todo.date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let prefix = todo.isCompleted ? "✅ " : ""
            if let event = try? await googleService.createEvent(
                title: "\(prefix)\(todo.title)", startDate: startOfDay,
                endDate: endOfDay, isAllDay: true) {
                todos[i].googleEventId = event.id
                synced += 1
            }
        }
        if synced > 0 {
            saveTodos()
            refreshEvents()
        }
        return synced
    }

    // MARK: - Todo CRUD

    func addTodo(title: String, categoryID: UUID? = nil, date: Date? = nil, isRepeating: Bool = false) {
        var todo = TodoItem(
            title: title,
            categoryID: categoryID ?? defaultCategoryID,
            date: date ?? selectedDate,
            isRepeating: isRepeating
        )
        todos.append(todo)
        saveTodos()

        // Sync to Google Calendar
        if authManager.isAuthenticated {
            Task {
                let startOfDay = Calendar.current.startOfDay(for: todo.date)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                do {
                    let event = try await googleService.createEvent(title: title, startDate: startOfDay, endDate: endOfDay, isAllDay: true)
                    if let event, let idx = self.todos.firstIndex(where: { $0.id == todo.id }) {
                        self.todos[idx].googleEventId = event.id
                        self.saveTodos()
                    }
                } catch {
                    print("[Calen] Todo Google sync failed: \(error)")
                }
                self.refreshEvents()
            }
        }
    }

    func toggleTodo(id: UUID) {
        // Apple Reminder인 경우 EventKit으로 토글
        if let reminderItem = appleReminders.first(where: { $0.id == id }),
           let identifier = reminderItem.appleReminderIdentifier {
            toggleAppleReminder(identifier: identifier)
            return
        }

        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        saveTodos()

        // 달성률 반영 — 항상 UUID 기반 고정 키 사용 (googleEventId는 나중에 할당될 수 있어 키가 불안정)
        let completionKey = "todo:\(todos[index].id.uuidString)"
        if todos[index].isCompleted {
            goalService?.markCompletion(eventId: completionKey, goalId: nil, status: .done, plannedMinutes: 30)
        } else {
            goalService?.removeCompletion(eventId: completionKey)
        }

        if authManager.isAuthenticated, let eventId = todos[index].googleEventId {
            let todo = todos[index]
            let prefix = todo.isCompleted ? "✅ " : ""
            let cleanTitle = todo.title.replacingOccurrences(of: "✅ ", with: "")
            Task {
                let startOfDay = Calendar.current.startOfDay(for: todo.date)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                _ = try? await googleService.updateEvent(eventID: eventId, title: "\(prefix)\(cleanTitle)", startDate: startOfDay, endDate: endOfDay, isAllDay: true)
                self.refreshEvents()
            }
        }
    }

    func deleteTodo(id: UUID) {
        if let todo = todos.first(where: { $0.id == id }) {
            // 완료 기록 정리
            goalService?.removeCompletion(eventId: "todo:\(id.uuidString)")
            if let eventId = todo.googleEventId, authManager.isAuthenticated {
                Task {
                    _ = try? await googleService.deleteEvent(eventID: eventId)
                    self.refreshEvents()
                }
            }
        }
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func updateTodo(id: UUID, title: String, categoryID: UUID, date: Date? = nil) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].title = title
        todos[index].categoryID = categoryID
        if let newDate = date { todos[index].date = newDate }
        saveTodos()

        if authManager.isAuthenticated, let eventId = todos[index].googleEventId {
            let todo = todos[index]
            let prefix = todo.isCompleted ? "✅ " : ""
            Task {
                let startOfDay = Calendar.current.startOfDay(for: todo.date)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                _ = try? await googleService.updateEvent(eventID: eventId, title: "\(prefix)\(title)", startDate: startOfDay, endDate: endOfDay, isAllDay: true)
                self.refreshEvents()
            }
        }
    }

    // MARK: - Drag & Drop Move

    func moveTodo(id: UUID, toDate: Date) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].date = Calendar.current.startOfDay(for: toDate)
        saveTodos()

        if authManager.isAuthenticated, let eventId = todos[idx].googleEventId {
            let todo = todos[idx]
            let prefix = todo.isCompleted ? "✅ " : ""
            let todoPrefix = "✅ "
            let clean = todo.title.hasPrefix(todoPrefix) ? String(todo.title.dropFirst(todoPrefix.count)) : todo.title
            Task {
                let start = Calendar.current.startOfDay(for: toDate)
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                _ = try? await googleService.updateEvent(eventID: eventId, title: "\(prefix)\(clean)", startDate: start, endDate: end, isAllDay: true)
                self.refreshEvents()
            }
        }
    }

    func moveCalendarEvent(id: String, toDate: Date) {
        guard let event = calendarEvents.first(where: { $0.id == id }) else { return }
        let cal = Calendar.current
        let srcDay = cal.startOfDay(for: event.startDate)
        let dstDay = cal.startOfDay(for: toDate)
        let delta = dstDay.timeIntervalSince(srcDay)
        let newStart = event.startDate.addingTimeInterval(delta)
        let newEnd = event.endDate.addingTimeInterval(delta)

        switch event.source {
        case .google:
            updateGoogleEvent(eventID: id, calendarID: event.calendarID, title: event.title, startDate: newStart, endDate: newEnd, isAllDay: event.isAllDay)
        case .apple, .local:
            _ = updateCalendarEvent(eventID: id, title: event.title, startDate: newStart, endDate: newEnd, isAllDay: event.isAllDay)
        }
    }

    // MARK: - Category CRUD

    func addCategory(name: String, colorHex: String) {
        let cat = TodoCategory(name: name, colorHex: colorHex)
        categories.append(cat)
        saveCategories()
    }

    func deleteCategory(id: UUID) {
        if let fallback = categories.first(where: { $0.id != id }) {
            for i in todos.indices where todos[i].categoryID == id {
                todos[i].categoryID = fallback.id
            }
            saveTodos()
        }
        categories.removeAll { $0.id == id }
        saveCategories()
        // 삭제된 카테고리를 참조하는 캘린더 매핑 제거
        eventCategoryMappings = eventCategoryMappings.filter { $0.value.categoryID != id }
        saveEventCategoryMappings()
        applyEventCategoryMappings()
    }

    func updateCategory(id: UUID, name: String, colorHex: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
        categories[index].colorHex = colorHex
        saveCategories()
    }

    // MARK: - Event Category Mappings (이벤트별 독립 매핑)

    /// 이벤트의 카테고리를 반환 (매핑 없으면 nil)
    func categoryForEvent(_ event: CalendarEvent) -> TodoCategory? {
        guard let catID = event.categoryID else { return nil }
        return categories.first { $0.id == catID }
    }

    /// 이벤트에 카테고리 매핑 설정 (categoryID == nil이면 매핑 제거)
    func setEventCategory(eventID: String, eventTitle: String, categoryID: UUID?) {
        if let catID = categoryID {
            eventCategoryMappings[eventID] = EventCategoryMapping(
                eventID: eventID,
                eventTitle: eventTitle,
                categoryID: catID
            )
        } else {
            eventCategoryMappings.removeValue(forKey: eventID)
        }
        saveEventCategoryMappings()
        applyEventCategoryMappings()
    }

    /// 현재 로드된 이벤트에 매핑 적용 (존재하지 않는 카테고리는 무시)
    func applyEventCategoryMappings() {
        let validCategoryIDs = Set(categories.map { $0.id })
        for i in calendarEvents.indices {
            let eid = calendarEvents[i].id
            if let mapping = eventCategoryMappings[eid],
               validCategoryIDs.contains(mapping.categoryID) {
                calendarEvents[i].categoryID = mapping.categoryID
            } else {
                calendarEvents[i].categoryID = nil
            }
        }
    }

    private func saveEventCategoryMappings() {
        let store = EventCategoryMappingsStore(
            version: 1,
            mappings: Array(eventCategoryMappings.values)
        )
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: eventCategoryMappingsPath, options: .atomic)
        } catch { print("[Calen] Failed to save event category mappings: \(error)") }
    }

    func loadEventCategoryMappings() {
        guard let data = try? Data(contentsOf: eventCategoryMappingsPath),
              let store = try? JSONDecoder().decode(EventCategoryMappingsStore.self, from: data) else { return }
        eventCategoryMappings = store.mappings.reduce(into: [:]) { $0[$1.eventID] = $1 }
    }

    // MARK: - Event Completion

    func isEventCompleted(_ eventID: String) -> Bool {
        completedEventIDs.contains(eventID)
    }

    func toggleEventCompleted(_ eventID: String) {
        if completedEventIDs.contains(eventID) {
            completedEventIDs.remove(eventID)
            goalService?.removeCompletion(eventId: eventID)
        } else {
            completedEventIDs.insert(eventID)
            goalService?.markCompletion(eventId: eventID, goalId: nil, status: .done, plannedMinutes: 60)
        }
        saveCompletedEvents()
    }

    // MARK: - Persistence

    func saveTodos() {
        do {
            let data = try JSONEncoder().encode(todos)
            try data.write(to: todosPath, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: todosPath.path)
        } catch { print("[Calen] Failed to save todos: \(error)") }
    }

    func loadTodos() {
        guard fileManager.fileExists(atPath: todosPath.path) else { return }
        do {
            let data = try Data(contentsOf: todosPath)
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch { print("[Calen] Failed to load todos: \(error)") }
    }

    private func saveCompletedEvents() {
        do {
            let data = try JSONEncoder().encode(Array(completedEventIDs))
            try data.write(to: completedEventsPath, options: .atomic)
        } catch { print("[Calen] Failed to save completed events: \(error)") }
    }

    private func loadCompletedEvents() {
        guard fileManager.fileExists(atPath: completedEventsPath.path) else { return }
        do {
            let data = try Data(contentsOf: completedEventsPath)
            let ids = try JSONDecoder().decode([String].self, from: data)
            completedEventIDs = Set(ids)
        } catch { print("[Calen] Failed to load completed events: \(error)") }
    }

    func saveCategories() {
        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: categoriesPath, options: .atomic)
        } catch { print("[Calen] Failed to save categories: \(error)") }
    }

    func loadCategories() {
        if fileManager.fileExists(atPath: categoriesPath.path) {
            do {
                let data = try Data(contentsOf: categoriesPath)
                categories = try JSONDecoder().decode([TodoCategory].self, from: data)
                return
            } catch { print("[Calen] Failed to load categories: \(error)") }
        }
        categories = TodoCategory.defaults
        saveCategories()
    }

    var writableCalendars: [(name: String, identifier: String)] {
        eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { ($0.title, $0.calendarIdentifier) }
    }

    // MARK: - Event Cache (Offline Support)

    private func cacheEvents(_ events: [CalendarEvent]) {
        let cached = events.map { CachedCalendarEvent.from($0) }
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: eventCachePath, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: eventCachePath.path)
        } catch { print("[Calen] Failed to cache events") }
    }

    private func loadCachedEvents() {
        guard fileManager.fileExists(atPath: eventCachePath.path) else { return }
        do {
            let data = try Data(contentsOf: eventCachePath)
            let cached = try JSONDecoder().decode([CachedCalendarEvent].self, from: data)
            // Only use cache if we don't already have live data
            if calendarEvents.isEmpty {
                calendarEvents = cached.map { $0.toCalendarEvent() }
                applyEventCategoryMappings()
            }
        } catch { print("[Calen] Failed to load cached events") }
    }

    // MARK: - Pending Edits Queue (Offline Sync)

    private var pendingEdits: [PendingCalendarEdit] = []

    private func queuePendingEdit(_ edit: PendingCalendarEdit) {
        pendingEdits.append(edit)
        pendingEditsCount = pendingEdits.count
        savePendingEdits()
    }

    private func savePendingEdits() {
        do {
            let data = try JSONEncoder().encode(pendingEdits)
            try data.write(to: pendingEditsPath, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pendingEditsPath.path)
        } catch { print("[Calen] Failed to save pending edits") }
    }

    private func loadPendingEdits() {
        guard fileManager.fileExists(atPath: pendingEditsPath.path) else { return }
        do {
            let data = try Data(contentsOf: pendingEditsPath)
            pendingEdits = try JSONDecoder().decode([PendingCalendarEdit].self, from: data)
            pendingEditsCount = pendingEdits.count
        } catch { print("[Calen] Failed to load pending edits") }
    }

    /// Sync all pending offline edits to Google Calendar
    func syncPendingEdits() async {
        guard !pendingEdits.isEmpty, authManager.isAuthenticated else { return }
        guard !isSyncingPendingEdits else { return }  // 재진입 방지
        isSyncingPendingEdits = true
        defer { isSyncingPendingEdits = false }

        // 처리할 배치를 스냅샷하고 pendingEdits를 즉시 비움
        // → await 구간에 새로 추가된 편집이 remaining 덮어쓰기로 유실되는 문제 방지
        let batch = pendingEdits
        pendingEdits = []
        savePendingEdits()

        var remaining: [PendingCalendarEdit] = []

        for edit in batch {
            do {
                switch edit.action {
                case "create":
                    _ = try await googleService.createEvent(
                        title: edit.title, startDate: edit.startDate,
                        endDate: edit.endDate, isAllDay: edit.isAllDay)
                case "update":
                    if let eventId = edit.eventId {
                        _ = try await googleService.updateEvent(
                            eventID: eventId, title: edit.title,
                            startDate: edit.startDate, endDate: edit.endDate,
                            isAllDay: edit.isAllDay)
                    }
                case "delete":
                    if let eventId = edit.eventId {
                        _ = try await googleService.deleteEvent(eventID: eventId)
                    }
                default: break
                }
            } catch {
                // Keep failed edits for next sync attempt
                remaining.append(edit)
            }
        }

        // 실패한 편집 + sync 도중 새로 추가된 편집을 합산
        pendingEdits = remaining + pendingEdits
        pendingEditsCount = pendingEdits.count
        savePendingEdits()
    }
}
