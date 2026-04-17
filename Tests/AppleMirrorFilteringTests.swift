import Foundation
import SwiftUI
import Testing
@testable import Calen

private enum AppleMirrorFilteringFixture {
    static let base = Date(timeIntervalSince1970: 1_700_000_000)

    static func event(
        id: String,
        source: CalendarEventSource,
        title: String = "Team Sync",
        startOffset: TimeInterval,
        duration: TimeInterval = 3_600,
        isAllDay: Bool = false,
        calendarID: String
    ) -> CalendarEvent {
        let start = base.addingTimeInterval(startOffset)
        return CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            color: .blue,
            isAllDay: isAllDay,
            calendarName: source == .apple ? "Apple" : "Google",
            calendarID: calendarID,
            source: source
        )
    }

    static func minute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }
}

@Test func appleMirrorSuppress_targetsOnlyMovedRepeatingInstance() {
    let oldMirror = AppleMirrorFilteringFixture.event(
        id: "apple-old",
        source: .apple,
        startOffset: 0,
        calendarID: "apple:google"
    )
    let otherInstance = AppleMirrorFilteringFixture.event(
        id: "apple-other",
        source: .apple,
        startOffset: 86_400,
        calendarID: "apple:google"
    )
    let movedGoogle = AppleMirrorFilteringFixture.event(
        id: "google-moved",
        source: .google,
        startOffset: 7_200,
        calendarID: "google:primary"
    )
    let suppressKey = CalendarViewModel.SuppressKey(
        title: oldMirror.title,
        oldStartMinute: AppleMirrorFilteringFixture.minute(oldMirror.startDate),
        calendarID: oldMirror.calendarID
    )

    let result = CalendarViewModel.filteredAppleCalendarEvents(
        [oldMirror, otherInstance],
        googleEvents: [movedGoogle],
        suppressedAppleMirrors: [suppressKey: Date(timeIntervalSince1970: 1_700_001_000)],
        now: Date(timeIntervalSince1970: 1_700_000_100)
    )

    #expect(result.events.map(\.id) == ["apple-other"])
    #expect(result.mirrorBySuppress == 1)
}

@Test func appleMirrorSuppress_keepsAppleOnlyEventWithSameTitleInDifferentCalendar() {
    let appleOnly = AppleMirrorFilteringFixture.event(
        id: "apple-personal",
        source: .apple,
        startOffset: 0,
        calendarID: "apple:personal"
    )
    let movedGoogle = AppleMirrorFilteringFixture.event(
        id: "google-moved",
        source: .google,
        startOffset: 7_200,
        calendarID: "google:primary"
    )
    let suppressKey = CalendarViewModel.SuppressKey(
        title: appleOnly.title,
        oldStartMinute: AppleMirrorFilteringFixture.minute(appleOnly.startDate),
        calendarID: "apple:google"
    )

    let result = CalendarViewModel.filteredAppleCalendarEvents(
        [appleOnly],
        googleEvents: [movedGoogle],
        suppressedAppleMirrors: [suppressKey: Date(timeIntervalSince1970: 1_700_001_000)],
        now: Date(timeIntervalSince1970: 1_700_000_100)
    )

    #expect(result.events.map(\.id) == ["apple-personal"])
    #expect(result.mirrorBySuppress == 0)
}

@Test func appleMirrorFiltering_expiredSuppressDoesNotHideAndFingerprintIncludesDuration() {
    let appleOnlyShorter = AppleMirrorFilteringFixture.event(
        id: "apple-shorter",
        source: .apple,
        startOffset: 0,
        duration: 1_800,
        calendarID: "apple:personal"
    )
    let googleLonger = AppleMirrorFilteringFixture.event(
        id: "google-longer",
        source: .google,
        startOffset: 0,
        duration: 3_600,
        calendarID: "google:primary"
    )
    let suppressKey = CalendarViewModel.SuppressKey(
        title: appleOnlyShorter.title,
        oldStartMinute: AppleMirrorFilteringFixture.minute(appleOnlyShorter.startDate),
        calendarID: appleOnlyShorter.calendarID
    )

    let result = CalendarViewModel.filteredAppleCalendarEvents(
        [appleOnlyShorter],
        googleEvents: [googleLonger],
        suppressedAppleMirrors: [suppressKey: Date(timeIntervalSince1970: 1_700_000_050)],
        now: Date(timeIntervalSince1970: 1_700_000_100)
    )

    #expect(result.events.map(\.id) == ["apple-shorter"])
    #expect(result.mirrorByFingerprint == 0)
    #expect(result.mirrorBySuppress == 0)
}
