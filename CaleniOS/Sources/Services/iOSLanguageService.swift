#if os(iOS)
import Foundation
import SwiftUI

// MARK: - iOSLanguageService
//
// v0.1.2 앱 내 언어 선택기. UserDefaults에 `AppleLanguages` override 를 저장하되,
// 실행 중 즉시 반영은 `@Environment(\.locale, …)` 주입으로 달성. 앱 재시작 시에도
// `AppleLanguages` override 로 시스템 언어 → 앱 언어 fallback.
//
// 지원 언어: 한국어(ko), 영어(en). 시스템 언어에 따라 첫 실행 기본값 자동 선택.

enum AppLanguage: String, CaseIterable, Identifiable {
    case ko
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        }
    }

    static var systemDefault: AppLanguage {
        let pref = Locale.preferredLanguages.first ?? "en"
        if pref.hasPrefix("ko") { return .ko }
        return .en
    }
}

@MainActor
final class iOSLanguageService: ObservableObject {

    static let shared = iOSLanguageService()
    static let userDefaultsKey = "calen.ios.language"

    @Published private(set) var current: AppLanguage

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.userDefaultsKey),
           let lang = AppLanguage(rawValue: raw) {
            self.current = lang
        } else {
            self.current = AppLanguage.systemDefault
        }
    }

    func select(_ language: AppLanguage) {
        current = language
        defaults.set(language.rawValue, forKey: Self.userDefaultsKey)
        // AppleLanguages override — 앱 재시작 후에도 유지.
        // 주의: iOS는 이 값으로 Bundle.main 의 `localizedString(forKey:)` 해석을 바꾼다.
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
}
#endif
