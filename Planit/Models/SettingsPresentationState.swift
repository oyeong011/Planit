import Foundation

enum SettingsPresentationIntent {
    case open
    case close
    case toggle

    func resolvedValue(from isPresented: Bool) -> Bool {
        switch self {
        case .open:
            return true
        case .close:
            return false
        case .toggle:
            return !isPresented
        }
    }
}
