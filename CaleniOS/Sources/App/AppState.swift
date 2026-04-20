#if os(iOS)
import SwiftUI

// MARK: - Tab Enum
//
// M2 UI v4 (TimeBlocks 스타일) — 탭 2개로 축소.
// v3은 .home/.calendar/.profile 3탭이었으나, 오늘 탭이 월 그리드 + 일정 리스트를
// 겸하므로 `.calendar`를 폐지하고 `.today` / `.profile` 2칸으로 재구성.

enum Tab: String, CaseIterable {
    case today    = "today"
    case profile  = "profile"

    var title: String {
        switch self {
        case .today:    return "오늘"
        case .profile:  return "설정"
        }
    }

    var icon: String {
        switch self {
        case .today:    return "calendar.circle"
        case .profile:  return "person.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .today:    return "calendar.circle.fill"
        case .profile:  return "person.circle.fill"
        }
    }
}

// MARK: - AppState

final class AppState: ObservableObject {

    // In-memory navigation state
    @Published var selectedTab: Tab = .today
}
#endif
