import Foundation

public enum CalendarInteractionMath {
    public static func dropColumnIndex(
        originColumn: Int,
        translationX: Double,
        columnWidth: Double
    ) -> Int {
        guard columnWidth > 0 else { return max(0, min(6, originColumn)) }
        let raw = Double(originColumn) + (translationX / columnWidth).rounded()
        return max(0, min(6, Int(raw)))
    }

    public static func dropDay(
        weekStart: Date,
        originColumn: Int,
        translationX: Double,
        columnWidth: Double,
        calendar: Calendar
    ) -> Date {
        let column = dropColumnIndex(
            originColumn: originColumn,
            translationX: translationX,
            columnWidth: columnWidth
        )
        return calendar.date(byAdding: .day, value: column, to: calendar.startOfDay(for: weekStart))
            ?? calendar.startOfDay(for: weekStart)
    }

    public static func shiftedRange(
        start: Date,
        end: Date,
        toStartDay newStartDay: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let duration = end.timeIntervalSince(start)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: start)
        var day = calendar.dateComponents([.year, .month, .day], from: newStartDay)
        day.hour = time.hour
        day.minute = time.minute
        day.second = time.second
        day.nanosecond = time.nanosecond
        let newStart = calendar.date(from: day) ?? newStartDay
        return (newStart, newStart.addingTimeInterval(duration))
    }

    public static func movedTimeRange(
        start: Date,
        end: Date,
        verticalTranslation: Double,
        pointsPerHour: Double,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        guard pointsPerHour > 0 else { return (start, end) }
        let deltaMinutes = (verticalTranslation / pointsPerHour) * 60
        let movedStart = start.addingTimeInterval(deltaMinutes * 60)
        let snappedStart = snapToQuarterHour(movedStart, calendar: calendar)
        return (snappedStart, snappedStart.addingTimeInterval(end.timeIntervalSince(start)))
    }

    public static func resizedEnd(
        start: Date,
        end: Date,
        verticalTranslation: Double,
        pointsPerHour: Double,
        minimumMinutes: Int = 15,
        calendar: Calendar
    ) -> Date {
        guard pointsPerHour > 0 else { return end }
        let deltaMinutes = (verticalTranslation / pointsPerHour) * 60
        let rawEnd = end.addingTimeInterval(deltaMinutes * 60)
        let snapped = snapToQuarterHour(rawEnd, calendar: calendar)
        let minimumEnd = start.addingTimeInterval(TimeInterval(max(15, minimumMinutes) * 60))
        return max(snapped, minimumEnd)
    }

    public static func snapToQuarterHour(_ date: Date, calendar: Calendar) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        let quantum: Double = 15 * 60
        let snapped = (seconds / quantum).rounded() * quantum
        return Date(timeIntervalSinceReferenceDate: snapped)
    }
}
