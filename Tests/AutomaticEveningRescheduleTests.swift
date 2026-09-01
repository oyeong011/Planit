import Foundation
import Testing
@testable import Calen

@MainActor
struct AutomaticEveningRescheduleTests {
    @Test
    func automaticEveningReschedule_skipsBeforeReviewWindowWithoutLedgerRecord() throws {
        let calendar = makeCalendar()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 20, calendar: calendar))
        let context = makeContext(autoApply: false)

        let run = context.service.beginAutomaticEveningCorrection(
            lastRunKey: "",
            now: now,
            calendar: calendar
        )

        #expect(run == nil)
        #expect(context.ledger.record(for: "2026-05-04") == nil)
    }

    @Test
    func automaticEveningReschedule_recordsPlannedResultWithinWindow() throws {
        let calendar = makeCalendar()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21, calendar: calendar))
        let context = makeContext(autoApply: false)

        let run = try #require(context.service.beginAutomaticEveningCorrection(
            lastRunKey: "",
            now: now,
            calendar: calendar
        ))
        let started = try #require(context.ledger.record(for: run.reviewDateKey))
        #expect(started.result == .started)

        let outcome = context.service.completeAutomaticEveningCorrection(
            run,
            itemCount: 2
        )

        #expect(outcome.result == .planned)
        #expect(outcome.shouldBurnDayKey)
        let record = try #require(context.ledger.record(for: run.reviewDateKey))
        #expect(record.result == .planned)
        #expect(record.itemCount == 2)
        #expect(record.applyMode == .manual)
    }

    @Test
    func automaticEveningReschedule_recordsSkippedWhenPlanIsEmpty() throws {
        let calendar = makeCalendar()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21, calendar: calendar))
        let context = makeContext(autoApply: false)

        let run = try #require(context.service.beginAutomaticEveningCorrection(
            lastRunKey: "",
            now: now,
            calendar: calendar
        ))

        let outcome = context.service.completeAutomaticEveningCorrection(
            run,
            itemCount: 0
        )

        #expect(outcome.result == .skipped)
        #expect(outcome.shouldBurnDayKey)
        let record = try #require(context.ledger.record(for: run.reviewDateKey))
        #expect(record.result == .skipped)
        #expect(record.itemCount == 0)
        #expect(record.failureReason == "no eligible overdue items")
    }

    @Test
    func automaticEveningReschedule_recordsAppliedWhenAutoApplySucceeds() throws {
        let calendar = makeCalendar()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21, calendar: calendar))
        let context = makeContext(autoApply: true)
        var applyCount = 0

        let run = try #require(context.service.beginAutomaticEveningCorrection(
            lastRunKey: "",
            now: now,
            calendar: calendar
        ))

        let outcome = context.service.completeAutomaticEveningCorrection(
            run,
            itemCount: 2
        ) {
            applyCount += 2
        }

        #expect(applyCount == 2)
        #expect(outcome.result == .applied)
        #expect(outcome.shouldBurnDayKey)
        let record = try #require(context.ledger.record(for: run.reviewDateKey))
        #expect(record.result == .applied)
        #expect(record.itemCount == 2)
        #expect(record.applyMode == .automatic)
    }

    @Test
    func automaticEveningReschedule_retriesAfterFailureWithoutBurningDayKey() throws {
        let calendar = makeCalendar()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21, calendar: calendar))
        let context = makeContext(autoApply: true)

        let firstRun = try #require(context.service.beginAutomaticEveningCorrection(
            lastRunKey: "",
            now: now,
            calendar: calendar
        ))
        let failed = context.service.completeAutomaticEveningCorrection(
            firstRun,
            itemCount: 1
        ) {
            throw TestFailure.interrupted
        }

        #expect(failed.result == .failed)
        #expect(!failed.shouldBurnDayKey)
        #expect(context.ledger.record(for: firstRun.reviewDateKey)?.result == .failed)

        let secondRun = try #require(context.service.beginAutomaticEveningCorrection(
            lastRunKey: "",
            now: now,
            calendar: calendar
        ))
        let succeeded = context.service.completeAutomaticEveningCorrection(
            secondRun,
            itemCount: 1
        )

        #expect(secondRun.reviewDateKey == firstRun.reviewDateKey)
        #expect(succeeded.result == .applied)
        #expect(succeeded.shouldBurnDayKey)
        #expect(context.ledger.record(for: secondRun.reviewDateKey)?.result == .applied)
    }

    private func makeContext(autoApply: Bool) -> (service: ReviewService, ledger: EveningCorrectionLedger, defaults: UserDefaults) {
        let suiteName = "AutomaticEveningRescheduleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let ledger = EveningCorrectionLedger(defaults: defaults)
        let goalService = GoalService()
        var profile = UserProfile()
        profile.onboardingDone = true
        profile.eveningReviewHour = 21
        profile.eveningReviewAutoApply = autoApply
        goalService.profile = profile

        let service = ReviewService(
            goalService: goalService,
            calendarService: nil,
            eveningCorrectionLedger: ledger
        )
        return (service, ledger, defaults)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }

    private enum TestFailure: LocalizedError {
        case interrupted

        var errorDescription: String? {
            switch self {
            case .interrupted:
                return "automatic evening correction interrupted"
            }
        }
    }
}
