import Foundation
import UserNotifications

/// 자정에 미완료 Todo를 다음날로 자동 이동하는 서비스.
/// - 앱 실행 시 오늘 자정 롤오버가 아직 안 됐으면 자동 실행.
/// - 미완료 + 오늘 이전 날짜인 로컬 Todo를 오늘로 이동.
/// - 이동한 항목 수를 알림으로 표시.
@MainActor
final class MidnightRolloverService {

    static let shared = MidnightRolloverService()
    private init() {}

    private let rolloverKey = "planit.lastRolloverDate"
    private let center = UNUserNotificationCenter.current()

    // MARK: - Public

    /// 앱 실행 시 또는 날짜 변경 시 호출. 필요하면 롤오버 실행.
    func performIfNeeded(viewModel: CalendarViewModel) {
        let today = Calendar.current.startOfDay(for: Date())

        if let last = UserDefaults.standard.object(forKey: rolloverKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return // 오늘 이미 실행됨
        }

        let movedIDs = incompletePastTodos(in: viewModel.todos, before: today)
        guard !movedIDs.isEmpty else {
            markDone(today)
            return
        }

        for id in movedIDs {
            viewModel.moveTodo(id: id, toDate: today)
        }

        markDone(today)
        scheduleRolloverNotification(count: movedIDs.count)
    }

    /// 자정(00:01) 반복 알림을 예약해 두어 앱이 닫혀 있어도 열 수 있도록 유도.
    func scheduleMidnightTrigger() {
        var components = DateComponents()
        components.hour = 0
        components.minute = 1

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("rollover.notification.title", comment: "")
        content.body  = NSLocalizedString("rollover.notification.body", comment: "")
        content.sound = .default
        // userInfo로 앱이 열릴 때 롤오버 실행 트리거
        content.userInfo = ["action": "midnight_rollover"]

        let request = UNNotificationRequest(
            identifier: "planit.midnight.rollover",
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error { print("[MidnightRolloverService] 자정 트리거 예약 실패: \(error)") }
        }
    }

    func cancelMidnightTrigger() {
        center.removePendingNotificationRequests(withIdentifiers: ["planit.midnight.rollover"])
    }

    // MARK: - Private

    private func incompletePastTodos(in todos: [TodoItem], before today: Date) -> [UUID] {
        todos.compactMap { todo in
            guard !todo.isCompleted,
                  todo.source == .local,
                  todo.date < today else { return nil }
            return todo.id
        }
    }

    private func markDone(_ date: Date) {
        UserDefaults.standard.set(date, forKey: rolloverKey)
    }

    private func scheduleRolloverNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("rollover.moved.title", comment: "")
        let fmt = NSLocalizedString("rollover.moved.body", comment: "") // "%d개의 미완료 할 일을 오늘로 이동했습니다"
        content.body  = String(format: fmt, count)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request  = UNNotificationRequest(
            identifier: "planit.rollover.done.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }
}
