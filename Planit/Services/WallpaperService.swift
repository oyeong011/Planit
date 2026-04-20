import Foundation

@MainActor
final class WallpaperService: ObservableObject {
    static let shared = WallpaperService()
    static let userDefaultsKey = "planit.wallpaperPresetID"

    let presets: [WallpaperPreset]
    @Published private(set) var activePreset: WallpaperPreset?

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard, presets: [WallpaperPreset] = WallpaperPreset.builtIn) {
        self.userDefaults = userDefaults
        self.presets = presets
        let savedID = userDefaults.string(forKey: Self.userDefaultsKey)
        self.activePreset = presets.first { $0.id == savedID }
    }

    func select(_ preset: WallpaperPreset?) {
        activePreset = preset
        if let preset {
            userDefaults.set(preset.id, forKey: Self.userDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: Self.userDefaultsKey)
        }
    }

    var isActive: Bool { activePreset != nil }
}
