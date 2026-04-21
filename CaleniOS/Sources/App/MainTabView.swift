#if os(iOS)
import SwiftUI

// MARK: - MainTabView
//
// v0.1.1 Review — 4칸 pill 탭바 (today / chat / review / profile).
// v0.1.1 AI-1(3탭) → Review(4탭) 확장. 스타일(cornerRadius 32, 이중 그림자, easeInOut 0.2) 유지.
// iPhone 17 Pro 세로에서도 혼잡하지 않도록 아이콘 20pt + 라벨 9~10pt.

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: Content Area
            Group {
                switch appState.selectedTab {
                case .today:
                    HomeView()
                case .chat:
                    ChatTabView()
                case .review:
                    ReviewTabView()
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
            tabButton(.chat)
            tabButton(.review)
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
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(tab.title)
                    // 4칸 확장 — 라벨을 9pt로 살짝 줄여 crowded 방지.
                    .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
            }
            // UX Critic fix: Color(.darkGray)는 다크모드에서 거의 안 보임.
            // 시스템 의미적 색상으로 교체 — 자동 light/dark 대응.
            .foregroundStyle(isSelected ? Color.calenBlue : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel(tab.title)
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
