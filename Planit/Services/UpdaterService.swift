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

    /// appcast XML을 직접 받아 최신 버전을 확인하고 `updateAvailable`/`latestVersion`을 갱신.
    /// Sparkle의 `checkForUpdatesInBackground`는 menubar(accessory) 앱에서
    /// `didFindValidUpdate` delegate를 호출하지 않는 케이스가 있어 배너가 안 뜬다.
    /// 이 경로는 Sparkle에 의존하지 않고 직접 XML을 파싱해 Publisher를 갱신한다.
    func pollAppcastForBanner() async {
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString) else { return }
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return }
        // appcast 규약상 첫 번째 <item>이 최신. 첫 sparkle:shortVersionString만 보면 충분.
        let pattern = #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return }
        let latest = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        let current = currentVersion
        await MainActor.run {
            if latest.compare(current, options: .numeric) == .orderedDescending {
                self.updateAvailable = true
                self.latestVersion = latest
            } else {
                self.updateAvailable = false
                self.latestVersion = nil
            }
        }
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
