import Foundation
import Testing
import CalenShared

private func uxDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

@Test func monthDropColumn_clampsTranslatedColumnInsideWeek() {
    #expect(CalendarInteractionMath.dropColumnIndex(originColumn: 2, translationX: 160, columnWidth: 52) == 5)
    #expect(CalendarInteractionMath.dropColumnIndex(originColumn: 2, translationX: -400, columnWidth: 52) == 0)
    #expect(CalendarInteractionMath.dropColumnIndex(originColumn: 6, translationX: 200, columnWidth: 52) == 6)
}

@Test func monthDropDay_preservesTargetWeekColumn() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let weekStart = uxDate("2026-05-10T00:00:00Z")

    let target = CalendarInteractionMath.dropDay(
        weekStart: weekStart,
        originColumn: 1,
        translationX: 132,
        columnWidth: 44,
        calendar: calendar
    )

    #expect(calendar.component(.weekday, from: target) == 5)
    #expect(calendar.component(.day, from: target) == 14)
}

@Test func timeDragSnapsToNearestFifteenMinutesAndKeepsDuration() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = uxDate("2026-05-11T09:07:00Z")
    let end = uxDate("2026-05-11T10:07:00Z")

    let moved = CalendarInteractionMath.movedTimeRange(
        start: start,
        end: end,
        verticalTranslation: 37,
        pointsPerHour: 80,
        calendar: calendar
    )

    #expect(calendar.component(.hour, from: moved.start) == 9)
    #expect(calendar.component(.minute, from: moved.start) == 30)
    #expect(Int(moved.end.timeIntervalSince(moved.start) / 60) == 60)
}

@Test func timeResizeSnapsEndAndKeepsMinimumDuration() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = uxDate("2026-05-11T09:00:00Z")
    let end = uxDate("2026-05-11T10:00:00Z")

    let resized = CalendarInteractionMath.resizedEnd(
        start: start,
        end: end,
        verticalTranslation: -100,
        pointsPerHour: 80,
        minimumMinutes: 30,
        calendar: calendar
    )

    #expect(Int(resized.timeIntervalSince(start) / 60) == 30)
}

@Test func completionMetadata_roundTripsThroughCalendarEventDescription() {
    let original = CalendarEvent(
        id: "evt-1",
        calendarId: "primary",
        title: "Review PR",
        startDate: uxDate("2026-05-11T09:00:00Z"),
        endDate: uxDate("2026-05-11T10:00:00Z"),
        description: "notes"
    )

    let completed = original.settingCompleted(true)
    #expect(completed.isCompleted)
    #expect(completed.description?.contains("calenCompleted=true") == true)

    let reopened = completed.settingCompleted(false)
    #expect(!reopened.isCompleted)
    #expect(reopened.description?.contains("calenCompleted=true") == false)
}

@Test func eveningReviewSuggestions_onlyIncludePastIncompleteItems() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = uxDate("2026-05-11T21:30:00Z")

    let pastOpen = CalendarEvent(
        id: "open",
        calendarId: "primary",
        title: "Finish notes",
        startDate: uxDate("2026-05-11T18:00:00Z"),
        endDate: uxDate("2026-05-11T19:00:00Z")
    )
    let pastDone = CalendarEvent(
        id: "done",
        calendarId: "primary",
        title: "Done",
        startDate: uxDate("2026-05-11T17:00:00Z"),
        endDate: uxDate("2026-05-11T18:00:00Z")
    ).settingCompleted(true)
    let future = CalendarEvent(
        id: "future",
        calendarId: "primary",
        title: "Future",
        startDate: uxDate("2026-05-11T23:00:00Z"),
        endDate: uxDate("2026-05-12T00:00:00Z")
    )

    let suggestions = EveningReviewRescheduler.suggestions(
        for: [pastOpen, pastDone, future],
        now: now,
        calendar: calendar
    )

    #expect(suggestions.map(\.event.id) == ["open"])
    #expect(calendar.isDate(suggestions[0].targetStart, inSameDayAs: uxDate("2026-05-12T00:00:00Z")))
    #expect(Int(suggestions[0].targetEnd.timeIntervalSince(suggestions[0].targetStart) / 60) == 60)
}
