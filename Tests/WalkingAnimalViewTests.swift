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
            "rabbit",
            "monkey",
            "sheep",
            "pig",
            "cow",
            "deer",
            "bear",
            "koala",
            "hedgehog",
            "owl",
            "frog",
            "elephant",
            "horse",
            "fox"
        ])

        for style in WalkingAnimalStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(!style.title.contains("settings.animal"))
        }
        for mode in WalkingPetDisplayMode.allCases {
            #expect(!mode.title.isEmpty)
            #expect(!mode.title.contains("settings.animal"))
        }
        for category in WalkingAnimalCategory.allCases {
            #expect(!category.title.isEmpty)
            #expect(!category.title.contains("settings.animal"))
        }
    }

    @Test("animal categories group existing and expanded styles")
    func animalCategoriesGroupStyles() {
        #expect(WalkingAnimalCategory.basic.styles.map(\.id) == ["cat", "dog", "cheetah", "duck", "rabbit", "monkey"])
        #expect(WalkingAnimalCategory.farm.styles.map(\.id) == ["sheep", "pig", "cow", "horse"])
        #expect(WalkingAnimalCategory.forest.styles.map(\.id) == [
            "deer",
            "bear",
            "koala",
            "hedgehog",
            "owl",
            "frog",
            "elephant",
            "fox"
        ])
        #expect(WalkingAnimalCategory.all.styles == WalkingAnimalStyle.allCases)
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
        #expect(!source.contains("let renderedFrames = AnimalSpriteImageCache.shared.renderedFrames"),
                "Pet rebuilds must not decode and render all frames for every animal synchronously.")
        #expect(source.contains("AnimalSpriteImageCache.shared.renderedFrame"),
                "Animation should render only the frame it is about to display.")
    }

    @Test("settings animal previews load thumbnails lazily")
    func settingsAnimalPreviewsLoadThumbnailsLazily() throws {
        let source = try projectFile("Planit/Views/SettingsView.swift")

        #expect(!source.contains("WalkingAnimalStyle.allCases.compactMap"),
                "Settings must not decode every animal thumbnail before the grid is visible.")
        #expect(source.contains("previewImageCache[style] = image"))
    }

    @Test("walking animal speed uses the restored faster default")
    func walkingAnimalUsesFasterDefaultSpeed() {
        #expect(WalkingAnimalView.speed == 90)
    }

    @Test("pet parade returns selected visible styles")
    func petParadeReturnsSelectedVisibleStyles() {
        #expect(WalkingAnimalView.visibleStyles(
            selectedStyle: .dog,
            displayMode: .parade,
            paradeStyles: [.cat, .rabbit, .duck, .monkey]
        ).map(\.id) == ["cat", "rabbit", "duck", "monkey"])

        #expect(WalkingAnimalView.visibleStyles(
            selectedStyle: .dog,
            displayMode: .parade,
            paradeStyles: []
        ).map(\.id) == ["dog"])
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
        let first = cache.renderedFrames(style: .rabbit, prefersRetina: true)
        let second = cache.renderedFrames(style: .rabbit, prefersRetina: true)
        let standard = cache.renderedFrames(style: .rabbit, prefersRetina: false)

        #expect(first.count == WalkingAnimalStyle.rabbit.frameCount)
        #expect(second.count == first.count)
        #expect(standard.count == first.count)
        for index in first.indices {
            #expect(first[index] === second[index])
        }
    }

    @Test("single rendered animal frames are cached lazily")
    func singleRenderedAnimalFramesAreCachedLazily() throws {
        let cache = AnimalSpriteImageCache.shared
        let first = try #require(cache.renderedFrame(style: .rabbit, frameIndex: 0, prefersRetina: true))
        let second = try #require(cache.renderedFrame(style: .rabbit, frameIndex: 0, prefersRetina: true))
        let standard = try #require(cache.renderedFrame(style: .rabbit, frameIndex: 0, prefersRetina: false))

        #expect(first === second)
        #expect(first !== standard)
    }
}

@MainActor
@Test func animalSettings_defaultsToEnabledCat() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    #expect(settings.isEnabled == true)
    #expect(settings.selectedStyle == .cat)
    #expect(settings.displayMode == .selected)
    #expect(settings.paradeCount == 1)
    #expect(settings.selectedParadeStyles.map(\.id) == ["cat"])
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
@Test func animalSettings_mapsRemovedAnimalStylesToCat() {
    for removedStyle in ["hamster", "penguin", "panda", "turtle", "squirrel"] {
        let defaults = makeAnimalDefaults()
        defaults.set(removedStyle, forKey: AnimalSettings.styleKey)

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
    #expect(settings.paradeCount == WalkingAnimalStyle.allCases.count)
    #expect(defaults.integer(forKey: AnimalSettings.paradeCountKey) == WalkingAnimalStyle.allCases.count)
    #expect(defaults.stringArray(forKey: AnimalSettings.paradeStylesKey) == WalkingAnimalStyle.allCases.map(\.id))

    settings.setParadeCount(-2)
    #expect(settings.paradeCount == 1)
    #expect(defaults.integer(forKey: AnimalSettings.paradeCountKey) == 1)
    #expect(defaults.stringArray(forKey: AnimalSettings.paradeStylesKey) == ["cat"])
}

@MainActor
@Test func animalSettings_persistsMultipleParadeStyles() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    settings.toggleParadeStyle(.dog)
    settings.toggleParadeStyle(.rabbit)

    #expect(settings.selectedParadeStyles.map(\.id) == ["cat", "dog", "rabbit"])
    #expect(defaults.stringArray(forKey: AnimalSettings.paradeStylesKey) == ["cat", "dog", "rabbit"])
    #expect(settings.paradeCount == 3)

    settings.toggleParadeStyle(.dog)
    #expect(settings.selectedParadeStyles.map(\.id) == ["cat", "rabbit"])
    #expect(defaults.stringArray(forKey: AnimalSettings.paradeStylesKey) == ["cat", "rabbit"])
}

@MainActor
@Test func animalSettings_migratesLegacyParadeCountToSelectedStyles() {
    let defaults = makeAnimalDefaults()
    defaults.set(3, forKey: AnimalSettings.paradeCountKey)

    let settings = AnimalSettings(userDefaults: defaults)

        #expect(settings.selectedParadeStyles.map(\.id) == ["cat", "dog", "cheetah"])
    #expect(settings.paradeCount == 3)
}

@MainActor
@Test func animalSettings_keepsOneParadeStyleSelected() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    settings.toggleParadeStyle(.cat)

    #expect(settings.selectedParadeStyles.map(\.id) == ["cat"])
    #expect(defaults.stringArray(forKey: AnimalSettings.paradeStylesKey) == nil)
}

@MainActor
@Test func animalSettings_ignoresNoopParadeCountWrites() {
    let defaults = makeAnimalDefaults()
    let settings = AnimalSettings(userDefaults: defaults)

    settings.setParadeCount(1)

    #expect(settings.paradeCount == 1)
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
