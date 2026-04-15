import Foundation
import UserNotifications

/// 자정(00:00) 재배치 서비스.
///
/// 흐름:
/// 1. 하루가 끝나는 자정(00:00)에 실행
/// 2. 오늘 못 끝낸 할 일 탐색
/// 3. SmartSchedulerService로 향후 7일 일정 밀도 분석
/// 4. 여유로운 날에 분산 배치 (하루 최대 3개)
/// 5. 결과 알림 — 어디에 얼마나 옮겼는지 구체적으로 표시
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

        guard let last = UserDefaults.standard.object(forKey: rolloverKey) as? Date,
              !Calendar.current.isDate(last, inSameDayAs: today) else {
            // 오늘 이미 실행됨
            return
        }

        performMidnightRollover(viewModel: viewModel, today: today)
    }

    /// 자정(00:01) 반복 알림 트리거 예약
    func scheduleAllTriggers() {
        var comps = DateComponents()
        comps.hour = 0
        comps.minute = 1

        let content = UNMutableNotificationContent()
        content.title = "Calen 일정 조정 중"
        content.body  = "오늘 못 끝낸 할 일을 다음 일정에 맞게 재배치합니다."
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
        let tomorrow  = cal.date(byAdding: .day, value:  1, to: today)!

        // 어제 달성 통계
        let stats = collectDayStats(todos: viewModel.todos, events: viewModel.calendarEvents, date: yesterday)

        // 못 끝낸 할 일 수집 (기한 지난 미완료)
        let overdueTodos = viewModel.todos.filter {
            !$0.isCompleted && $0.source == .local && $0.date < today
        }

        // 스마트 배치: 내일부터 7일 내 여유 있는 날에 분산
        let scheduler = SmartSchedulerService()
        let plan = scheduler.distributeBacklog(
            todos: overdueTodos,
            events: viewModel.calendarEvents,
            startDate: tomorrow
        )

        // 적용 — 시스템 재배치로 기록 (UI 인디케이터용)
        for (id, newDate) in plan {
            viewModel.moveTodoBySystem(id: id, toDate: newDate)
        }

        // 완료 기록
        UserDefaults.standard.set(today, forKey: rolloverKey)

        // 결과 알림
        let summary = scheduler.backlogSummary(plan: plan, todos: overdueTodos)
        sendRolloverNotification(stats: stats, movedCount: plan.count, summary: summary)
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

    private func sendRolloverNotification(stats: DayStats, movedCount: Int, summary: String) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["action": "midnight_rollover"]

        if movedCount == 0 {
            // 모두 완료
            if stats.totalTodos > 0 {
                content.title = "어제 할 일 \(stats.achievementPercent)% 달성!"
                content.body  = "모든 할 일을 완료했어요. 오늘도 파이팅!"
            } else {
                content.title = "새로운 하루 시작"
                content.body  = "오늘 할 일을 계획해보세요."
            }
        } else {
            // 재배치 발생
            let pct = stats.totalTodos > 0 ? " (달성률 \(stats.achievementPercent)%)" : ""
            content.title = "Calen이 \(movedCount)개 할 일을 재배치했습니다\(pct)"
            content.body  = summary.isEmpty
                ? "일정 여유에 맞게 자동으로 배분했어요."
                : summary
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(
            identifier: "planit.rollover.result.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        ))
    }
}
