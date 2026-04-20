import Foundation
import Testing
@testable import Calen

private enum CalendarSyncRegressionSource {
    static func read(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func body(of functionName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(functionName)") else {
            throw CalendarSyncRegressionFailure("Missing function \(functionName)")
        }
        guard let openingBrace = source[nameRange.lowerBound...].firstIndex(of: "{") else {
            throw CalendarSyncRegressionFailure("Missing body for \(functionName)")
        }
        return try braceBlock(openingAt: openingBrace, in: source)
    }

    static func braceBlock(openingAt openingBrace: String.Index, in source: String) throws -> String {
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
        throw CalendarSyncRegressionFailure("Unclosed brace block")
    }

    static func block(after needle: String, in source: String) throws -> String {
        guard let needleRange = source.range(of: needle) else {
            throw CalendarSyncRegressionFailure("Missing block marker \(needle)")
        }
        guard let openingBrace = source[needleRange.upperBound...].firstIndex(of: "{") else {
            throw CalendarSyncRegressionFailure("Missing block after \(needle)")
        }
        return try braceBlock(openingAt: openingBrace, in: source)
    }

    static func segment(from startNeedle: String, to endNeedle: String, in source: String) throws -> String {
        guard let start = source.range(of: startNeedle)?.lowerBound else {
            throw CalendarSyncRegressionFailure("Missing segment start \(startNeedle)")
        }
        guard let end = source.range(of: endNeedle, range: start..<source.endIndex)?.lowerBound else {
            throw CalendarSyncRegressionFailure("Missing segment end \(endNeedle)")
        }
        return String(source[start..<end])
    }
}

private struct CalendarSyncRegressionFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

@Test func keychainQueries_doNotMixAccessControlWithSynchronizable() throws {
    let source = try CalendarSyncRegressionSource.read("Planit/Services/KeychainHelper.swift")
    let saveBody = try CalendarSyncRegressionSource.body(of: "saveItem", in: source)

    // kSecAttrAccessControl과 kSecAttrSynchronizable을 동시에 쓰면 SecItemAdd가 errSecParam(-50)으로 실패.
    // 단순하게 service+account만으로 조회하고 kSecAttrAccessible만 쓰는 것이 올바른 방식.
    #expect(!saveBody.contains("kSecAttrAccessControl"),
            "saveItem must not use kSecAttrAccessControl — it conflicts with kSecAttrSynchronizable causing silent save failures.")
    #expect(saveBody.contains("kSecAttrAccessible"),
            "saveItem must use kSecAttrAccessible to set protection level without conflicting attributes.")
}

@Test func keychainSave_recoversStaleRowByDeleteAndRetryingAdd() throws {
    let source = try CalendarSyncRegressionSource.read("Planit/Services/KeychainHelper.swift")
    let saveBody = try CalendarSyncRegressionSource.body(of: "saveItem", in: source)

    // update 실패(errSecItemNotFound 이외 에러) 시 기존 항목 삭제 후 재추가해야 한다.
    #expect(saveBody.contains("SecItemDelete(query"),
            "saveItem must delete a stale row before retrying SecItemAdd when SecItemUpdate fails.")
    #expect(saveBody.contains("SecItemAdd(addQuery"),
            "saveItem must retry SecItemAdd after clearing the stale row.")
}

@Test func keychainLoad_usesSimpleServiceAccountQuery() throws {
    let source = try CalendarSyncRegressionSource.read("Planit/Services/KeychainHelper.swift")
    let loadBody = try CalendarSyncRegressionSource.body(of: "loadItem", in: source)

    // 단순 service+account 조회가 모든 과거 버전 항목을 포괄한다 (속성 제한 없음).
    #expect(loadBody.contains("kSecAttrService"),
            "loadItem must query by service to find items across all historical attribute combinations.")
    #expect(loadBody.contains("kSecReturnData as String: true"),
            "loadItem must request data return.")
}

@Test func keychainDelete_usesSimpleServiceAccountQuery() throws {
    let source = try CalendarSyncRegressionSource.read("Planit/Services/KeychainHelper.swift")
    let deleteBody = try CalendarSyncRegressionSource.body(of: "deleteItem", in: source)

    #expect(deleteBody.contains("SecItemDelete"),
            "deleteItem must call SecItemDelete.")
    #expect(deleteBody.contains("errSecSuccess || status == errSecItemNotFound"),
            "deleteItem must treat both success and not-found as successful deletion.")
}

@Test func pendingCalendarEdit_decodesLegacyPayloadWithoutCalendarID() throws {
    let id = UUID()
    let json = """
    {
      "id": "\(id.uuidString)",
      "action": "update",
      "title": "Move planning block",
      "startDate": 1200,
      "endDate": 1800,
      "isAllDay": false,
      "eventId": "event-123",
      "createdAt": 1000
    }
    """.data(using: .utf8)!

    let edit = try JSONDecoder().decode(PendingCalendarEdit.self, from: json)

    #expect(edit.id == id)
    #expect(edit.calendarID == nil)
    #expect(PendingCalendarEdit.isSafeQueue([edit]))
}

@Test func pendingCalendarEdit_roundTripsCalendarIDForNonPrimaryCalendar() throws {
    let edit = PendingCalendarEdit(
        action: "delete",
        eventId: "event-456",
        calendarID: "google:team@example.com"
    )

    let data = try JSONEncoder().encode(edit)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let decoded = try JSONDecoder().decode(PendingCalendarEdit.self, from: data)

    #expect(object["calendarID"] as? String == "google:team@example.com")
    #expect(decoded.calendarID == "google:team@example.com")
    #expect(PendingCalendarEdit.isSafeQueue([decoded]))
}

@Test func calendarViewModel_googleFetchTTL_skipsRecentFetchUnlessForced() {
    let lastFetch = Date(timeIntervalSinceReferenceDate: 1_000)

    #expect(CalendarViewModel.shouldSkipGoogleFetch(
        lastFetch: lastFetch,
        now: lastFetch.addingTimeInterval(CalendarViewModel.googleFetchTTL - 0.1),
        force: false
    ))
    #expect(!CalendarViewModel.shouldSkipGoogleFetch(
        lastFetch: lastFetch,
        now: lastFetch.addingTimeInterval(CalendarViewModel.googleFetchTTL - 0.1),
        force: true
    ))
}

@Test func calendarViewModel_googleFetchTTL_allowsFetchAtBoundaryOrWithoutHistory() {
    let lastFetch = Date(timeIntervalSinceReferenceDate: 1_000)

    #expect(!CalendarViewModel.shouldSkipGoogleFetch(
        lastFetch: lastFetch,
        now: lastFetch.addingTimeInterval(CalendarViewModel.googleFetchTTL),
        force: false
    ))
    #expect(!CalendarViewModel.shouldSkipGoogleFetch(
        lastFetch: nil,
        now: lastFetch,
        force: false
    ))
}

@Test func calendarViewModel_refreshIntervalAndGoogleTTLStayAtRegressionValues() {
    #expect(CalendarViewModel.googleFetchTTL == 120)
    #expect(CalendarViewModel.periodicRefreshInterval == 180)
}

@Test func calendarViewModel_fetchTimerAndCrudPathsUseRegressionHelpers() throws {
    let source = try CalendarSyncRegressionSource.read("Planit/ViewModels/CalendarViewModel.swift")
    let fetchBody = try CalendarSyncRegressionSource.body(of: "fetchEventsFromGoogle", in: source)
    let timerBody = try CalendarSyncRegressionSource.body(of: "startPeriodicRefresh", in: source)
    let crudBody = try CalendarSyncRegressionSource.body(of: "recordCRUDFailure", in: source)

    #expect(fetchBody.contains("shouldSkipGoogleFetch"),
            "fetchEventsFromGoogle must use the tested TTL predicate.")
    #expect(timerBody.contains("periodicRefreshInterval"),
            "The refresh timer must use the tested 180-second interval constant.")
    #expect(crudBody.contains("shouldMarkNeedsReauth"),
            "CRUD failure handling must use the tested 403 reauth predicate.")
}

@Test func calendarViewModel_crud403MarksNeedsReauth() {
    #expect(CalendarViewModel.shouldMarkNeedsReauth(after: GoogleCalendarError.httpStatus(403)))
    #expect(!CalendarViewModel.shouldMarkNeedsReauth(after: GoogleCalendarError.httpStatus(401)))
    #expect(!CalendarViewModel.shouldMarkNeedsReauth(after: URLError(.timedOut)))
}
