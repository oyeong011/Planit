#if os(iOS)
import SwiftUI

// MARK: - RootView (Sprint B — sizeClass 분기)
//
// horizontalSizeClass 에 따라 레이아웃 분기:
//  - .compact (iPhone, iPad Split View 1/3) → MainTabView (4탭 pill)
//  - .regular (iPad full / 1/2)              → iPadRootView (3-column SplitView)
//
// 참고: 기존 RootView 는 무조건 MainTabView 진입이었으나, Sprint B 부터
// iPad 전용 IA 를 분리. 향후 LaunchView / AuthView 단계는 v0.2 이후.

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        if hSizeClass == .regular {
            iPadRootView()
        } else {
            MainTabView()
        }
    }
}

// MARK: - Previews

#Preview("Compact / iPhone") {
    RootView()
        .environmentObject(AppState())
        .environmentObject(iOSThemeService.shared)
}

#Preview("Regular / iPad") {
    RootView()
        .environmentObject(AppState())
        .environmentObject(iOSThemeService.shared)
        .environment(\.horizontalSizeClass, .regular)
}
#endif
