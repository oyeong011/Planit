import Combine
import Foundation

enum WalkingAnimalStyle: String, CaseIterable, Identifiable {
    case cat
    case dog
    case cheetah
    case duck
    case rabbit
    case monkey
    case sheep
    case pig
    case cow
    case deer
    case bear
    case koala
    case hedgehog
    case owl
    case frog
    case elephant
    case horse
    case fox

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
        default:
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
        if ["panda", "turtle", "squirrel"].contains(rawValue) {
            return .cat
        }
        return WalkingAnimalStyle(rawValue: rawValue)
    }
}

enum WalkingAnimalCategory: String, CaseIterable, Identifiable {
    case all
    case basic
    case farm
    case forest

    var id: String { rawValue }

    var title: String {
        NSLocalizedString("settings.animal.category.\(rawValue)", bundle: .module, comment: "")
    }

    var styles: [WalkingAnimalStyle] {
        switch self {
        case .all:
            return WalkingAnimalStyle.allCases
        case .basic:
            return [.cat, .dog, .cheetah, .duck, .rabbit, .monkey]
        case .farm:
            return [.sheep, .pig, .cow, .horse]
        case .forest:
            return [.deer, .bear, .koala, .hedgehog, .owl, .frog, .elephant, .fox]
        }
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
    static let paradeStylesKey = "planit.petParadeStyles"
    static var paradeCountRange: ClosedRange<Int> { 1...WalkingAnimalStyle.allCases.count }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var selectedStyle: WalkingAnimalStyle
    @Published private(set) var displayMode: WalkingPetDisplayMode
    @Published private(set) var paradeCount: Int
    @Published private(set) var selectedParadeStyles: [WalkingAnimalStyle]

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isEnabled = userDefaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let savedStyle = WalkingAnimalStyle.persistedStyle(from: userDefaults.string(forKey: Self.styleKey))
        self.selectedStyle = savedStyle ?? .cat
        let savedMode = userDefaults.string(forKey: Self.displayModeKey).flatMap(WalkingPetDisplayMode.init(rawValue:))
        self.displayMode = savedMode ?? .selected
        let savedParadeStyles = Self.persistedParadeStyles(
            from: userDefaults.stringArray(forKey: Self.paradeStylesKey),
            legacyCount: userDefaults.object(forKey: Self.paradeCountKey) as? Int,
            fallback: savedStyle ?? .cat
        )
        self.selectedParadeStyles = savedParadeStyles
        self.paradeCount = savedParadeStyles.count
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
        let availableStyles = Self.normalizedParadeStyles(selectedParadeStyles + WalkingAnimalStyle.allCases)
        setParadeStyles(Array(availableStyles.prefix(clamped)))
    }

    func toggleParadeStyle(_ style: WalkingAnimalStyle) {
        var next = selectedParadeStyles

        if let index = next.firstIndex(of: style) {
            guard next.count > 1 else { return }
            next.remove(at: index)
        } else {
            next.append(style)
        }

        setParadeStyles(next)
    }

    private func setParadeStyles(_ styles: [WalkingAnimalStyle]) {
        let normalized = Self.normalizedParadeStyles(styles)
        guard selectedParadeStyles != normalized else { return }
        selectedParadeStyles = normalized
        paradeCount = normalized.count
        userDefaults.set(normalized.map(\.rawValue), forKey: Self.paradeStylesKey)
        userDefaults.set(normalized.count, forKey: Self.paradeCountKey)
    }

    static func clampedParadeCount(_ count: Int) -> Int {
        min(max(count, paradeCountRange.lowerBound), paradeCountRange.upperBound)
    }

    private static func persistedParadeStyles(
        from rawValues: [String]?,
        legacyCount: Int?,
        fallback: WalkingAnimalStyle
    ) -> [WalkingAnimalStyle] {
        if let rawValues {
            return normalizedParadeStyles(rawValues.compactMap(WalkingAnimalStyle.persistedStyle))
        }

        if let legacyCount {
            return normalizedParadeStyles(Array(WalkingAnimalStyle.allCases.prefix(clampedParadeCount(legacyCount))))
        }

        return normalizedParadeStyles([fallback])
    }

    static func normalizedParadeStyles(_ styles: [WalkingAnimalStyle]) -> [WalkingAnimalStyle] {
        var seen: Set<WalkingAnimalStyle> = []
        let unique = styles.filter { style in
            guard !seen.contains(style) else { return false }
            seen.insert(style)
            return true
        }
        return Array((unique.isEmpty ? [.cat] : unique).prefix(paradeCountRange.upperBound))
    }
}
