import CoreGraphics
import Testing
@testable import Calen

@Suite("WalkingCatView")
struct WalkingCatViewTests {
    @Test("position updates every tick while sprite frames advance at 12fps cadence")
    func movementAndSpriteCadenceAreDecoupled() {
        var state = WalkingCatView.MotionState(
            xPos: 6,
            isMovingRight: true,
            frameIndex: 0,
            frameElapsed: 0
        )

        state = WalkingCatView.advancedState(from: state, totalWidth: 200)
        #expect(state.xPos > 6)
        #expect(state.frameIndex == 0)

        state = WalkingCatView.advancedState(from: state, totalWidth: 200)
        #expect(state.frameIndex == 0)

        state = WalkingCatView.advancedState(from: state, totalWidth: 200)
        #expect(state.frameIndex == 1)

        state = WalkingCatView.advancedState(from: state, totalWidth: 200)
        #expect(state.frameIndex == 1)

        state = WalkingCatView.advancedState(from: state, totalWidth: 200)
        #expect(state.frameIndex == 2)
    }

    @Test("movement still clamps to boundaries and flips direction")
    func movementClampsAndTurnsAround() {
        let start = WalkingCatView.MotionState(
            xPos: 149,
            isMovingRight: true,
            frameIndex: 7,
            frameElapsed: 0
        )

        let state = WalkingCatView.advancedState(from: start, totalWidth: 200)

        #expect(state.xPos == 150)
        #expect(state.isMovingRight == false)
        #expect(state.frameIndex == 7)
    }
}
