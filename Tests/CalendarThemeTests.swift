import Foundation
import Testing
@testable import Calen

@Test func calendarThemeBuiltIns_areStableAndComplete() {
    let themes = CalendarTheme.builtIn

    #expect(themes.count == 6)
    #expect(themes.map(\.id) == ["classic", "ocean", "sunset", "forest", "mono", "sakura"])
    #expect(Set(themes.map(\.id)).count == themes.count)

    for theme in themes {
        #expect(theme.swatchHexes.count == 5)
        #expect(theme.swatchHexes.allSatisfy { $0.hasPrefix("#") && $0.count == 7 })
    }
}

@MainActor
@Test func calendarThemeService_usesClassicWhenNoThemeIsSaved() {
    let defaults = makeThemeDefaults()
    let service = CalendarThemeService(userDefaults: defaults)

    #expect(service.current.id == "classic")
    #expect(service.current.primaryHex == "#3F5EFB")
}

@MainActor
@Test func calendarThemeService_persistsSelectedTheme() {
    let defaults = makeThemeDefaults()
    let service = CalendarThemeService(userDefaults: defaults)

    service.selectTheme(id: "forest")

    #expect(service.current.id == "forest")
    #expect(defaults.string(forKey: CalendarThemeService.userDefaultsKey) == "forest")

    let restored = CalendarThemeService(userDefaults: defaults)
    #expect(restored.current.id == "forest")
}

@MainActor
@Test func calendarThemeService_fallsBackToClassicForUnknownSavedTheme() {
    let defaults = makeThemeDefaults()
    defaults.set("missing-theme", forKey: CalendarThemeService.userDefaultsKey)

    let service = CalendarThemeService(userDefaults: defaults)

    #expect(service.current.id == "classic")
}

private func makeThemeDefaults() -> UserDefaults {
    let suiteName = "CalendarThemeTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
