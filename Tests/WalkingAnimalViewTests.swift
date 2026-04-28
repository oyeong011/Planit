import CoreGraphics
import Foundation
import Testing
@testable import Calen

@Suite("WalkingAnimalView")
struct WalkingAnimalViewTests {
    @Test("animal styles are the requested selectable set")
    func animalStylesAreStable() {
        #expect(WalkingAnimalStyle.allCases.map(\.id) == [
            "fox",
            "penguin",
            "hamster",
            "rabbit"
        ])
        #expect(WalkingAnimalStyle.allCases.map(\.title) == [
            "여우",
            "펭귄",
            "햄스터",
            "토끼"
        ])
    }

    @Test("movement and sprite cadence are decoupled")
    func movementAndSpriteCadenceAreDecoupled() {
        var state = WalkingAnimalView.MotionState(
            xPos: 6,
            isMovingRight: true,
            frameIndex: 0,
            frameElapsed: 0
        )

        state = WalkingAnimalView.advancedState(from: state, totalWidth: 200, frameCount: 8)
        #expect(state.xPos > 6)
        #expect(state.frameIndex == 0)

        state = WalkingAnimalView.advancedState(from: state, totalWidth: 200, frameCount: 8)
        #expect(state.frameIndex == 0)

        state = WalkingAnimalView.advancedState(from: state, totalWidth: 200, frameCount: 8)
        #expect(state.frameIndex == 1)
    }

    @Test("movement reflects at boundaries")
    func movementReflectsAtBoundary() {
        let totalWidth: CGFloat = 200
        let maxX = totalWidth - 56 - 6
        let start = WalkingAnimalView.MotionState(
            xPos: maxX - 0.5,
            isMovingRight: true,
            frameIndex: 7,
            frameElapsed: 0
        )

        let edge = WalkingAnimalView.advancedState(from: start, totalWidth: totalWidth, frameCount: 8)

        #expect(edge.xPos == maxX)
        #expect(edge.isMovingRight == false)
    }
}

@MainActor
@Test func animalSettings_defaultsToEnabledFox() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    #expect(settings.isEnabled == true)
    #expect(settings.selectedStyle == .fox)
}

@MainActor
@Test func animalSettings_persistsSelectedStyle() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    settings.selectStyle(.rabbit)

    #expect(settings.selectedStyle == .rabbit)
    #expect(defaults.string(forKey: AnimalSettings.styleKey) == "rabbit")
}

private func makeAnimalDefaults() -> UserDefaults {
    let suiteName = "AnimalSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
