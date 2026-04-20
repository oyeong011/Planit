#if os(iOS)
import SwiftUI

// MARK: - MainTabView
//
// M2 UI v4 (TimeBlocks 스타일) — 2칸 pill 탭바.
// v3의 3칸(.home / .calendar / .profile)에서 `.calendar`가 오늘 탭(HomeView)에
// 흡수되어 2칸으로 축소. 스타일(cornerRadius 32, 이중 그림자, easeInOut 0.2) 유지.

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: Content Area
            Group {
                switch appState.selectedTab {
                case .today:
                    HomeView()
                case .profile:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 90)

            // MARK: Custom Tab Bar
            CustomTabBar(selectedTab: $appState.selectedTab)
        }
        .ignoresSafeArea(.keyboard)
        .edgesIgnoringSafeArea(.bottom)
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: Tab

    private let tabBarHeight: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.today)
            tabButton(.profile)
        }
        .frame(height: tabBarHeight)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.calenCardSurface)
                .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: -4)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: -2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Regular Tab Button

    @ViewBuilder
    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                .font(.system(size: 26, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.calenBlue : Color(.darkGray))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
#endif
