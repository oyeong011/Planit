import Foundation
import SwiftUI

@MainActor
final class CalendarThemeService: ObservableObject {
    static let shared = CalendarThemeService()
    static let userDefaultsKey = "planit.calendar.theme"

    let themes: [CalendarTheme]

    @Published private(set) var current: CalendarTheme

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard, themes: [CalendarTheme] = CalendarTheme.builtIn) {
        self.userDefaults = userDefaults
        self.themes = themes

        let savedID = userDefaults.string(forKey: Self.userDefaultsKey)
        self.current = themes.first { $0.id == savedID } ?? CalendarTheme.fallback
    }

    @discardableResult
    func selectTheme(id: String) -> Bool {
        guard let theme = theme(for: id) else { return false }
        selectTheme(theme)
        return true
    }

    func selectTheme(_ theme: CalendarTheme) {
        current = theme
        userDefaults.set(theme.id, forKey: Self.userDefaultsKey)
    }

    func theme(for id: String) -> CalendarTheme? {
        themes.first { $0.id == id }
    }
}
