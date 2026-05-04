import Foundation
import UserNotifications

/// 자정(00:00) 재검토 알림 서비스.
///
/// 흐름:
/// 1. 하루가 끝나는 자정(00:00)에 실행
/// 2. 오늘 못 끝낸 할 일 탐색
/// 3. 자동 이동 대신 리뷰 알림만 표시
/// 4. 실제 이동은 저녁 리뷰 UI에서 사용자가 추천안을 확인한 뒤 적용
@MainActor
final class MidnightRolloverService {

    static let shared = MidnightRolloverService()
    private init() {}

    private let rolloverKey = "planit.lastRolloverDate"
    private let center = UNUserNotificationCenter.current()

    // MARK: - Public

    /// 앱 실행 시 또는 날짜 변경 시 호출.
    /// 오늘 자정 재배치가 아직 실행되지 않았으면 실행.
    func performIfNeeded(viewModel: CalendarViewModel) {
        let today = Calendar.current.startOfDay(for: Date())
        let last = UserDefaults.standard.object(forKey: rolloverKey) as? Date

        guard Self.shouldPerformRollover(lastRun: last, today: today) else {
            return
        }

        performMidnightRollover(viewModel: viewModel, today: today)
    }

    nonisolated static func shouldPerformRollover(
        lastRun: Date?,
        today: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastRun else { return true }
        return !calendar.isDate(lastRun, inSameDayAs: today)
    }

    /// 자정(00:01) 반복 알림 트리거 예약
    func scheduleAllTriggers() {
        var comps = DateComponents()
        comps.hour = 0
        comps.minute = 1

        let content = UNMutableNotificationContent()
        content.title = "Calen 저녁 리뷰"
        content.body  = "못 끝낸 할 일이 있으면 이동 추천을 확인해보세요."
        content.sound = .default
        content.userInfo = ["action": "midnight_rollover"]

        let request = UNNotificationRequest(
            identifier: "planit.trigger.midnight",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        )
        center.add(request) { err in
            if let err { print("[MidnightRollover] 트리거 예약 실패: \(err)") }
        }
    }

    func cancelMidnightTrigger() {
        center.removePendingNotificationRequests(withIdentifiers: ["planit.trigger.midnight"])
    }

    // 이전 코드 호환
    func scheduleMidnightTrigger() { scheduleAllTriggers() }

    // MARK: - Core Rollover

    private func performMidnightRollover(viewModel: CalendarViewModel, today: Date) {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        // 어제 달성 통계
        let stats = collectDayStats(todos: viewModel.todos, events: viewModel.calendarEvents, date: yesterday)

        // 못 끝낸 할 일 수집 (기한 지난 미완료)
        let overdueTodos = viewModel.todos.filter {
            !$0.isCompleted && $0.source == .local && $0.date < today
        }

        // 완료 기록
        UserDefaults.standard.set(today, forKey: rolloverKey)

        // 알림만 표시 — 이동은 리뷰 UI에서 확인 후 적용
        sendRolloverNotification(stats: stats, pendingCount: overdueTodos.count)
    }

    // MARK: - Stats

    private struct DayStats {
        let completedTodos: Int
        let totalTodos: Int
        var achievementPercent: Int {
            guard totalTodos > 0 else { return 100 }
            return completedTodos * 100 / totalTodos
        }
    }

    private func collectDayStats(todos: [TodoItem], events: [CalendarEvent], date: Date) -> DayStats {
        let cal = Calendar.current
        let dayTodos = todos.filter {
            $0.source == .local && cal.isDate($0.date, inSameDayAs: date)
        }
        return DayStats(
            completedTodos: dayTodos.filter { $0.isCompleted }.count,
            totalTodos: dayTodos.count
        )
    }

    // MARK: - Notification

    private func sendRolloverNotification(stats: DayStats, pendingCount: Int) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["action": "midnight_rollover"]

        if pendingCount == 0 {
            // 모두 완료
            if stats.totalTodos > 0 {
                content.title = "어제 할 일 \(stats.achievementPercent)% 달성!"
                content.body  = "모든 할 일을 완료했어요. 오늘도 파이팅!"
            } else {
                content.title = "새로운 하루 시작"
                content.body  = "오늘 할 일을 계획해보세요."
            }
        } else {
            // 확인 필요
            let pct = stats.totalTodos > 0 ? " (달성률 \(stats.achievementPercent)%)" : ""
            content.title = "이동 추천이 필요한 할 일 \(pendingCount)개\(pct)"
            content.body  = "앱을 열어 앞으로의 일정과 목표에 맞춘 이동 추천을 확인하세요."
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(
            identifier: "planit.rollover.result.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        ))
    }
}
