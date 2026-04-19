import SwiftUI
import SwiftData

@main
struct CaleniOSApp: App {
    /// macOS 앱과 동일한 SwiftData 스키마 — CloudKit을 통해 같은 iCloud 컨테이너에서 sync
    /// Xcode target 설정에서 iCloud capability + "iCloud.com.oy.planit" container 추가 필요
    let container: ModelContainer = {
        let schema = Schema([MemoryFactRecord.self, PlanningDecisionRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )
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
