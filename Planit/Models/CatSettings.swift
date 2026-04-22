import Combine
import Foundation

@MainActor
final class CatSettings: ObservableObject {
    static let shared = CatSettings()
    static let enabledKey = "planit.catEnabled"
    static let tintKey = "planit.catTint"

    @Published private(set) var catEnabled: Bool
    @Published private(set) var catTint: String

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.catEnabled = userDefaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.catTint = userDefaults.string(forKey: Self.tintKey) ?? ""
    }

    func setEnabled(_ isEnabled: Bool) {
        guard catEnabled != isEnabled else { return }
        catEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: Self.enabledKey)
    }

    func selectTint(_ hex: String) {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard catTint != normalized else { return }

        catTint = normalized

        if normalized.isEmpty {
            userDefaults.removeObject(forKey: Self.tintKey)
        } else {
            userDefaults.set(normalized, forKey: Self.tintKey)
        }
    }
}
