import Foundation
import Testing
@testable import Calen

@Test func calendarThemeBuiltIns_areStableAndComplete() {
    let themes = CalendarTheme.builtIn

    #expect(themes.count == 14)
    #expect(themes.map(\.id) == [
        "classic",
        "ocean",
        "sunset",
        "forest",
        "mono",
        "sakura",
        "pantone-classic-blue",
        "pantone-illuminating",
        "pantone-ultimate-gray",
        "pantone-very-peri",
        "pantone-viva-magenta",
        "pantone-peach-fuzz",
        "pantone-mocha-mousse",
        "pantone-cloud-dancer"
    ])
    #expect(Set(themes.map(\.id)).count == themes.count)

    for theme in themes {
        #expect(theme.swatchHexes.count == 5)
        #expect(theme.swatchHexes.allSatisfy { $0.hasPrefix("#") && $0.count == 7 })
    }
}

@Test func pantoneThemePrimaryColors_matchColorOfTheYearValues() {
    let primaryHexById = Dictionary(uniqueKeysWithValues: CalendarTheme.builtIn.map { ($0.id, $0.primaryHex) })

    #expect(primaryHexById["pantone-classic-blue"] == "#0F4C81")
    #expect(primaryHexById["pantone-illuminating"] == "#F5DF4D")
    #expect(primaryHexById["pantone-ultimate-gray"] == "#939597")
    #expect(primaryHexById["pantone-very-peri"] == "#6667AB")
    #expect(primaryHexById["pantone-viva-magenta"] == "#BB2649")
    #expect(primaryHexById["pantone-peach-fuzz"] == "#FFBE98")
    #expect(primaryHexById["pantone-mocha-mousse"] == "#A47864")
    #expect(primaryHexById["pantone-cloud-dancer"] == "#F0EEE9")
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
