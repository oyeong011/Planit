#if os(iOS)
import Foundation
import SwiftUI

// MARK: - iOSThemeService
//
// v0.1.2 테마 시스템. 선택된 `CalenTheme`을 `@Published` 로 노출하고
// UserDefaults(`calen.ios.theme`)에 persist. macOS의 `CalendarThemeService`와
// 독립적으로 동작한다(iOS 전용 ID 세트).

@MainActor
final class iOSThemeService: ObservableObject {

    static let shared = iOSThemeService()
    static let userDefaultsKey = "calen.ios.theme"

    let themes: [CalenTheme]

    @Published private(set) var current: CalenTheme

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard,
         themes: [CalenTheme] = CalenTheme.builtIn) {
        self.defaults = defaults
        self.themes = themes
        let savedID = defaults.string(forKey: Self.userDefaultsKey)
        self.current = themes.first { $0.id == savedID } ?? CalenTheme.fallback
    }

    /// 테마를 ID 기반으로 선택. 존재하지 않으면 false.
    @discardableResult
    func select(id: String) -> Bool {
        guard let t = themes.first(where: { $0.id == id }) else { return false }
        current = t
        defaults.set(t.id, forKey: Self.userDefaultsKey)
        return true
    }

    func select(_ theme: CalenTheme) {
        current = theme
        defaults.set(theme.id, forKey: Self.userDefaultsKey)
    }
}
#endif
