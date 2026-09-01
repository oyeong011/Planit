import Foundation
import SwiftUI
import Testing
@testable import Calen

@MainActor
struct TomorrowPlannerServiceTests {
    @Test
    func autoModeKeepsDeniedSyntheticItemAsSuggestionWithoutCalendarWrite() async throws {
        let defaults = try makeDefaults()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 10))

        var profile = UserProfile()
        profile.aggressiveness = .auto

        let goals = TestGoalProvider(profile: profile, now: now)
        let calendar = TestCalendarService(fetchResults: [.success([])])
        let service = TomorrowPlannerService(
            goalProvider: goals,
            calendarService: calendar,
            defaults: defaults,
            now: { now },
            candidateCollector: { _ in
                [
                    PlannedItem(
                        goalId: nil,
                        title: "FocusTime",
                        duration: 30,
                        score: 10,
                        type: .focusQuota,
                        preferredTimeTags: ["AM-Deep"]
                    )
                ]
            }
        )

        await service.generateTomorrowPlan()

        let result = try #require(service.lastResult)
        #expect(calendar.createRequests.isEmpty)
        #expect(result.created.isEmpty)
        #expect(result.suggested.map(\.title) == ["FocusTime"])
        #expect((result.error ?? "").contains("캘린더에 쓰지 않고"))
    }

    @Test
    func goalBackedCarryoverStillAutoCreatesWhenPolicyAllowsIt() async throws {
        let defaults = try makeDefaults()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 10))

        var profile = UserProfile()
        profile.aggressiveness = .auto

        let goal = Goal(
            id: "goal-1",
            level: .week,
            title: "Prepare demo",
            dueDate: try #require(makeDate(year: 2026, month: 5, day: 6, hour: 18))
        )
        let completion = CompletionRecord(
            eventId: "carryover-1",
            eventTitle: "Prepare demo",
            goalId: goal.id,
            date: now,
            status: .partial,
            plannedMinutes: 45
        )

        let goals = TestGoalProvider(
            profile: profile,
            goals: [goal],
            completions: [completion.eventId: completion],
            now: now
        )
        let calendar = TestCalendarService(
            fetchResults: [.success([])],
            createdEvent: makeCalendarEvent(
                id: "created-1",
                title: "Prepare demo",
                start: try #require(makeDate(year: 2026, month: 5, day: 5, hour: 9)),
                end: try #require(makeDate(year: 2026, month: 5, day: 5, hour: 9, minute: 45))
            )
        )
        let service = TomorrowPlannerService(
            goalProvider: goals,
            calendarService: calendar,
            defaults: defaults,
            now: { now },
            candidateCollector: { _ in
                [
                    PlannedItem(
                        goalId: goal.id,
                        title: goal.title,
                        duration: 45,
                        score: 20,
                        type: .carryover,
                        preferredTimeTags: ["AM-Deep"]
                    )
                ]
            }
        )

        await service.generateTomorrowPlan()

        let result = try #require(service.lastResult)
        #expect(calendar.createRequests.count == 1)
        #expect(result.created.count == 1)
        #expect(result.suggested.isEmpty)
        #expect(result.created.first?.autoCreated == true)
        #expect(result.error == nil)
    }

    @Test
    func fetchErrorsDoNotMarkPlanDoneAndAllowRetry() async throws {
        let defaults = try makeDefaults()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 10))

        var profile = UserProfile()
        profile.aggressiveness = .auto

        let goal = Goal(
            id: "goal-2",
            level: .week,
            title: "Write report",
            dueDate: try #require(makeDate(year: 2026, month: 5, day: 6, hour: 18))
        )

        let goals = TestGoalProvider(profile: profile, goals: [goal], now: now)
        let calendar = TestCalendarService(
            fetchResults: [.failure(TestError.offline), .success([])],
            createdEvent: makeCalendarEvent(
                id: "created-2",
                title: goal.title,
                start: try #require(makeDate(year: 2026, month: 5, day: 5, hour: 9)),
                end: try #require(makeDate(year: 2026, month: 5, day: 5, hour: 9, minute: 30))
            )
        )
        let service = TomorrowPlannerService(
            goalProvider: goals,
            calendarService: calendar,
            defaults: defaults,
            now: { now },
            candidateCollector: { _ in
                [
                    PlannedItem(
                        goalId: goal.id,
                        title: goal.title,
                        duration: 30,
                        score: 12,
                        type: .deadline,
                        preferredTimeTags: ["AM-Deep"]
                    )
                ]
            }
        )

        await service.generateTomorrowPlan()

        let failedResult = try #require(service.lastResult)
        #expect((failedResult.error ?? "").contains("캘린더 조회 실패"))
        #expect(defaults.string(forKey: "planit.lastPlannedDate") == nil)
        #expect(calendar.createRequests.isEmpty)

        await service.generateTomorrowPlan()

        let retriedResult = try #require(service.lastResult)
        #expect(calendar.createRequests.count == 1)
        #expect(retriedResult.created.count == 1)
        #expect(defaults.string(forKey: "planit.lastPlannedDate") == tomorrowKey(from: now))
    }

    @Test
    func repeatedCallWithSameDateKeyDoesNotDuplicateAllowedCreations() async throws {
        let defaults = try makeDefaults()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 10))

        var profile = UserProfile()
        profile.aggressiveness = .auto

        let goal = Goal(
            id: "goal-3",
            level: .week,
            title: "Review launch checklist",
            dueDate: try #require(makeDate(year: 2026, month: 5, day: 6, hour: 18))
        )

        let goals = TestGoalProvider(profile: profile, goals: [goal], now: now)
        let calendar = TestCalendarService(
            fetchResults: [.success([])],
            createdEvent: makeCalendarEvent(
                id: "created-3",
                title: goal.title,
                start: try #require(makeDate(year: 2026, month: 5, day: 5, hour: 9)),
                end: try #require(makeDate(year: 2026, month: 5, day: 5, hour: 9, minute: 30))
            )
        )
        let service = TomorrowPlannerService(
            goalProvider: goals,
            calendarService: calendar,
            defaults: defaults,
            now: { now },
            candidateCollector: { _ in
                [
                    PlannedItem(
                        goalId: goal.id,
                        title: goal.title,
                        duration: 30,
                        score: 15,
                        type: .deadline,
                        preferredTimeTags: ["AM-Deep"]
                    )
                ]
            }
        )

        await service.generateTomorrowPlan()
        await service.generateTomorrowPlan()

        let result = try #require(service.lastResult)
        #expect(calendar.createRequests.count == 1)
        #expect(result.created.count == 1)
        #expect(defaults.string(forKey: "planit.lastPlannedDate") == tomorrowKey(from: now))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "TomorrowPlannerServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    private func tomorrowKey(from now: Date) -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return GoalService.dateKey(tomorrow)
    }

    private func makeCalendarEvent(id: String, title: String, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            color: .blue,
            isAllDay: false
        )
    }
}

@MainActor
private final class TestGoalProvider: TomorrowPlannerGoalProviding {
    var profile: UserProfile
    var completions: [String: CompletionRecord]
    var goals: [Goal]
    private let now: Date

    init(
        profile: UserProfile,
        goals: [Goal] = [],
        completions: [String: CompletionRecord] = [:],
        now: Date
    ) {
        self.profile = profile
        self.goals = goals
        self.completions = completions
        self.now = now
    }

    func activeGoals() -> [Goal] {
        goals.filter { $0.status == .active }
    }

    func daysUntilDeadline(_ goal: Goal) -> Int {
        Calendar.current.dateComponents([.day], from: now, to: goal.dueDate).day ?? 0
    }
}

@MainActor
private final class TestCalendarService: TomorrowPlannerCalendarServicing {
    struct CreateRequest: Equatable {
        let title: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
    }

    var fetchResults: [Result<[CalendarEvent], Error>]
    var createdEvent: CalendarEvent?
    private(set) var createRequests: [CreateRequest] = []

    init(
        fetchResults: [Result<[CalendarEvent], Error>],
        createdEvent: CalendarEvent? = nil
    ) {
        self.fetchResults = fetchResults
        self.createdEvent = createdEvent
    }

    func fetchEvents(for month: Date) async throws -> [CalendarEvent] {
        guard !fetchResults.isEmpty else { return [] }
        let result = fetchResults.removeFirst()
        return try result.get()
    }

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        recurrence: String?
    ) async throws -> CalendarEvent? {
        createRequests.append(
            CreateRequest(
                title: title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay
            )
        )
        return createdEvent
    }
}

private enum TestError: LocalizedError {
    case offline

    var errorDescription: String? {
        switch self {
        case .offline:
            return "offline"
        }
    }
}
