#if os(iOS)
import SwiftUI

// MARK: - Tab Enum
//
// 레퍼런스 `Calen-iOS/Calen/App/AppState.swift` 포팅 (M2 UI v3).
// 레퍼런스 5탭(.home/.calendar/.aiCall/.chat/.profile) 중 v0.1.0은 3탭만 사용.
// `.aiCall`, `.chat`은 v0.1.1로 연기 — 해당 케이스 제거.

enum Tab: String, CaseIterable {
    case home     = "home"
    case calendar = "calendar"
    case profile  = "profile"

    var title: String {
        switch self {
        case .home:     return "오늘"
        case .calendar: return "캘린더"
        case .profile:  return "설정"
        }
    }

    var icon: String {
        switch self {
        case .home:     return "house"
        case .calendar: return "calendar"
        case .profile:  return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home:     return "house.fill"
        case .calendar: return "calendar"
        case .profile:  return "person.fill"
        }
    }
}

// MARK: - AppState

final class AppState: ObservableObject {

    // In-memory navigation state
    @Published var selectedTab: Tab = .home
}
#endif
