import Foundation

struct MenuBarProgressSnapshot: Equatable {
    enum State: Equatable {
        case neutral
        case active
    }

    let completed: Int
    let total: Int
    let percent: Int?
    let state: State

    static func make(todayTotal: Int, todayCompleted: Int) -> MenuBarProgressSnapshot {
        let safeTotal = max(0, todayTotal)
        let safeCompleted = min(max(0, todayCompleted), safeTotal)

        guard safeTotal > 0 else {
            return MenuBarProgressSnapshot(completed: 0, total: 0, percent: nil, state: .neutral)
        }

        let percent = Int((Double(safeCompleted) / Double(safeTotal) * 100).rounded())
        return MenuBarProgressSnapshot(
            completed: safeCompleted,
            total: safeTotal,
            percent: percent,
            state: .active
        )
    }

    static func make(
        todos: [TodoItem],
        reminders: [TodoItem],
        events: [CalendarEvent],
        completedEventIDs: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MenuBarProgressSnapshot {
        let todayTodos = todos.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let todayReminders = reminders.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let todoEventIDs = Set((todayTodos + todayReminders).compactMap(\.googleEventId))
        let todayEvents = events.filter { event in
            guard !event.isAllDay, !todoEventIDs.contains(event.id) else { return false }
            return eventOccurs(event, on: now, calendar: calendar)
        }

        let completedTodos = todayTodos.filter(\.isCompleted).count
        let completedReminders = todayReminders.filter(\.isCompleted).count
        let completedEvents = todayEvents.filter { completedEventIDs.contains($0.id) }.count

        return make(
            todayTotal: todayTodos.count + todayReminders.count + todayEvents.count,
            todayCompleted: completedTodos + completedReminders + completedEvents
        )
    }

    private static func eventOccurs(_ event: CalendarEvent, on date: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return false
        }

        return event.startDate < dayEnd && event.endDate > dayStart
    }
}
