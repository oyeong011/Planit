import Foundation
@preconcurrency import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    @Published var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        Task { await checkOrRequestPermission() }
    }

    // MARK: - Permission

    /// 현재 권한 상태를 먼저 확인하고, notDetermined일 때만 시스템 다이얼로그 표시
    func checkOrRequestPermission() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            isAuthorized = true
        case .notDetermined:
            await requestPermission()
        case .denied, .ephemeral:
            isAuthorized = false
            print("[NotificationService] 권한 거부됨 — 알림 비활성화")
        @unknown default:
            isAuthorized = false
        }
    }

    private func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            print("[NotificationService] 권한 요청 실패: \(error)")
        }
    }

    /// 권한이 있을 때만 알림을 예약하는 헬퍼
    private func addRequest(_ request: UNNotificationRequest) {
        guard isAuthorized else {
            print("[NotificationService] 권한 없음 — 알림 스킵: \(request.identifier)")
            return
        }
        center.add(request) { error in
            if let error { print("[NotificationService] 알림 등록 실패: \(error)") }
        }
    }

    // MARK: - Daily Briefing

    func scheduleDailyBriefing(hour: Int, minute: Int = 0) {
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "오늘의 일정"
        content.body = "오늘의 일정을 확인하세요."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "calen.daily.briefing",
            content: content,
            trigger: trigger
        )

        addRequest(request)
    }

    func updateDailyBriefingContent(events: [String], todos: [String], morningBriefHour: Int = 8) {
        center.removePendingNotificationRequests(withIdentifiers: ["calen.daily.briefing"])

        // Rebuild content with actual data
        var lines: [String] = []
        if !events.isEmpty {
            lines.append("일정: " + events.joined(separator: ", "))
        }
        if !todos.isEmpty {
            lines.append("할 일: " + todos.joined(separator: ", "))
        }
        let body = lines.isEmpty ? "오늘 예정된 일정이 없습니다." : lines.joined(separator: "\n")

        let content = UNMutableNotificationContent()
        content.title = "오늘의 일정"
        content.body = body
        content.sound = .default

        // Re-schedule with fixed morningBriefHour trigger (prevents time drift)
        var dateComponents = DateComponents()
        dateComponents.hour = morningBriefHour
        dateComponents.minute = 0
        dateComponents.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "calen.daily.briefing",
            content: content,
            trigger: trigger
        )

        addRequest(request)
    }

    // MARK: - Event Reminder

    func scheduleEventReminder(eventId: String, title: String, at date: Date, minutesBefore: Int = 15) {
        let fireDate = date.addingTimeInterval(-Double(minutesBefore * 60))
        let interval = fireDate.timeIntervalSinceNow

        guard interval > 0 else { return }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "일정 알림"
        content.body = "\(minutesBefore)분 후: \(title)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "calen.event.\(eventId)",
            content: content,
            trigger: trigger
        )

        addRequest(request)
    }

    func cancelEventReminder(eventId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["calen.event.\(eventId)"])
    }

    // MARK: - Evening Review

    func scheduleEveningReview(hour: Int, minute: Int = 0) {
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "오늘 하루 리뷰"
        content.body = "완료한 일정을 확인하고 내일을 준비하세요"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "calen.daily.evening",
            content: content,
            trigger: trigger
        )

        addRequest(request)
    }

    // MARK: - Batch Schedule for Today's Events

    func scheduleRemindersForEvents(_ events: [(id: String, title: String, startDate: Date)]) {
        // Cancel all existing event reminders first
        let center = self.center
        center.getPendingNotificationRequests { [weak self, center] requests in
            let eventIds = requests
                .filter { $0.identifier.hasPrefix("calen.event.") }
                .map(\.identifier)

            center.removePendingNotificationRequests(withIdentifiers: eventIds)

            // Schedule new reminders on MainActor
            Task { @MainActor in
                for event in events {
                    self?.scheduleEventReminder(
                        eventId: event.id,
                        title: event.title,
                        at: event.startDate
                    )
                }
            }
        }
    }

    // MARK: - Cancel All

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
