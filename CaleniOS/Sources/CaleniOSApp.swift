#if !os(iOS)
// macOS/Linux 빌드에서는 CaleniOS target을 빌드해도 실제 앱은 생성하지 않음.
// (SwiftPM은 per-platform target 제외를 지원하지 않으므로 placeholder main을 둠.)
// 실제 iOS 앱은 xcodebuild -scheme CaleniOS -destination 'generic/platform=iOS Simulator'로 빌드.
@main
struct CaleniOSPlaceholder {
    static func main() {
        // no-op: iOS 전용 target — macOS에서는 실행되지 않아야 함
    }
}
#else
import SwiftUI
import SwiftData

@main
struct CaleniOSApp: App {
    /// 로컬 SwiftData 캐시만 사용. iCloud sync는 SwiftData cloudKitDatabase가 아니라
    /// custom CKRecord(`HermesMemoryFactV1`)를 통해 M2(SYNC 팀장)에서 구현 예정.
    /// (자동 CloudKit 동기화는 macOS 스키마와 해시 충돌 위험이 있어 의도적으로 꺼둠.)
    let container: ModelContainer = {
        let schema = Schema([MemoryFactRecord.self, PlanningDecisionRecord.self])
        let config = ModelConfiguration(schema: schema)
        return try! ModelContainer(for: schema, configurations: config)
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

// MARK: - RootTabView
//
// iOS v0.1.0 P0 — **3탭 레이아웃**.
//   0. 오늘  — `CalendarTabView`
//   1. 할일  — `TodoTabView`
//   2. 설정  — `SettingsView`
//
// 디자인 토큰은 `Resources/Color+Calen.swift` + `Resources/Theme.swift`에서 제공.
// 레퍼런스(`Calen-iOS/Calen/App/MainTabView.swift`)의 커스텀 pill TabBar 패턴을 3탭에 맞게 이식.
// (레퍼런스의 5탭 구조 + 중앙 elevated mic 버튼은 v0.1.0 범위 밖 — 3개 동일 가중치 탭으로 단순화.)
//
// iPad(regular horizontal size class)는 `NavigationSplitView`로 자동 적응.

/// 3탭 인덱스. 정렬/아이콘/라벨을 한 곳에서 관리하기 위한 enum.
enum CalenTab: Int, CaseIterable, Identifiable {
    case today = 0
    case todo = 1
    case settings = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .today:    return "오늘"
        case .todo:     return "할일"
        case .settings: return "설정"
        }
    }

    /// 기본(미선택) 심볼 — SF Symbols.
    var icon: String {
        switch self {
        case .today:    return "calendar"
        case .todo:     return "checklist"
        case .settings: return "gearshape"
        }
    }

    /// 선택 시 사용하는 심볼 (fill variant).
    var selectedIcon: String {
        switch self {
        case .today:    return "calendar"
        case .todo:     return "checklist.checked"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: CalenTab = .today

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: iPhone (compact) — 커스텀 pill TabBar

    private var iPhoneLayout: some View {
        ZStack(alignment: .bottom) {
            // MARK: Content
            //
            // 각 탭을 `ZStack`으로 쌓아두면 `TabView` 없이도 상태가 유지됨.
            // overlap 방지를 위해 하단 탭바 높이만큼 clearance 확보(`safeAreaInset`).
            Group {
                switch selectedTab {
                case .today:
                    CalendarTabView(selectedTab: Binding(
                        get: { selectedTab.rawValue },
                        set: { selectedTab = CalenTab(rawValue: $0) ?? .today }
                    ))
                case .todo:
                    TodoTabView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 탭바(약 82pt: height 60 + bottom padding 12 + safe area) 아래 컨텐츠가 밀리도록.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 72)
            }

            // MARK: Custom pill TabBar
            CalenTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: iPad (regular) — NavigationSplitView

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: Binding<CalenTab?>(
                get: { selectedTab },
                set: { selectedTab = $0 ?? .today }
            )) {
                ForEach(CalenTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.icon).tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Calen")
        } detail: {
            switch selectedTab {
            case .today:
                CalendarTabView(selectedTab: Binding(
                    get: { selectedTab.rawValue },
                    set: { selectedTab = CalenTab(rawValue: $0) ?? .today }
                ))
            case .todo:
                TodoTabView()
            case .settings:
                SettingsView()
            }
        }
        .tint(Color.calenBlue)
    }
}

// MARK: - CalenTabBar
//
// 레퍼런스 `MainTabView.swift`의 pill TabBar 패턴을 3탭 버전으로 이식.
// - 흰색 둥근 캡슐(cornerRadius 32)
// - 각 탭 버튼은 `maxWidth: .infinity`로 동일 가중치
// - 선택 시 `calenBlue` tint + semibold
// - 미선택은 `Color(.darkGray)`
// - 탭 전환 애니메이션: `easeInOut(0.2)`
private struct CalenTabBar: View {
    @Binding var selectedTab: CalenTab

    private let tabBarHeight: CGFloat = 60

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalenTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .frame(height: tabBarHeight)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: -4)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: -2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func tabButton(_ tab: CalenTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.calenBlue : Color(.darkGray))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
#endif
