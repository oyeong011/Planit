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
// iPad(regular horizontal size class)는 `NavigationSplitView`로 자동 적응.
// (이전 Home / Memory 2탭 구조는 재배치됨. Home 기능은 Calendar에 통합,
//  Memory는 설정 → "기억 조회" 네비게이션 하위로 이동.)
struct RootTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: Int = 0

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad / 큰 화면 — sidebar 스타일.
            iPadLayout
        } else {
            // iPhone / compact — 하단 탭바.
            iPhoneLayout
        }
    }

    // MARK: iPhone (compact)

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            CalendarTabView(selectedTab: $selectedTab)
                .tabItem { Label("오늘", systemImage: "calendar") }
                .tag(0)

            TodoTabView()
                .tabItem { Label("할일", systemImage: "checklist") }
                .tag(1)

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(Color(red: 0.30, green: 0.67, blue: 0.98))
    }

    // MARK: iPad (regular)

    private var iPadLayout: some View {
        // iOS 17 `List(selection:)`는 optional binding을 요구하므로
        // 내부 optional 프로퍼티를 거쳐 `selectedTab`과 동기화한다.
        NavigationSplitView {
            List(selection: Binding<Int?>(
                get: { selectedTab },
                set: { selectedTab = $0 ?? 0 }
            )) {
                Label("오늘", systemImage: "calendar").tag(0)
                Label("할일", systemImage: "checklist").tag(1)
                Label("설정", systemImage: "gearshape.fill").tag(2)
            }
            .listStyle(.sidebar)
            .navigationTitle("Calen")
        } detail: {
            switch selectedTab {
            case 0:
                CalendarTabView(selectedTab: $selectedTab)
            case 1:
                TodoTabView()
            case 2:
                SettingsView()
            default:
                CalendarTabView(selectedTab: $selectedTab)
            }
        }
        .tint(Color(red: 0.30, green: 0.67, blue: 0.98))
    }
}
#endif
