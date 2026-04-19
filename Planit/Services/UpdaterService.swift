import AppKit
import Foundation
import Sparkle
import UserNotifications

/// Sparkle 기반 자동 업데이트 래퍼.
/// appcast.xml을 주기적으로 확인해 업데이트가 감지되면 Sparkle UI가 다운로드/설치/재시작까지 자동 처리한다.
@MainActor
final class UpdaterService: NSObject, ObservableObject {
    static let shared = UpdaterService()

    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var latestVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var pollTimer: Timer?
    private var isPollingAppcast = false
    /// 같은 버전에 대해 알림이 매 체크마다 재발송되지 않도록 유지.
    private var lastNotifiedVersion: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 개발 빌드 여부 — run-dev.sh가 만드는 `/tmp/Calen.app`로 실행되면 dev.
    /// macOS에서 `/tmp`는 `/private/tmp`의 symlink이므로 Bundle.main.bundlePath는
    /// 실제 경로인 `/private/tmp/...`로 반환된다. 두 경로 모두 허용한다.
    /// 릴리즈 설치본(`/Applications/Calen.app`)에서는 false.
    static let isDevelopmentBuild: Bool = {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/")
    }()

    override init() {
        super.init()
        // 개발 빌드에서는 Sparkle 컨트롤러를 아예 구성하지 않음 — appcast 폴링도, 다이얼로그도 없음.
        guard !Self.isDevelopmentBuild else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// 사용자 수동 체크 — Sparkle 다이얼로그 표시
    func checkForUpdates() {
        guard !Self.isDevelopmentBuild, let controller else { return }
        // LSUIElement(.accessory) 앱은 기본적으로 비활성 상태이므로
        // Sparkle 윈도우가 생성돼도 앞에 나타나지 않는다. 먼저 앱을 활성화.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// 백그라운드 체크 트리거 (사용자 UI 없이)
    func checkForUpdatesInBackground() {
        guard !Self.isDevelopmentBuild, let controller else { return }
        controller.updater.checkForUpdatesInBackground()
    }

    /// appcast XML을 직접 받아 최신 버전을 확인하고 `updateAvailable`/`latestVersion`을 갱신.
    /// Sparkle의 `checkForUpdatesInBackground`는 menubar(accessory) 앱에서
    /// `didFindValidUpdate` delegate를 호출하지 않는 케이스가 있어 배너가 안 뜬다.
    /// 이 경로는 Sparkle에 의존하지 않고 직접 XML을 파싱해 Publisher를 갱신한다.
    func pollAppcastForBanner() async {
        guard !Self.isDevelopmentBuild else { return }
        guard !isPollingAppcast else { return }
        // Periodic polling and popover onAppear can overlap; keep only one appcast request active.
        isPollingAppcast = true
        defer { isPollingAppcast = false }

        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString) else { return }
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return }
        // 우리 appcast는 오래된 entry가 앞에 있는 경우가 있어 "첫 item = 최신" 가정은 틀림.
        // 모든 sparkle:shortVersionString을 추출해 numeric 비교로 최대 버전을 고른다.
        let pattern = #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsRange = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: nsRange)
        let versions: [String] = matches.compactMap { match in
            Range(match.range(at: 1), in: xml).map {
                String(xml[$0]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.filter { !$0.isEmpty }
        guard let latest = versions.max(by: { a, b in
            a.compare(b, options: .numeric) == .orderedAscending
        }) else { return }
        let current = currentVersion
        await MainActor.run {
            if latest.compare(current, options: .numeric) == .orderedDescending {
                self.updateAvailable = true
                self.latestVersion = latest
                // 같은 버전에 대해 한 번만 시스템 알림 — 사용자가 앱을 안 열고 있어도
                // 알림 센터로 새 버전 출시를 알려준다.
                if self.lastNotifiedVersion != latest {
                    self.lastNotifiedVersion = latest
                    self.postUpdateAvailableNotification(version: latest)
                }
            } else {
                self.updateAvailable = false
                self.latestVersion = nil
            }
        }
    }

    /// 주기적으로 appcast를 폴링해 새 버전을 감지 (기본 5분 간격).
    /// 서버 기반 push가 없는 환경에서 "릴리즈 직후 체감 즉시 알림"에 가깝도록
    /// 짧은 간격으로 당긴다. 목표 URL은 GitHub Pages CDN이라 부하는 미미함.
    func startPeriodicAppcastPolling(interval: TimeInterval = 300) {
        guard !Self.isDevelopmentBuild else { return }
        // 테스트 기기에서는 UserDefaults로 1분 폴링 강제 가능
        // 활성화: defaults write com.oy.planit planit.dev.fastUpdateCheck -bool YES
        let actualInterval: TimeInterval
        if UserDefaults.standard.bool(forKey: "planit.dev.fastUpdateCheck") {
            actualInterval = 60
        } else {
            actualInterval = interval
        }
        stopPeriodicAppcastPolling()
        // 시작 즉시 한 번 체크
        Task { await self.pollAppcastForBanner() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: actualInterval, repeats: true) { [weak self] _ in
            Task { await self?.pollAppcastForBanner() }
        }
    }

    func stopPeriodicAppcastPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func postUpdateAvailableNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "update.notification.title",
                               defaultValue: "Calen 업데이트 가능")
        content.body = String(localized: "update.notification.body",
                              defaultValue: "새 버전 v\(version)가 준비됐어요. Calen을 열어 설치하세요.")
        content.userInfo = ["type": "update-available", "version": version]
        let request = UNNotificationRequest(
            identifier: "calen.update.\(version)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
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
