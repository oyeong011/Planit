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

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("오늘", systemImage: "house.fill") }
            MemoryView()
                .tabItem { Label("기억", systemImage: "brain.head.profile") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape.fill") }
        }
        .tint(Color(red: 0.30, green: 0.67, blue: 0.98))
    }
}
#endif
