import Combine
import Foundation

enum WalkingAnimalStyle: String, CaseIterable, Identifiable {
    case cat
    case dog
    case cheetah
    case duck
    case rabbit
    case panda
    case turtle
    case squirrel

    var id: String { rawValue }

    var title: String {
        NSLocalizedString("settings.animal.style.\(rawValue)", bundle: .module, comment: "")
    }

    var frameCount: Int {
        8
    }

    var spriteSubdirectory: String {
        "CatSprites"
    }

    func frameResourceName(for index: Int) -> String {
        let safeIndex = max(0, min(index, frameCount - 1))
        switch self {
        case .cat:
            return "cat_pixel_R\(safeIndex + 1)"
        case .dog:
            return "character_dog_R\(safeIndex + 1)"
        case .cheetah, .duck, .rabbit, .panda, .turtle, .squirrel:
            return "character_\(rawValue)_R\(safeIndex + 1)"
        }
    }

    static var randomPool: [WalkingAnimalStyle] {
        allCases
    }

    static func persistedStyle(from rawValue: String?) -> WalkingAnimalStyle? {
        guard let rawValue else { return nil }
        if rawValue == "original" || rawValue == "pixel" {
            return .cat
        }
        return WalkingAnimalStyle(rawValue: rawValue)
    }
}

enum WalkingPetDisplayMode: String, CaseIterable, Identifiable {
    case selected
    case random
    case parade

    var id: String { rawValue }

    var title: String {
        NSLocalizedString("settings.animal.display.\(rawValue)", bundle: .module, comment: "")
    }
}

@MainActor
final class AnimalSettings: ObservableObject {
    static let shared = AnimalSettings()
    static let enabledKey = "planit.catEnabled"
    static let styleKey = "planit.catStyle"
    static let displayModeKey = "planit.petDisplayMode"
    static let paradeCountKey = "planit.petParadeCount"
    static let paradeCountRange = 1...3

    @Published private(set) var isEnabled: Bool
    @Published private(set) var selectedStyle: WalkingAnimalStyle
    @Published private(set) var displayMode: WalkingPetDisplayMode
    @Published private(set) var paradeCount: Int

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isEnabled = userDefaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let savedStyle = WalkingAnimalStyle.persistedStyle(from: userDefaults.string(forKey: Self.styleKey))
        self.selectedStyle = savedStyle ?? .cat
        let savedMode = userDefaults.string(forKey: Self.displayModeKey).flatMap(WalkingPetDisplayMode.init(rawValue:))
        self.displayMode = savedMode ?? .selected
        let savedParadeCount = userDefaults.object(forKey: Self.paradeCountKey) as? Int ?? 3
        self.paradeCount = Self.clampedParadeCount(savedParadeCount)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        userDefaults.set(enabled, forKey: Self.enabledKey)
    }

    func selectStyle(_ style: WalkingAnimalStyle) {
        guard selectedStyle != style else { return }
        selectedStyle = style
        userDefaults.set(style.rawValue, forKey: Self.styleKey)
    }

    func setDisplayMode(_ mode: WalkingPetDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.displayModeKey)
    }

    func setParadeCount(_ count: Int) {
        let clamped = Self.clampedParadeCount(count)
        guard paradeCount != clamped else { return }
        paradeCount = clamped
        userDefaults.set(clamped, forKey: Self.paradeCountKey)
    }

    static func clampedParadeCount(_ count: Int) -> Int {
        min(max(count, paradeCountRange.lowerBound), paradeCountRange.upperBound)
    }
}
