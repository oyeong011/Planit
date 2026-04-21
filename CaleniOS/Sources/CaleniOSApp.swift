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

// MARK: - CaleniOSApp
//
// 레퍼런스 `Calen-iOS/Calen/App/CalenApp.swift`를 기반으로 재작성 (M2 UI v3).
// 레퍼런스는 `Schedule.self`, `Relation.self` 두 모델을 포함했으나,
// v0.1.0은 `Relation`을 포팅하지 않았으므로 `Schedule.self`만 사용한다.
// Hermes 로컬 캐시(`MemoryFactRecord`, `PlanningDecisionRecord`)는 별도 스키마로
// 함께 등록한다.

@main
struct CaleniOSApp: App {
    @StateObject private var appState = AppState()
    /// v0.1.2 테마 시스템. MainTabView/HomeView/SettingsView 가 환경 주입으로 참조.
    @StateObject private var themeService = iOSThemeService.shared
    /// v0.1.2 언어 설정. Locale override — preferredLocalizations 를 앱 단위로 강제.
    @StateObject private var language = iOSLanguageService.shared

    /// 로컬 SwiftData 컨테이너.
    ///  - `Schedule` (iOS 로컬 전용 샘플 엔티티, M2 UI v3에서 포팅)
    ///  - `MemoryFactRecord`, `PlanningDecisionRecord` (Hermes 로컬 캐시)
    ///
    /// iCloud sync는 SwiftData cloudKitDatabase가 아니라 custom CKRecord(`HermesMemoryFactV1`)
    /// 를 통해 M2(SYNC 팀장)에서 구현. (자동 CloudKit 동기화는 macOS 스키마와 해시 충돌
    /// 위험이 있어 의도적으로 꺼둠.)
    ///
    /// 실패 시: 기존 store가 스키마 변경으로 에러를 내면 shared App Group 내 store를
    /// 지우고 재시도, 두 번째도 실패하면 in-memory fallback. `try!` 크래시 회피.
    ///
    /// v0.1.2 핫픽스 — iCloud entitlements 활성화로 SwiftData가 **자동 CloudKit 통합**을
    /// 켜버려 "CloudKit integration requires that all attributes be optional" 에러로 크래시.
    /// 우리는 Hermes custom CKRecord 경로를 사용하므로 SwiftData 자체 CloudKit은 `.none` 로 차단.
    let container: ModelContainer = {
        let schema = Schema([
            Schedule.self,
            MemoryFactRecord.self,
            PlanningDecisionRecord.self,
        ])

        // CloudKit 자동통합 차단 — Hermes 메모리는 별도 `HermesMemoryFactV1` CKRecord 경로 사용.
        let diskConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        if let c = try? ModelContainer(for: schema, configurations: diskConfig) {
            return c
        }

        // 구버전(v0.1.1) store가 CloudKit hash를 갖고 있어 열리지 않는 경우 제거 후 재시도.
        let candidates: [URL] = [
            URL.applicationSupportDirectory.appending(path: "default.store"),
            URL.applicationSupportDirectory.appending(path: "default.store-shm"),
            URL.applicationSupportDirectory.appending(path: "default.store-wal")
        ]
        for u in candidates { try? FileManager.default.removeItem(at: u) }

        if let groupDir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.oy.planit"
        )?.appending(path: "Library/Application Support") {
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try? FileManager.default.removeItem(at: groupDir.appending(path: name))
            }
        }

        if let c = try? ModelContainer(for: schema, configurations: diskConfig) {
            return c
        }

        // 최후의 수단: 휘발성 in-memory 컨테이너. 로컬 SwiftData는 비지만 앱 자체는 구동.
        let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memConfig)
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(themeService)
                .environmentObject(language)
                .environment(\.locale, Locale(identifier: language.current.rawValue))
                .tint(themeService.current.primary)
                .onOpenURL { url in
                    GoogleOAuthURLHandler.handleCallback(url)
                }
        }
        .modelContainer(container)
    }
}
#endif
