import Combine
import Foundation

enum WalkingAnimalStyle: String, CaseIterable, Identifiable {
    case cat
    case dog
    case fox
    case penguin
    case hamster
    case rabbit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cat:     return "고양이"
        case .dog:     return "강아지"
        case .fox:     return "여우"
        case .penguin: return "펭귄"
        case .hamster: return "햄스터"
        case .rabbit:  return "토끼"
        }
    }

    var frameCount: Int {
        switch self {
        case .hamster, .penguin: return 9
        case .cat, .dog, .fox, .rabbit:
            return 8
        }
    }

    var spriteSubdirectory: String {
        switch self {
        case .cat, .dog: return "CatSprites"
        case .fox, .penguin, .hamster, .rabbit: return "Animals"
        }
    }

    func frameResourceName(for index: Int) -> String {
        let safeIndex = max(0, min(index, frameCount - 1))
        switch self {
        case .cat:
            return "cat_pixel_R\(safeIndex + 1)"
        case .dog:
            return "character_dog_R\(safeIndex + 1)"
        case .fox, .penguin, .hamster, .rabbit:
            break
        }
        return "animal_\(rawValue)_frame_\(String(format: "%02d", safeIndex))"
    }
}

@MainActor
final class AnimalSettings: ObservableObject {
    static let shared = AnimalSettings()
    static let enabledKey = "planit.catEnabled"
    static let styleKey = "planit.catStyle"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var selectedStyle: WalkingAnimalStyle

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isEnabled = userDefaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let savedStyle = userDefaults.string(forKey: Self.styleKey).flatMap(WalkingAnimalStyle.init(rawValue:))
        self.selectedStyle = savedStyle ?? .cat
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
}
