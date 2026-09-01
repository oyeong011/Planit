import Foundation

public struct EveningReviewSuggestion: Equatable, Sendable, Identifiable {
    public var id: String { "\(event.calendarId)::\(event.id)::\(targetStart.timeIntervalSinceReferenceDate)" }
    public let event: CalendarEvent
    public let targetStart: Date
    public let targetEnd: Date
    public let reason: String
}

public enum EveningReviewRescheduler {
    public static func suggestions(
        for events: [CalendarEvent],
        now: Date = Date(),
        calendar: Calendar = .current,
        maxCount: Int = 5
    ) -> [EveningReviewSuggestion] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        return events
            .filter { event in
                !event.isAllDay
                    && !event.isCompleted
                    && event.endDate <= now
                    && calendar.isDate(event.startDate, inSameDayAs: now)
            }
            .sorted { $0.startDate < $1.startDate }
            .prefix(max(0, maxCount))
            .map { event in
                let shifted = CalendarInteractionMath.shiftedRange(
                    start: event.startDate,
                    end: event.endDate,
                    toStartDay: tomorrow,
                    calendar: calendar
                )
                return EveningReviewSuggestion(
                    event: event,
                    targetStart: shifted.start,
                    targetEnd: shifted.end,
                    reason: "오늘 완료되지 않은 일정"
                )
            }
    }
}
