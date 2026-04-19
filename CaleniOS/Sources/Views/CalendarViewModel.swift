#if os(iOS)
import Foundation
import SwiftData
import Combine

// MARK: - CalendarViewModel
//
// 레퍼런스 `Calen-iOS/Calen/Features/Calendar/CalendarViewModel.swift` 1:1 포팅 (M2 UI v3).

@MainActor
final class CalendarViewModel: ObservableObject {

    // MARK: - Published State

    /// The currently highlighted / selected day
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// The month being displayed (always normalised to the 1st of the month)
    @Published var currentMonth: Date

    /// 42-slot grid (6 weeks × 7 days). nil = padding cell outside the month.
    @Published var datesInMonth: [Date?] = []

    /// Schedules that belong to `selectedDate`
    @Published var schedulesForSelectedDate: [Schedule] = []

    /// All schedules visible in the current context
    @Published var allSchedules: [Schedule] = []

    // MARK: - Internal State

    /// Injected after the SwiftData environment is available
    var modelContext: ModelContext? {
        didSet { fetchAll() }
    }

    private let cal = Calendar.current

    // MARK: - Init

    init(modelContext: ModelContext? = nil) {
        // Normalise to the 1st of the current month
        let now = Date()
        var comps = Calendar.current.dateComponents([.year, .month], from: now)
        comps.day = 1
        self.currentMonth = Calendar.current.date(from: comps) ?? now
        self.modelContext = modelContext

        rebuildGrid()
        fetchAll()
    }

    // MARK: - Public API

    /// Move forward one month
    func nextMonth() {
        guard let next = cal.date(byAdding: .month, value: 1, to: currentMonth) else { return }
        currentMonth = next
        rebuildGrid()
    }

    /// Move back one month
    func previousMonth() {
        guard let prev = cal.date(byAdding: .month, value: -1, to: currentMonth) else { return }
        currentMonth = prev
        rebuildGrid()
    }

    /// Select a date and refresh the daily schedule list
    func selectDate(_ date: Date) {
        selectedDate = cal.startOfDay(for: date)
        updateSelectedDateSchedules()
    }

    /// Returns true when at least one schedule falls on `date`
    func hasSchedule(for date: Date) -> Bool {
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        return allSchedules.contains { $0.date >= start && $0.date < end }
    }

    /// Category of the first schedule on `date` — used to colour the dot
    func firstCategory(for date: Date) -> ScheduleCategory? {
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        return allSchedules
            .first { $0.date >= start && $0.date < end }?
            .category
    }

    /// Persist a new schedule and refresh both lists
    func addSchedule(_ schedule: Schedule) {
        guard let context = modelContext else {
            // Preview / no context — just append locally
            allSchedules.append(schedule)
            updateSelectedDateSchedules()
            return
        }
        context.insert(schedule)
        do {
            try context.save()
        } catch {
            print("[CalendarViewModel] save error: \(error)")
        }
        fetchAll()
    }

    /// Re-fetch from the model context (or use mock data if unavailable)
    func fetchAll() {
        guard let context = modelContext else {
            allSchedules = Self.mockSchedules()
            updateSelectedDateSchedules()
            return
        }

        let descriptor = FetchDescriptor<Schedule>(
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.startTime)]
        )
        do {
            allSchedules = try context.fetch(descriptor)
        } catch {
            print("[CalendarViewModel] fetchAll error: \(error)")
            allSchedules = []
        }
        updateSelectedDateSchedules()
    }

    // MARK: - Grid Building

    /// Builds a 42-element (6 × 7) array of optional Date values.
    /// Cells before the first day of the month and after the last day are nil.
    func buildDatesInMonth(for monthDate: Date) -> [Date?] {
        var comps = cal.dateComponents([.year, .month], from: monthDate)
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps) else {
            return Array(repeating: nil, count: 42)
        }

        // Weekday index of the first day (Sunday = 0 … Saturday = 6)
        let firstWeekday = cal.component(.weekday, from: firstOfMonth) - 1

        // Total days in the month
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: 42)
        for dayIndex in 0..<daysInMonth {
            let cellIndex = firstWeekday + dayIndex
            guard cellIndex < 42 else { break }
            cells[cellIndex] = cal.date(byAdding: .day, value: dayIndex, to: firstOfMonth)
        }
        return cells
    }

    // MARK: - Private Helpers

    private func rebuildGrid() {
        datesInMonth = buildDatesInMonth(for: currentMonth)
    }

    private func updateSelectedDateSchedules() {
        let start = cal.startOfDay(for: selectedDate)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        schedulesForSelectedDate = allSchedules
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Mock Data (for previews)

    static func mockSchedules() -> [Schedule] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        func make(daysOffset: Int, hour: Int, title: String, cat: ScheduleCategory) -> Schedule {
            let date = cal.date(byAdding: .day, value: daysOffset, to: today) ?? today
            let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            let end = cal.date(byAdding: .hour, value: 1, to: start)
            return Schedule(title: title, date: date, startTime: start, endTime: end, category: cat)
        }

        return [
            make(daysOffset: 0, hour: 9,  title: "팀 스탠드업",   cat: .meeting),
            make(daysOffset: 0, hour: 13, title: "점심 식사",    cat: .meal),
            make(daysOffset: 0, hour: 18, title: "헬스장",       cat: .exercise),
            make(daysOffset: 2, hour: 10, title: "기획 회의",    cat: .work),
            make(daysOffset: 5, hour: 14, title: "거래처 미팅",  cat: .meeting),
        ]
    }
}
#endif
