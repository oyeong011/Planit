#if os(iOS)
import SwiftUI

// MARK: - MainTabView
//
// 레퍼런스 `Calen-iOS/Calen/App/MainTabView.swift` 포팅 (M2 UI v3).
// 레퍼런스는 5탭 + 중앙 elevated mic 버튼 구조였으나, v0.1.0은 3탭으로 축소.
//  - `.aiCall` 중앙 mic 버튼 제거
//  - `.chat`(Relations) 제거
//  - 4칸 pill → 3칸 pill
// 나머지 스타일(cornerRadius 32, 이중 그림자, easeInOut 0.2) 그대로 유지.

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: Content Area
            Group {
                switch appState.selectedTab {
                case .home:
                    HomeView()
                case .calendar:
                    CalendarView()
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
            tabButton(.home)
            tabButton(.calendar)
            tabButton(.profile)
        }
        .frame(height: tabBarHeight)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white)
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
                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
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
