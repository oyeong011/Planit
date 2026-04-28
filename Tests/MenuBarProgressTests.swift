import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Calen

@Suite("Menu bar progress")
struct MenuBarProgressTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let categoryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test("empty today uses neutral progress")
    func emptyTodayUsesNeutralProgress() {
        let snapshot = MenuBarProgressSnapshot.make(todayTotal: 0, todayCompleted: 0)

        #expect(snapshot.state == .neutral)
        #expect(snapshot.percent == nil)
        #expect(snapshot.completed == 0)
        #expect(snapshot.total == 0)
    }

    @Test("partial today rounds to nearest percent")
    func partialTodayRoundsToNearestPercent() {
        let snapshot = MenuBarProgressSnapshot.make(todayTotal: 3, todayCompleted: 2)

        #expect(snapshot.state == .active)
        #expect(snapshot.percent == 67)
        #expect(snapshot.completed == 2)
        #expect(snapshot.total == 3)
    }

    @Test("completed today clamps at 100 percent")
    func completedTodayClampsAtOneHundred() {
        let snapshot = MenuBarProgressSnapshot.make(todayTotal: 2, todayCompleted: 5)

        #expect(snapshot.percent == 100)
        #expect(snapshot.completed == 2)
        #expect(snapshot.total == 2)
    }

    @Test("today progress uses only today todos reminders and completed timed events")
    func todayProgressUsesOnlyTodayItems() throws {
        let now = try date("2026-04-28T12:00:00Z")
        let todayOpen = todo("today open", date: try date("2026-04-28T09:00:00Z"), completed: false)
        let todayDone = todo("today done", date: try date("2026-04-28T10:00:00Z"), completed: true)
        let tomorrowDone = todo("tomorrow done", date: try date("2026-04-29T10:00:00Z"), completed: true)
        let todayReminderDone = todo("reminder done", date: try date("2026-04-28T11:00:00Z"), completed: true)
        let timedEvent = event(
            id: "event-1",
            start: try date("2026-04-28T13:00:00Z"),
            end: try date("2026-04-28T14:00:00Z"),
            isAllDay: false
        )
        let tomorrowEvent = event(
            id: "event-2",
            start: try date("2026-04-29T13:00:00Z"),
            end: try date("2026-04-29T14:00:00Z"),
            isAllDay: false
        )
        let allDayEvent = event(
            id: "event-3",
            start: try date("2026-04-28T00:00:00Z"),
            end: try date("2026-04-29T00:00:00Z"),
            isAllDay: true
        )

        let snapshot = MenuBarProgressSnapshot.make(
            todos: [todayOpen, todayDone, tomorrowDone],
            reminders: [todayReminderDone],
            events: [timedEvent, tomorrowEvent, allDayEvent],
            completedEventIDs: ["event-1", "event-2", "event-3"],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.completed == 3)
        #expect(snapshot.total == 4)
        #expect(snapshot.percent == 75)
    }

    @Test("progress icon renders non-empty images")
    func progressIconRendersNonEmptyImages() {
        for snapshot in [
            MenuBarProgressSnapshot.make(todayTotal: 0, todayCompleted: 0),
            MenuBarProgressSnapshot.make(todayTotal: 4, todayCompleted: 1),
            MenuBarProgressSnapshot.make(todayTotal: 4, todayCompleted: 4),
        ] {
            let image = MenuBarProgressIcon.makeImage(snapshot: snapshot, updateAvailable: false)

            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
            #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
        }
    }

    @Test("progress icon resolves colors at draw time")
    func progressIconResolvesColorsAtDrawTime() throws {
        let source = try projectFile("Planit/Models/MenuBarProgressIcon.swift")

        #expect(source.contains("drawingHandler"),
                "Menu bar icons must resolve NSColor.labelColor during drawing so light/dark menu bars stay legible.")
        #expect(!source.contains("lockFocus()"),
                "A one-time lockFocus bitmap can become stale across appearance changes.")
    }

    private func todo(_ title: String, date: Date, completed: Bool) -> TodoItem {
        TodoItem(title: title, categoryID: categoryID, isCompleted: completed, date: date)
    }

    private func event(id: String, start: Date, end: Date, isAllDay: Bool) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            startDate: start,
            endDate: end,
            color: .blue,
            isAllDay: isAllDay
        )
    }

    private func date(_ isoString: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        let options: ISO8601DateFormatter.Options = [.withInternetDateTime]
        formatter.formatOptions = options
        return try #require(formatter.date(from: isoString))
    }

    private func projectFile(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
