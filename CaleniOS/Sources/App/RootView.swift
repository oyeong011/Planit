#if os(iOS)
import SwiftUI

// MARK: - RootView
//
// 레퍼런스 `Calen-iOS/Calen/App/RootView.swift` 포팅 (M2 UI v3).
// 레퍼런스 원본은 Launch → Auth → Onboarding → MainTabView 4단계 분기였으나,
// v0.1.0 범위에서 `LaunchView` / `AuthView` / `OnboardingView` 화면은 포팅 대상이 아니므로
// **바로 MainTabView**로 진입한다. (Google 로그인은 SettingsView 안에서 처리.)
struct RootView: View {
    var body: some View {
        MainTabView()
    }
}

// MARK: - Previews

#Preview {
    RootView()
        .environmentObject(AppState())
}
#endif
