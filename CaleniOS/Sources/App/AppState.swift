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

// MARK: - Onboarding policy (Quick Win QW3)
//
// iOS는 현재 OnboardingView가 없고 앱이 바로 MainTabView로 진입한다.
// v0.1.1 이후 3단계 온보딩(언어/Google 로그인/첫 목표)을 추가할 예정이며
// **스킵 정책**은 macOS와 동일하게 '이번엔 건너뛰기' 1버튼으로 통일한다:
//   - 스킵해도 `OnboardingFlag.onboardingDoneKey`는 true로 저장한다 → 재실행 시 재진입 없음.
//   - 사용자가 Settings > 온보딩 다시 보기를 고르면 수동 false로 재설정 가능.
//
// 본 타입은 선언만 — 실제 Gate 로직은 OnboardingView 도입 시 추가.
enum OnboardingFlag {
    /// `UserDefaults` 키. macOS/iOS 모두 같은 이름.
    static let onboardingDoneKey = "calen.onboardingDone"

    /// 공용 헬퍼. 앱 시작 시 이 값이 false면 OnboardingView를 띄운다.
    static var isDone: Bool {
        UserDefaults.standard.bool(forKey: onboardingDoneKey)
    }

    /// 온보딩 완료 또는 스킵 시 호출. 동작 동일 — 한 번 true면 재진입 없음.
    static func markDone() {
        UserDefaults.standard.set(true, forKey: onboardingDoneKey)
    }

    /// Settings에서 '온보딩 다시 보기' 옵션 선택 시 호출.
    static func reset() {
        UserDefaults.standard.set(false, forKey: onboardingDoneKey)
    }
}
#endif
