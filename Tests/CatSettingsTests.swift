import Foundation
import Testing
@testable import Calen

@MainActor
@Test func catSettings_defaultsToEnabledWithOriginalTint() {
    let defaults = makeCatDefaults()
    let settings = CatSettings(userDefaults: defaults)

    #expect(settings.catEnabled == true)
    #expect(settings.catTint == "")
}

@MainActor
@Test func catSettings_persistsEnabledStateAndTint() {
    let defaults = makeCatDefaults()
    let settings = CatSettings(userDefaults: defaults)

    settings.setEnabled(false)
    settings.selectTint("#FF9933")

    #expect(defaults.bool(forKey: CatSettings.enabledKey) == false)
    #expect(defaults.string(forKey: CatSettings.tintKey) == "#FF9933")

    let restored = CatSettings(userDefaults: defaults)
    #expect(restored.catEnabled == false)
    #expect(restored.catTint == "#FF9933")
}

@MainActor
@Test func catSettings_clearsTintBackToOriginal() {
    let defaults = makeCatDefaults()
    let settings = CatSettings(userDefaults: defaults)

    settings.selectTint("#FF7EB6")
    settings.selectTint("")

    #expect(settings.catTint == "")
    #expect(defaults.string(forKey: CatSettings.tintKey) == nil)
}

private func makeCatDefaults() -> UserDefaults {
    let suiteName = "CatSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
