import Foundation
import Testing
@testable import Calen

struct EveningCorrectionLedgerTests {
    @Test
    func writesOneRecordPerReviewDate() throws {
        let suiteName = "EveningCorrectionLedgerTests-\(#function)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let ledger = EveningCorrectionLedger(defaults: defaults)
        let startedAt = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21))

        ledger.recordStarted(reviewDateKey: "2026-05-04", startedAt: startedAt, applyMode: .manual)
        ledger.recordResult(
            reviewDateKey: "2026-05-04",
            result: .planned,
            itemCount: 2,
            applyMode: .manual
        )
        ledger.recordStarted(reviewDateKey: "2026-05-04", startedAt: startedAt.addingTimeInterval(600), applyMode: .automatic)

        let records = ledger.allRecords()
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.reviewDateKey == "2026-05-04")
    }

    @Test
    func updatesStatusAfterPlanAndApply() throws {
        let suiteName = "EveningCorrectionLedgerTests-\(#function)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let ledger = EveningCorrectionLedger(defaults: defaults)
        let startedAt = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21))

        ledger.recordStarted(reviewDateKey: "2026-05-04", startedAt: startedAt, applyMode: .manual)
        ledger.recordResult(
            reviewDateKey: "2026-05-04",
            result: .planned,
            itemCount: 3,
            applyMode: .manual
        )

        var planned = try #require(ledger.record(for: "2026-05-04"))
        #expect(planned.result == .planned)
        #expect(planned.itemCount == 3)
        #expect(planned.applyMode == .manual)

        ledger.recordResult(
            reviewDateKey: "2026-05-04",
            result: .applied,
            itemCount: 3,
            applyMode: .automatic
        )

        planned = try #require(ledger.record(for: "2026-05-04"))
        #expect(planned.result == .applied)
        #expect(planned.itemCount == 3)
        #expect(planned.applyMode == .automatic)
    }

    @Test
    func preservesFailureReasonWithoutPersistingRawTitles() throws {
        let suiteName = "EveningCorrectionLedgerTests-\(#function)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let ledger = EveningCorrectionLedger(defaults: defaults)

        ledger.recordStarted(
            reviewDateKey: "2026-05-04",
            startedAt: try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21)),
            applyMode: .automatic
        )
        ledger.recordFailure(
            reviewDateKey: "2026-05-04",
            itemCount: 1,
            applyMode: .automatic,
            failureReason: #"Failed to apply event "Therapy with Dr. Kim" because calendar write timed out for title "Private Journal Review""#
        )

        let record = try #require(ledger.record(for: "2026-05-04"))
        #expect(record.result == .failed)
        #expect(record.failureReason == "calendar write timed out")
        #expect(!(record.failureReason ?? "").contains("Therapy with Dr. Kim"))
        #expect(!(record.failureReason ?? "").contains("Private Journal Review"))
    }

    @Test
    func survivesUserDefaultsRoundTrip() throws {
        let suiteName = "EveningCorrectionLedgerTests-\(#function)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let startedAt = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21))

        do {
            let ledger = EveningCorrectionLedger(defaults: defaults)
            ledger.recordStarted(reviewDateKey: "2026-05-04", startedAt: startedAt, applyMode: .manual)
            ledger.recordResult(
                reviewDateKey: "2026-05-04",
                result: .skipped,
                itemCount: 0,
                applyMode: .manual,
                failureReason: "no eligible overdue items"
            )
        }

        let reloadedLedger = EveningCorrectionLedger(defaults: defaults)
        let record = try #require(reloadedLedger.record(for: "2026-05-04"))
        #expect(record.startedAt == startedAt)
        #expect(record.result == .skipped)
        #expect(record.itemCount == 0)
        #expect(record.failureReason == "no eligible overdue items")
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }
}
