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

    // MARK: - Private

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

    init() {
        loadCategories()
        loadTodos()
        loadCompletedEvents()
        requestCalendarAccess()
        observeCalendarChanges()
        startPeriodicRefresh()
    }

    /// Listen for EventKit changes (external edits from Google Calendar, MCP, etc.)
    private func observeCalendarChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchEvents(for: self?.currentMonth ?? Date())
            }
        }
    }

    /// Periodic refresh every 30 seconds to catch external changes
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchEvents(for: self?.currentMonth ?? Date())
            }
        }
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

    func monthTitle() -> String {
        "\(calendar.component(.month, from: currentMonth))월"
    }

    func yearTitle() -> String {
        "\(calendar.component(.year, from: currentMonth))"
    }

    func previousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = prev
            fetchEvents(for: currentMonth)
        }
    }

    func nextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = next
            fetchEvents(for: currentMonth)
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
            let eventEnd = calendar.startOfDay(for: event.endDate)
            let target = calendar.startOfDay(for: date)
            return target >= eventStart && target <= eventEnd
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
        // Move todos in this category to first available category
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
        } catch {
            print("[Planit] Failed to save todos: \(error)")
        }
    }

    func loadTodos() {
        guard fileManager.fileExists(atPath: todosPath.path) else { return }
        do {
            let data = try Data(contentsOf: todosPath)
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch {
            print("[Planit] Failed to load todos: \(error)")
        }
    }

    private func saveCompletedEvents() {
        do {
            let data = try JSONEncoder().encode(Array(completedEventIDs))
            try data.write(to: completedEventsPath, options: .atomic)
        } catch {
            print("[Planit] Failed to save completed events: \(error)")
        }
    }

    private func loadCompletedEvents() {
        guard fileManager.fileExists(atPath: completedEventsPath.path) else { return }
        do {
            let data = try Data(contentsOf: completedEventsPath)
            let ids = try JSONDecoder().decode([String].self, from: data)
            completedEventIDs = Set(ids)
        } catch {
            print("[Planit] Failed to load completed events: \(error)")
        }
    }

    func saveCategories() {
        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: categoriesPath, options: .atomic)
        } catch {
            print("[Planit] Failed to save categories: \(error)")
        }
    }

    func loadCategories() {
        if fileManager.fileExists(atPath: categoriesPath.path) {
            do {
                let data = try Data(contentsOf: categoriesPath)
                categories = try JSONDecoder().decode([TodoCategory].self, from: data)
                return
            } catch {
                print("[Planit] Failed to load categories: \(error)")
            }
        }
        // First launch: use defaults
        categories = TodoCategory.defaults
        saveCategories()
    }

    // MARK: - EventKit

    func requestCalendarAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                guard granted, error == nil else { return }
                Task { @MainActor in
                    self?.fetchEvents(for: self?.currentMonth ?? Date())
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                guard granted, error == nil else { return }
                Task { @MainActor in
                    self?.fetchEvents(for: self?.currentMonth ?? Date())
                }
            }
        }
    }

    func fetchEvents(for month: Date) {
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

    // MARK: - EventKit Write (Google Calendar Sync)

    /// Default writable calendar (prefers Google, falls back to default)
    private var writableCalendar: EKCalendar? {
        // Prefer Google calendar
        if let google = eventStore.calendars(for: .event).first(where: {
            $0.source.sourceType == .calDAV && $0.allowsContentModifications
        }) {
            return google
        }
        return eventStore.defaultCalendarForNewEvents
    }

    /// Create a new event in the system calendar (syncs to Google)
    func addEventToCalendar(title: String, startDate: Date, endDate: Date, isAllDay: Bool) -> Bool {
        guard let cal = writableCalendar else { return false }
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = title
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.isAllDay = isAllDay
        ekEvent.calendar = cal
        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            fetchEvents(for: currentMonth)
            return true
        } catch {
            print("[Planit] Failed to create event: \(error)")
            return false
        }
    }

    /// Update an existing calendar event
    func updateCalendarEvent(eventID: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool) -> Bool {
        guard let ekEvent = eventStore.event(withIdentifier: eventID) else { return false }
        ekEvent.title = title
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.isAllDay = isAllDay
        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            fetchEvents(for: currentMonth)
            return true
        } catch {
            print("[Planit] Failed to update event: \(error)")
            return false
        }
    }

    /// Delete a calendar event
    func deleteCalendarEvent(eventID: String) -> Bool {
        guard let ekEvent = eventStore.event(withIdentifier: eventID) else { return false }
        do {
            try eventStore.remove(ekEvent, span: .thisEvent)
            completedEventIDs.remove(eventID)
            saveCompletedEvents()
            fetchEvents(for: currentMonth)
            return true
        } catch {
            print("[Planit] Failed to delete event: \(error)")
            return false
        }
    }

    /// Get list of writable calendar names
    var writableCalendars: [(name: String, identifier: String)] {
        eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { ($0.title, $0.calendarIdentifier) }
    }
}
