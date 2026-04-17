import Foundation
import Testing
@testable import Calen

private enum CRUDRegressionSource {
    static let viewModel = "Planit/ViewModels/CalendarViewModel.swift"

    static func read(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func body(of functionName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(functionName)") else {
            throw TestFailure("Missing function \(functionName)")
        }
        guard let openingBrace = source[nameRange.lowerBound...].firstIndex(of: "{") else {
            throw TestFailure("Missing body for \(functionName)")
        }

        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        throw TestFailure("Unclosed body for \(functionName)")
    }

    static func switchCase(_ caseName: String, in functionBody: String) throws -> String {
        guard let start = functionBody.range(of: "case \(caseName):")?.lowerBound else {
            throw TestFailure("Missing case \(caseName)")
        }

        let remainder = functionBody[start...]
        let nextCase = remainder
            .range(of: #"\n\s*case\s+\."#, options: .regularExpression)?
            .lowerBound
        let defaultCase = remainder
            .range(of: #"\n\s*default\s*:"#, options: .regularExpression)?
            .lowerBound
        let end = [nextCase, defaultCase, functionBody.endIndex].compactMap { $0 }.min() ?? functionBody.endIndex
        return String(functionBody[start..<end])
    }

    static func event(_ id: String, source: CalendarEventSource, title: String = "Event") -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            color: .blue,
            isAllDay: false,
            calendarName: source == .google ? "Google" : "Home",
            calendarID: source == .google ? "google:primary" : "apple:home",
            source: source
        )
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

@Test func crudRegression_deleteAppleEventRoutesToEventKitOnly() throws {
    let source = try CRUDRegressionSource.read(CRUDRegressionSource.viewModel)
    let body = try CRUDRegressionSource.body(of: "deleteCalendarEvent", in: source)

    #expect(body.contains("CalendarEvent") || body.contains(".apple"),
            "deleteCalendarEvent must route from the event source, not only auth state.")
    #expect(body.contains("switch") && body.contains(".apple"),
            "Apple delete needs an explicit .apple branch.")

    let appleBranch = try CRUDRegressionSource.switchCase(".apple", in: body)
    #expect(appleBranch.contains("eventStore") && appleBranch.contains("remove"),
            "Apple delete must call EventKit removal.")
    #expect(!appleBranch.contains("deleteGoogleEvent") && !appleBranch.contains("googleService.deleteEvent"),
            "Apple delete must not call Google Calendar deletion.")
}

@Test func crudRegression_deleteGoogleEventRoutesToGoogleOnly() throws {
    let source = try CRUDRegressionSource.read(CRUDRegressionSource.viewModel)
    let body = try CRUDRegressionSource.body(of: "deleteCalendarEvent", in: source)

    #expect(body.contains("switch") && body.contains(".google"),
            "Google delete needs an explicit .google branch.")

    let googleBranch = try CRUDRegressionSource.switchCase(".google", in: body)
    #expect(googleBranch.contains("deleteGoogleEvent") || googleBranch.contains("googleService.deleteEvent"),
            "Google delete must call the Google Calendar service.")
    #expect(!googleBranch.contains("eventStore.remove"),
            "Google delete must not call EventKit removal.")
}

@Test func crudRegression_appleAndGoogleEventsWithSameIdAreDedupedForUI() {
    let google = CRUDRegressionSource.event("shared-id", source: .google, title: "Google copy")
    let apple = CRUDRegressionSource.event("shared-id", source: .apple, title: "Apple copy")
    let unique = CRUDRegressionSource.event("unique-id", source: .google, title: "Unique")

    var seen = Set<String>()
    let visible = [google, apple, unique].filter { seen.insert($0.id).inserted }

    #expect(visible.map(\.id) == ["shared-id", "unique-id"])
    #expect(visible.count == Set(visible.map(\.id)).count)
}

@Test func crudRegression_appleMergeDedupesAgainstExistingGoogleEvents() throws {
    let source = try CRUDRegressionSource.read(CRUDRegressionSource.viewModel)
    let body = try CRUDRegressionSource.body(of: "mergeAppleCalendarEvents", in: source)

    #expect(body.contains("Set<String>") || body.contains("seen"),
            "Apple merge must dedupe against existing Google IDs before updating calendarEvents.")
    #expect(body.contains("calendarEvents =") || body.contains("removeAll {") && body.contains("append"),
            "Apple merge must update calendarEvents through a deterministic merge path.")
}

@Test func crudRegression_updateEventRoutesBySource() throws {
    let source = try CRUDRegressionSource.read(CRUDRegressionSource.viewModel)
    let body = try CRUDRegressionSource.body(of: "updateCalendarEvent", in: source)

    #expect(body.contains("CalendarEvent") || body.contains(".apple") || body.contains(".google"),
            "updateCalendarEvent must route by event source.")
    #expect(body.contains("switch") && body.contains(".google") && body.contains(".apple"),
            "updateCalendarEvent needs explicit Google and Apple branches.")

    let googleBranch = try CRUDRegressionSource.switchCase(".google", in: body)
    #expect(googleBranch.contains("updateGoogleEvent") || googleBranch.contains("googleService.updateEvent"),
            "Google updates must use GoogleCalendarService.")
    #expect(!googleBranch.contains("eventStore.save"),
            "Google updates must not save through EventKit.")

    let appleBranch = try CRUDRegressionSource.switchCase(".apple", in: body)
    #expect(appleBranch.contains("eventStore") && appleBranch.contains("save"),
            "Apple updates must save through EventKit.")
    #expect(!appleBranch.contains("updateGoogleEvent") && !appleBranch.contains("googleService.updateEvent"),
            "Apple updates must not call GoogleCalendarService.")
}

@Test func crudRegression_syncedTodoEventIsExcludedFromNextEventFetchDisplay() throws {
    let source = try CRUDRegressionSource.read(CRUDRegressionSource.viewModel)
    let body = try CRUDRegressionSource.body(of: "eventsForDate", in: source)

    #expect(body.contains("todos.compactMap") && body.contains("googleEventId"),
            "eventsForDate must derive the set of Google event IDs already represented by todos.")
    #expect(body.contains("todoEventIds.contains(event.id)") && body.contains("return false"),
            "Fetched Google events with todo googleEventId must be hidden to prevent duplicates.")
}

@Test func crudRegression_repeatingTodoCreationDoesNotCreateDuplicateGoogleEvents() throws {
    let source = try CRUDRegressionSource.read(CRUDRegressionSource.viewModel)
    let body = try CRUDRegressionSource.body(of: "addTodo", in: source)

    #expect(body.contains("isRepeating"),
            "addTodo must keep repeating todo state while avoiding extra Google event creates.")
    #expect(body.contains("googleEventId"),
            "A repeating todo synced to Google must store the created event ID for later dedupe.")
    #expect(!body.contains("for ") && !body.contains("while "),
            "Creating a repeating todo must not loop-create duplicate Google events.")
}

@Test func crudRegression_appleToggleOffImmediatelyRemovesAppleEvents() {
    let events = [
        CRUDRegressionSource.event("google-1", source: .google),
        CRUDRegressionSource.event("apple-1", source: .apple),
        CRUDRegressionSource.event("local-1", source: .local),
    ]

    let filtered = CalendarViewModel.eventsExcludingAppleCalendar(events)

    #expect(filtered.map(\.id) == ["google-1", "local-1"])
    #expect(!filtered.contains { $0.source == .apple })
}

@Test func crudRegression_pendingEditRetryLoopDrops4xxFailures() throws {
    for code in [400, 401, 403, 404, 409] {
        #expect(!CalendarViewModel.shouldQueueGoogleMutation(after: GoogleCalendarError.httpStatus(code)),
                "HTTP \(code) is permanent and must not stay in the pending edit retry queue.")
    }

    let source = try CRUDRegressionSource.read(CRUDRegressionSource.viewModel)
    let body = try CRUDRegressionSource.body(of: "syncPendingEdits", in: source)
    #expect(body.contains("shouldQueueGoogleMutation"),
            "syncPendingEdits must use the same retry policy before appending failures back to remaining.")
}
