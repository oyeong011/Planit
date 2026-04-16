import Foundation
import UserNotifications

/// GitHub Releases API로 최신 버전을 확인하고 업데이트 여부를 알려줍니다.
@MainActor
final class UpdateCheckerService: ObservableObject {
    static let shared = UpdateCheckerService()

    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersion: String?

    private let repoURL = URL(string: "https://api.github.com/repos/oyeong011/Planit/releases/latest")!
    private let lastCheckKey = "planit.updateChecker.lastCheckDate"
    private let notifiedVersionKey = "planit.updateChecker.notifiedVersion"
    private let checkInterval: TimeInterval = 60 * 60 * 24 // 24시간

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private init() {}

    /// 앱 시작 시 호출 — 하루 1회 제한
    func checkIfNeeded() {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - lastCheck >= checkInterval else { return }
        Task { await check() }
    }

    /// 수동 강제 체크
    func check() async {
        var request = URLRequest(url: repoURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            latestVersion = latest
            let hasUpdate = isNewer(latest, than: currentVersion)
            updateAvailable = hasUpdate

            // 새 버전을 처음 감지했을 때만 시스템 알림 발송
            if hasUpdate {
                let alreadyNotified = UserDefaults.standard.string(forKey: notifiedVersionKey) == latest
                if !alreadyNotified {
                    sendUpdateNotification(version: latest)
                    UserDefaults.standard.set(latest, forKey: notifiedVersionKey)
                }
            }
        } catch {
            // 네트워크 실패 — 조용히 무시
        }
    }

    private func sendUpdateNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "update.notification.title")
        content.body = String(format: String(localized: "update.notification.body"), version)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "calen.update.\(version)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// latest가 current보다 높으면 true (semantic versioning)
    private func isNewer(_ latest: String, than current: String) -> Bool {
        let a = latest.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        let len = max(a.count, b.count)
        for i in 0..<len {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }
}
