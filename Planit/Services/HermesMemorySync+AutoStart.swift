import Foundation
import OSLog

// MARK: - HermesMemorySync AutoStart
//
// 앱 startup 경로에서 호출할 수 있는 static entry point.
// 본 커밋에서는 **코드만 준비**하고, 실제 호출처(`PlanitApp.swift` / `AppDelegate`)는
// 다른 세션 영역이므로 손대지 않는다. M2 이후 RELEASE 또는 UI 팀장이 startup hook에
//   `HermesMemorySync.startIfEnabled(service: calendarViewModel.hermesMemoryService)`
// 와 같이 연결한다.
//
// UserDefaults flag `planit.hermesCloudKitSyncEnabled`가 true일 때만 시작한다
// (기본값 false). Setting UI에서 토글할 수 있도록 key 이름을 고정.

extension HermesMemorySync {

    /// UserDefaults key — Setting UI와 공유.
    public static let enabledFlagKey = "planit.hermesCloudKitSyncEnabled"

    /// 활성화 플래그가 켜져 있으면 `HermesMemorySync`를 만들어 background sync 시작.
    ///
    /// - Returns: 시작된 인스턴스 (caller가 retain 해야 Timer가 살아있음). 비활성화 시 nil.
    @discardableResult
    @MainActor
    public static func startIfEnabled(
        service: HermesMemoryService,
        defaults: UserDefaults = .standard
    ) -> HermesMemorySync? {
        let logger = Logger(subsystem: "com.oy.planit", category: "hermes.sync")
        guard defaults.bool(forKey: enabledFlagKey) else {
            logger.debug("startIfEnabled: 비활성화 상태 — skip")
            return nil
        }
        logger.info("startIfEnabled: CloudKit upstream sync 시작")
        let sync = HermesMemorySync(hermesMemoryService: service)
        sync.scheduleBackgroundSync()
        return sync
    }
}

// NOTE: M2 후 PlanitApp startup에서 `HermesMemorySync.startIfEnabled(service:)` 호출 예정.
// 현재 커밋에서는 PlanitApp.swift / AppDelegate 수정은 다른 세션 영역이므로
// 호출처 추가는 후속 PR에서 수행한다.
