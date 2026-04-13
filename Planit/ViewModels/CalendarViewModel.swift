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

    // MARK: - Init

    private var refreshTimer: Timer?

    private var notificationObserver: Any?

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
        loadCategories()
        loadTodos()
        loadCompletedEvents()
        startPeriodicRefresh()

        // If Google is authenticated, fetch from API; otherwise use EventKit
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
            do {
                let events = try await googleService.fetchEvents(for: month)
                self.calendarEvents = events
            } catch {
                print("[Planit] Google Calendar fetch failed: \(error) — falling back to EventKit")
                fetchEventsFromEventKit(for: month)
            }
        }
    }

    func addEventToGoogleCalendar(title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        Task {
            do {
                let _ = try await googleService.createEvent(title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
                fetchEventsFromGoogle(for: currentMonth)
            } catch {
                print("[Planit] Failed to create Google event: \(error)")
            }
        }
    }

    func updateGoogleEvent(eventID: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        Task {
            do {
                _ = try await googleService.updateEvent(eventID: eventID, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
                fetchEventsFromGoogle(for: currentMonth)
            } catch {
                print("[Planit] Failed to update Google event: \(error)")
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
                print("[Planit] Failed to delete Google event: \(error)")
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
            print("[Planit] Failed to create event: \(error)")
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

    // MARK: - Todo CRUD

    func addTodo(title: String, categoryID: UUID? = nil, date: Date? = nil, isRepeating: Bool = false) {
        let todo = TodoItem(
            title: title,
            categoryID: categoryID ?? defaultCategoryID,
            date: date ?? selectedDate,
            isRepeating: isRepeating
        )
        todos.append(todo)
        saveTodos()
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        saveTodos()
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func updateTodo(id: UUID, title: String, categoryID: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].title = title
        todos[index].categoryID = categoryID
        saveTodos()
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
        } catch { print("[Planit] Failed to save todos: \(error)") }
    }

    func loadTodos() {
        guard fileManager.fileExists(atPath: todosPath.path) else { return }
        do {
            let data = try Data(contentsOf: todosPath)
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch { print("[Planit] Failed to load todos: \(error)") }
    }

    private func saveCompletedEvents() {
        do {
            let data = try JSONEncoder().encode(Array(completedEventIDs))
            try data.write(to: completedEventsPath, options: .atomic)
        } catch { print("[Planit] Failed to save completed events: \(error)") }
    }

    private func loadCompletedEvents() {
        guard fileManager.fileExists(atPath: completedEventsPath.path) else { return }
        do {
            let data = try Data(contentsOf: completedEventsPath)
            let ids = try JSONDecoder().decode([String].self, from: data)
            completedEventIDs = Set(ids)
        } catch { print("[Planit] Failed to load completed events: \(error)") }
    }

    func saveCategories() {
        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: categoriesPath, options: .atomic)
        } catch { print("[Planit] Failed to save categories: \(error)") }
    }

    func loadCategories() {
        if fileManager.fileExists(atPath: categoriesPath.path) {
            do {
                let data = try Data(contentsOf: categoriesPath)
                categories = try JSONDecoder().decode([TodoCategory].self, from: data)
                return
            } catch { print("[Planit] Failed to load categories: \(error)") }
        }
        categories = TodoCategory.defaults
        saveCategories()
    }

    var writableCalendars: [(name: String, identifier: String)] {
        eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { ($0.title, $0.calendarIdentifier) }
    }
}
