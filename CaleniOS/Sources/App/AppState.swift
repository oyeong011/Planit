#if os(iOS)
import SwiftUI

// MARK: - Tab Enum
//
// v0.1.1 Review — 4탭 (today / chat / review / profile).
// v0.1.0: 2탭(today/profile) → v0.1.1 AI-1: 3탭(+chat) → v0.1.1 Review: 4탭(+review).
// 4칸 pill에서도 혼잡하지 않도록 아이콘 20pt + 라벨 10pt 유지.

enum Tab: String, CaseIterable {
    case today    = "today"
    case chat     = "chat"
    case review   = "review"
    case profile  = "profile"

    var title: String {
        switch self {
        case .today:    return "오늘"
        case .chat:     return "채팅"
        case .review:   return "리뷰"
        case .profile:  return "설정"
        }
    }

    var icon: String {
        switch self {
        case .today:    return "calendar.circle"
        case .chat:     return "bubble.left.and.bubble.right"
        case .review:   return "chart.bar.xaxis"
        case .profile:  return "person.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .today:    return "calendar.circle.fill"
        case .chat:     return "bubble.left.and.bubble.right.fill"
        // `chart.bar.xaxis.fill`은 SF Symbols 최신 버전에서만 존재 → 안전하게 같은 이름 사용
        // (선택 상태는 semibold + primary color로만 구분).
        case .review:   return "chart.bar.xaxis"
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
