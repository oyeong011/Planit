import CoreGraphics
import Foundation
import AppKit
import Testing
@testable import Calen

@Suite("WalkingAnimalView")
struct WalkingAnimalViewTests {
    @Test("animal styles are the requested selectable set")
    func animalStylesAreStable() {
        #expect(WalkingAnimalStyle.allCases.map(\.id) == [
            "cat",
            "dog",
            "cheetah",
            "duck",
            "fox",
            "penguin",
            "hamster",
            "rabbit"
        ])
        #expect(WalkingAnimalStyle.allCases.map(\.title) == [
            "고양이",
            "강아지",
            "치타",
            "오리",
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

    @Test("walking animal uses optimized AppKit layer animation")
    func walkingAnimalUsesOptimizedLayerAnimation() throws {
        let source = try projectFile("Planit/Views/WalkingAnimalView.swift")

        #expect(!source.contains("Timer.publish"),
                "WalkingAnimalView must not use a SwiftUI Timer publisher because it invalidates the larger popover layout every tick.")
        #expect(!source.contains("@State private var xPos"),
                "Per-frame position must stay inside the AppKit animation view, not SwiftUI state.")
        #expect(source.contains("NSViewRepresentable"),
                "WalkingAnimalView should render through an AppKit view so animation does not re-render SwiftUI.")
        #expect(source.contains(".calenPopoverDidClose"),
                "The animal animation timer must stop when the popover closes.")
        #expect(source.contains(".calenPopoverWillShow"),
                "The animal animation timer must restart when the popover opens.")
        #expect(source.contains("magnificationFilter = .nearest"))
        #expect(source.contains("minificationFilter = .nearest"))
        #expect(source.components(separatedBy: "Timer(timeInterval:").count - 1 == 1,
                "Parade mode must share one timer for all animals.")
    }

    @Test("walking animal speed uses the restored faster default")
    func walkingAnimalUsesFasterDefaultSpeed() {
        #expect(WalkingAnimalView.speed == 90)
    }

    @Test("pet parade returns capped visible styles")
    func petParadeReturnsCappedVisibleStyles() {
        #expect(WalkingAnimalView.visibleStyles(
            selectedStyle: .dog,
            displayMode: .parade,
            paradeCount: 99
        ).count == 3)

        #expect(WalkingAnimalView.visibleStyles(
            selectedStyle: .dog,
            displayMode: .parade,
            paradeCount: -2
        ).count == 1)
    }

    @Test("all exposed animals use eight normalized CatSprites frames")
    func allExposedAnimalsUseNormalizedCatSpriteFrames() throws {
        for style in WalkingAnimalStyle.allCases {
            #expect(style.frameCount == 8)
            #expect(style.spriteSubdirectory == "CatSprites")

            for frameIndex in 0..<style.frameCount {
                let frameName = style.frameResourceName(for: frameIndex)
                let image = try #require(AnimalSpriteImageCache.shared.image(named: frameName, subdirectory: style.spriteSubdirectory))
                #expect(image.size == NSSize(width: 56, height: 56), "\(style.id) frame \(frameIndex) must be 56x56")

                let retina = try #require(AnimalSpriteImageCache.shared.image(named: "\(frameName)@2x", subdirectory: style.spriteSubdirectory))
                let cgImage = try #require(retina.cgImage(forProposedRect: nil, context: nil, hints: nil))
                #expect(cgImage.width == 112, "\(style.id) frame \(frameIndex) @2x must be 112px wide")
                #expect(cgImage.height == 112, "\(style.id) frame \(frameIndex) @2x must be 112px tall")
            }
        }
    }

    @Test("rendered animal frames are cached per backing scale")
    func renderedAnimalFramesAreCachedPerBackingScale() throws {
        let cache = AnimalSpriteImageCache.shared
        let first = cache.renderedFrames(style: .penguin, prefersRetina: true)
        let second = cache.renderedFrames(style: .penguin, prefersRetina: true)
        let standard = cache.renderedFrames(style: .penguin, prefersRetina: false)

        #expect(first.count == WalkingAnimalStyle.penguin.frameCount)
        #expect(second.count == first.count)
        #expect(standard.count == first.count)
        for index in first.indices {
            #expect(first[index] === second[index])
        }
    }
}

@MainActor
@Test func animalSettings_defaultsToEnabledCat() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    #expect(settings.isEnabled == true)
    #expect(settings.selectedStyle == .cat)
    #expect(settings.displayMode == .selected)
    #expect(settings.paradeCount == 3)
}

@MainActor
@Test func animalSettings_persistsSelectedStyle() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    settings.selectStyle(.rabbit)

    #expect(settings.selectedStyle == .rabbit)
    #expect(defaults.string(forKey: AnimalSettings.styleKey) == "rabbit")
}

@MainActor
@Test func animalSettings_mapsLegacyCatStylesToCat() {
    for legacyValue in ["original", "pixel"] {
        let defaults = makeAnimalDefaults()
        defaults.set(legacyValue, forKey: AnimalSettings.styleKey)

        let settings = AnimalSettings(userDefaults: defaults)

        #expect(settings.selectedStyle == .cat)
    }
}

@MainActor
@Test func animalSettings_persistsDisplayModeAndParadeCount() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    settings.setDisplayMode(.parade)
    settings.setParadeCount(2)
    settings.setParadeCount(99)

    #expect(settings.displayMode == .parade)
    #expect(defaults.string(forKey: AnimalSettings.displayModeKey) == "parade")
    #expect(settings.paradeCount == 3)
    #expect(defaults.integer(forKey: AnimalSettings.paradeCountKey) == 3)

    settings.setParadeCount(-2)
    #expect(settings.paradeCount == 1)
    #expect(defaults.integer(forKey: AnimalSettings.paradeCountKey) == 1)
}

@MainActor
@Test func animalSettings_ignoresNoopParadeCountWrites() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    settings.setParadeCount(3)

    #expect(settings.paradeCount == 3)
    #expect(defaults.object(forKey: AnimalSettings.paradeCountKey) == nil)
}

private func makeAnimalDefaults() -> UserDefaults {
    let suiteName = "AnimalSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func projectFile(_ path: String) throws -> String {
    try String(
        contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path),
        encoding: .utf8
    )
}
