import Foundation
import Sparkle

/// Sparkle 기반 자동 업데이트 래퍼.
/// appcast.xml을 주기적으로 확인해 업데이트가 감지되면 Sparkle UI가 다운로드/설치/재시작까지 자동 처리한다.
@MainActor
final class UpdaterService: NSObject, ObservableObject {
    static let shared = UpdaterService()

    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var latestVersion: String?

    private var controller: SPUStandardUpdaterController!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// 사용자 수동 체크 — Sparkle 다이얼로그 표시
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 백그라운드 체크 트리거 (사용자 UI 없이)
    func checkForUpdatesInBackground() {
        controller.updater.checkForUpdatesInBackground()
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterService: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.updateAvailable = true
            self.latestVersion = version
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.updateAvailable = false
        }
    }
}
