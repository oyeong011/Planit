import Foundation
#if os(macOS)
import AppKit
#endif

#if os(macOS)
private extension String {
    /// 쉘 명령어에서 안전하게 사용하기 위해 경로를 이스케이프합니다.
    var shellEscaped: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
#endif

// MARK: - LanguageManager

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var currentLanguageCode: String

    struct SupportedLanguage: Identifiable {
        let id: String       // BCP-47 code
        let displayName: String
        let localName: String
    }

    static let supported: [SupportedLanguage] = [
        .init(id: "en",      displayName: "English",                localName: "English"),
        .init(id: "ko",      displayName: "Korean",                 localName: "한국어"),
        .init(id: "ja",      displayName: "Japanese",               localName: "日本語"),
        .init(id: "zh-Hans", displayName: "Chinese (Simplified)",   localName: "中文(简体)"),
        .init(id: "zh-Hant", displayName: "Chinese (Traditional)",  localName: "中文(繁體)"),
        .init(id: "es",      displayName: "Spanish",                localName: "Español"),
        .init(id: "fr",      displayName: "French",                 localName: "Français"),
        .init(id: "de",      displayName: "German",                 localName: "Deutsch"),
        .init(id: "pt-BR",   displayName: "Portuguese (Brazil)",    localName: "Português (BR)"),
        .init(id: "it",      displayName: "Italian",                localName: "Italiano"),
        .init(id: "ru",      displayName: "Russian",                localName: "Русский"),
        .init(id: "ar",      displayName: "Arabic",                 localName: "العربية"),
        .init(id: "hi",      displayName: "Hindi",                  localName: "हिन्दी"),
        .init(id: "th",      displayName: "Thai",                   localName: "ภาษาไทย"),
        .init(id: "vi",      displayName: "Vietnamese",             localName: "Tiếng Việt"),
        .init(id: "id",      displayName: "Indonesian",             localName: "Bahasa Indonesia"),
        .init(id: "tr",      displayName: "Turkish",                localName: "Türkçe"),
        .init(id: "pl",      displayName: "Polish",                 localName: "Polski"),
        .init(id: "nl",      displayName: "Dutch",                  localName: "Nederlands"),
        .init(id: "sv",      displayName: "Swedish",                localName: "Svenska"),
        .init(id: "da",      displayName: "Danish",                 localName: "Dansk"),
        .init(id: "fi",      displayName: "Finnish",                localName: "Suomi"),
        .init(id: "uk",      displayName: "Ukrainian",              localName: "Українська"),
        .init(id: "cs",      displayName: "Czech",                  localName: "Čeština"),
        .init(id: "ro",      displayName: "Romanian",               localName: "Română"),
        .init(id: "hu",      displayName: "Hungarian",              localName: "Magyar"),
        .init(id: "el",      displayName: "Greek",                  localName: "Ελληνικά"),
        .init(id: "he",      displayName: "Hebrew",                 localName: "עברית"),
        .init(id: "ms",      displayName: "Malay",                  localName: "Bahasa Melayu"),
    ]

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first
        let systemCode = Locale.current.language.languageCode?.identifier ?? "en"
        self.currentLanguageCode = saved ?? systemCode
    }

    /// 언어를 변경하고 앱을 재시작합니다.
    /// macOS: 즉시 재시작 / iOS: 다음 앱 실행 시 적용
    func setLanguage(_ code: String) {
        guard LanguageManager.supported.contains(where: { $0.id == code }) else { return }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        relaunch()
    }

    private func relaunch() {
        #if os(macOS)
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \(path.shellEscaped)"]
        let launched = (try? task.run()) != nil
        if launched {
            exit(0)
        } else {
            NSApp.terminate(nil)
        }
        #else
        // iOS: 언어 변경은 다음 앱 실행 시 적용됩니다.
        // 즉시 재시작이 필요하면 앱을 직접 종료 후 재실행하세요.
        #endif
    }
}
