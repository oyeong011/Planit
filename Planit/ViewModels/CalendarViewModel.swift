import SwiftUI
import EventKit
import Combine

@MainActor
final class CalendarViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedDate: Date = Date()
    @Published var currentMonth: Date = Date()
    @Published var todos: [TodoItem] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var completedEventIDs: Set<String> = []
    @Published var categories: [TodoCategory] = []
    @Published var isOffline: Bool = false
    @Published var pendingEditsCount: Int = 0

    // MARK: - Services

    let authManager: GoogleAuthManager
    lazy var googleService = GoogleCalendarService(auth: authManager)
    private let eventStore = EKEventStore()
    private let calendar = Calendar.current
    private let fileManager = FileManager.default

    private var appSupportDir: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Planit", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var todosPath: URL { appSupportDir.appendingPathComponent("todos.json") }
    private var completedEventsPath: URL { appSupportDir.appendingPathComponent("completed_events.json") }
    private var categoriesPath: URL { appSupportDir.appendingPathComponent("categories.json") }
    private var eventCachePath: URL { appSupportDir.appendingPathComponent("events_cache.json") }
    private var pendingEditsPath: URL { appSupportDir.appendingPathComponent("pending_edits.json") }

    // MARK: - Init

    private var refreshTimer: Timer?

    private var notificationObserver: Any?

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
        loadCategories()
        loadTodos()
        loadCompletedEvents()
        loadPendingEdits()
        startPeriodicRefresh()

        // Load cached events first (instant display), then try network
        loadCachedEvents()

        if authManager.isAuthenticated {
            fetchEventsFromGoogle(for: currentMonth)
        } else {
            requestCalendarAccess()
            observeCalendarChanges()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Periodic refresh every 15 seconds
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }
    }

    func refreshEvents() {
        if authManager.isAuthenticated {
            fetchEventsFromGoogle(for: currentMonth)
        } else {
            fetchEventsFromEventKit(for: currentMonth)
        }
    }

    // MARK: - Google Calendar API

    func fetchEventsFromGoogle(for month: Date) {
        Task {
            // Try syncing pending edits first
            await syncPendingEdits()

            do {
                let events = try await googleService.fetchEvents(for: month)
                self.calendarEvents = events
                self.isOffline = false
                cacheEvents(events)
            } catch {
                print("[Calen] Google Calendar fetch failed — using cached data")
                self.isOffline = true
                loadCachedEvents()
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
                    color: .blue, isAllDay: isAllDay)
                calendarEvents.append(tempEvent)
                cacheEvents(calendarEvents)
            }
        }
    }

    func updateGoogleEvent(eventID: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        Task {
            do {
                _ = try await googleService.updateEvent(eventID: eventID, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
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

    func deleteGoogleEvent(eventID: String) {
        Task {
            do {
                _ = try await googleService.deleteEvent(eventID: eventID)
                completedEventIDs.remove(eventID)
                saveCompletedEvents()
                fetchEventsFromGoogle(for: currentMonth)
            } catch {
                print("[Calen] Offline — queuing delete event")
                queuePendingEdit(PendingCalendarEdit(
                    action: "delete", eventId: eventID))
                // Optimistic local removal
                calendarEvents.removeAll { $0.id == eventID }
                completedEventIDs.remove(eventID)
                saveCompletedEvents()
                cacheEvents(calendarEvents)
            }
        }
    }

    // MARK: - EventKit (fallback when not using Google API)

    private func observeCalendarChanges() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchEventsFromEventKit(for: self?.currentMonth ?? Date())
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
                calendarName: event.calendar.title
            )
        }
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

    func updateCalendarEvent(eventID: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool) -> Bool {
        if authManager.isAuthenticated {
            updateGoogleEvent(eventID: eventID, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
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

    func deleteCalendarEvent(eventID: String) -> Bool {
        if authManager.isAuthenticated {
            deleteGoogleEvent(eventID: eventID)
            return true
        }
        guard let ekEvent = eventStore.event(withIdentifier: eventID) else { return false }
        do {
            try eventStore.remove(ekEvent, span: .thisEvent)
            completedEventIDs.remove(eventID)
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
        categories.first(where: { $0.id == id }) ?? categories.first ?? TodoCategory(name: "일상", colorHex: "#6699FF")
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

    func monthTitle() -> String { "\(calendar.component(.month, from: currentMonth))월" }
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
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    // MARK: - Filtering

    func eventsForDate(_ date: Date) -> [CalendarEvent] {
        calendarEvents.filter { event in
            let eventStart = calendar.startOfDay(for: event.startDate)
            let target = calendar.startOfDay(for: date)
            if event.isAllDay {
                // Google all-day events use exclusive end date
                let eventEnd = calendar.startOfDay(for: event.endDate)
                return target >= eventStart && target < eventEnd
            } else {
                let eventEnd = calendar.startOfDay(for: event.endDate)
                return target >= eventStart && target <= eventEnd
            }
        }
    }

    func todosForDate(_ date: Date) -> [TodoItem] {
        todos.filter { calendar.isDate($0.date, inSameDayAs: date) }
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
                if let event = try? await googleService.createEvent(title: title, startDate: startOfDay, endDate: endOfDay, isAllDay: true) {
                    if let idx = self.todos.firstIndex(where: { $0.id == todo.id }) {
                        self.todos[idx].googleEventId = event.id
                        self.saveTodos()
                        self.refreshEvents()
                    }
                }
            }
        }
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        saveTodos()

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
        if let todo = todos.first(where: { $0.id == id }),
           let eventId = todo.googleEventId,
           authManager.isAuthenticated {
            Task {
                _ = try? await googleService.deleteEvent(eventID: eventId)
                self.refreshEvents()
            }
        }
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func updateTodo(id: UUID, title: String, categoryID: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].title = title
        todos[index].categoryID = categoryID
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
    }

    func updateCategory(id: UUID, name: String, colorHex: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
        categories[index].colorHex = colorHex
        saveCategories()
    }

    // MARK: - Event Completion

    func isEventCompleted(_ eventID: String) -> Bool {
        completedEventIDs.contains(eventID)
    }

    func toggleEventCompleted(_ eventID: String) {
        if completedEventIDs.contains(eventID) {
            completedEventIDs.remove(eventID)
        } else {
            completedEventIDs.insert(eventID)
        }
        saveCompletedEvents()
    }

    // MARK: - Persistence

    func saveTodos() {
        do {
            let data = try JSONEncoder().encode(todos)
            try data.write(to: todosPath, options: .atomic)
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

        var remaining: [PendingCalendarEdit] = []

        for edit in pendingEdits {
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

        pendingEdits = remaining
        pendingEditsCount = remaining.count
        savePendingEdits()
    }
}
