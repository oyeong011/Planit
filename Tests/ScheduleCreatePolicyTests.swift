import Foundation
import Testing
@testable import CalenShared

@MainActor
struct ScheduleCreatePolicyTests {

    @Test("AI-invented focus/rest style titles without user backing are denied")
    func deniesSyntheticTitlesWithoutUserBackedSource() {
        let deniedTitles = [
            "FocusTime",
            "휴식 시간",
            "depress time",
            "딥워크 블록"
        ]

        for title in deniedTitles {
            let result = ScheduleCreatePolicy.classify(
                ScheduleCreateRequest(
                    title: title,
                    allowedCreateSources: [],
                    isConfirmed: false
                )
            )

            #expect(result == .denied)
        }
    }

    @Test("an explicit user-requested block needs confirmation before create is allowed")
    func explicitUserRequestedBlockNeedsConfirmation() {
        let result = ScheduleCreatePolicy.classify(
            ScheduleCreateRequest(
                title: "FocusTime",
                allowedCreateSources: [
                    ScheduleCreateSource(kind: .explicitUserRequestedBlock, title: "FocusTime")
                ],
                isConfirmed: false
            )
        )

        #expect(result == .needsConfirmation)
    }

    @Test("the same explicit block request becomes allowed after caller confirmation")
    func explicitUserRequestedBlockBecomesAllowedWhenConfirmed() {
        let result = ScheduleCreatePolicy.classify(
            ScheduleCreateRequest(
                title: "FocusTime",
                allowedCreateSources: [
                    ScheduleCreateSource(kind: .explicitUserRequestedBlock, title: "FocusTime")
                ],
                isConfirmed: true
            )
        )

        #expect(result == .allowed)
    }

    @Test("titles that match existing todo or goal sources are allowed")
    func titleMatchingExistingTodoOrGoalSourceIsAllowed() {
        let sources: [ScheduleCreateSource] = [
            .init(kind: .existingTodo, title: "Finish launch brief"),
            .init(kind: .activeGoal, title: "Write investor update")
        ]

        let todoResult = ScheduleCreatePolicy.classify(
            ScheduleCreateRequest(
                title: "Finish launch brief",
                allowedCreateSources: sources,
                isConfirmed: false
            )
        )
        let goalResult = ScheduleCreatePolicy.classify(
            ScheduleCreateRequest(
                title: "Write investor update",
                allowedCreateSources: sources,
                isConfirmed: false
            )
        )

        #expect(todoResult == .allowed)
        #expect(goalResult == .allowed)
    }

    @Test("explicit user-confirmed blocks and existing events are allowed sources")
    func explicitConfirmedBlocksAndExistingEventsAreAllowed() {
        let confirmedBlock = ScheduleCreatePolicy.classify(
            ScheduleCreateRequest(
                title: "Reserve prep block",
                allowedCreateSources: [
                    ScheduleCreateSource(kind: .explicitUserConfirmedBlock, title: "Reserve prep block")
                ],
                isConfirmed: false
            )
        )
        let existingEvent = ScheduleCreatePolicy.classify(
            ScheduleCreateRequest(
                title: "Doctor Appointment",
                allowedCreateSources: [
                    ScheduleCreateSource(kind: .existingEvent, title: "Doctor Appointment")
                ],
                isConfirmed: false
            )
        )

        #expect(confirmedBlock == .allowed)
        #expect(existingEvent == .allowed)
    }

    @Test("malformed and adversarial titles are denied")
    func deniesMalformedAndAdversarialTitles() {
        let cases = [
            "",
            String(repeating: "a", count: 500),
            "fOcUsTiMe"
        ]

        for title in cases {
            let result = ScheduleCreatePolicy.classify(
                ScheduleCreateRequest(
                    title: title,
                    allowedCreateSources: [],
                    isConfirmed: false
                )
            )

            #expect(result == .denied)
        }
    }
}
