import AppKit
import Combine
import SwiftUI

/// 사용자 선택에 따라 앱 외관(시스템/라이트/다크)을 관리한다.
/// NSApp.appearance를 조절해 팝오버 내부 SwiftUI가 상속받도록 한다.
@MainActor
final class AppearanceService: ObservableObject {
    static let shared = AppearanceService()

    enum Mode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return String(localized: "settings.appearance.mode.system")
            case .light:  return String(localized: "settings.appearance.mode.light")
            case .dark:   return String(localized: "settings.appearance.mode.dark")
            }
        }

        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light:  return "sun.max.fill"
            case .dark:   return "moon.fill"
            }
        }
    }

    private static let key = "planit.appearance.mode"

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
            apply()
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key).flatMap(Mode.init(rawValue:)) ?? .system
        self.mode = saved
        apply()
    }

    /// AppDelegate 시작 시점에 호출해 초기 appearance를 반영한다.
    func bootstrap() { apply() }

    private func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
