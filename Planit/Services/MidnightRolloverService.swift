import Foundation
import UserNotifications

/// 일일 피드백 & 자동 재배치 서비스.
///
/// - **자정(00:00)**: 미완료 Todo 다음날로 롤오버 + 어제 달성률 피드백 알림
/// - **정오(12:00)**: 오전 결산 + 오늘 남은 일정 미리보기 알림
/// - **구글 캘린더**: 지나간 이벤트가 있으면 앱 내에서 재배치 유도 알림
@MainActor
final class MidnightRolloverService {

    static let shared = MidnightRolloverService()
    private init() {}

    private let rolloverKey  = "planit.lastRolloverDate"
    private let noonKey      = "planit.lastNoonReviewDate"
    private let center = UNUserNotificationCenter.current()

    // MARK: - Public Entry Points

    /// 앱 실행 / 날짜 변경 시 호출 — 필요하면 자정 롤오버 실행
    func performIfNeeded(viewModel: CalendarViewModel) {
        let today = Calendar.current.startOfDay(for: Date())

        if let last = UserDefaults.standard.object(forKey: rolloverKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            // 자정 롤오버는 오늘 이미 실행됨 — 정오 리뷰만 체크
            performNoonReviewIfNeeded(viewModel: viewModel)
            return
        }

        performMidnightRollover(viewModel: viewModel, today: today)
        performNoonReviewIfNeeded(viewModel: viewModel)
    }

    /// 앱 시작 시 두 트리거 모두 예약
    func scheduleAllTriggers() {
        scheduleMidnightTrigger()
        scheduleNoonTrigger()
    }

    // 이전 코드 호환성 유지
    func scheduleMidnightTrigger() {
        scheduleTrigger(hour: 0, minute: 1, identifier: "planit.trigger.midnight",
                        title: NSLocalizedString("rollover.notification.title", comment: ""),
                        body: NSLocalizedString("rollover.notification.body", comment: ""),
                        action: "midnight_rollover")
    }

    func cancelMidnightTrigger() {
        center.removePendingNotificationRequests(withIdentifiers: [
            "planit.trigger.midnight", "planit.trigger.noon"
        ])
    }

    // MARK: - Midnight Rollover

    private func performMidnightRollover(viewModel: CalendarViewModel, today: Date) {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow  = Calendar.current.date(byAdding: .day, value:  1, to: today)!

        // 1. 어제 통계 (피드백용)
        let yesterdayStats = collectDayStats(todos: viewModel.todos, events: viewModel.calendarEvents, date: yesterday)

        // 2. 미완료 + 기한 지난 Todo 목록
        let pastTodoIDs = incompletePastTodos(in: viewModel.todos, before: today)
        let pastTodos   = viewModel.todos.filter { pastTodoIDs.contains($0.id) }

        // 3. 스마트 분산 배치 — 향후 7일 일정 밀도 분석 후 여유 날짜에 배정
        let scheduler = SmartSchedulerService()
        let plan = scheduler.distributeBacklog(
            todos: pastTodos,
            events: viewModel.calendarEvents,
            startDate: tomorrow   // 내일부터 탐색
        )

        // 4. 계획 적용
        for (id, newDate) in plan {
            viewModel.moveTodo(id: id, toDate: newDate)
        }

        markDone(today, key: rolloverKey)

        // 5. 지나간 구글 캘린더 이벤트 감지
        let overdueEvents = overdueGoogleEvents(
            in: viewModel.calendarEvents, before: today,
            completedIDs: viewModel.completedEventIDs
        )

        // 6. 결과 알림 (어디에 얼마나 배치됐는지 구체적으로)
        let summary = scheduler.backlogSummary(plan: plan, todos: pastTodos)
        scheduleMidnightFeedbackNotification(
            movedCount: plan.count,
            stats: yesterdayStats,
            overdueEventCount: overdueEvents.count,
            rescheduleSummary: summary
        )
    }

    // MARK: - Noon Review

    private func performNoonReviewIfNeeded(viewModel: CalendarViewModel) {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= 12 else { return } // 아직 오전이면 스킵

        let today = Calendar.current.startOfDay(for: now)
        if let last = UserDefaults.standard.object(forKey: noonKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return // 오늘 이미 실행됨
        }

        markDone(today, key: noonKey)

        let stats = collectDayStats(todos: viewModel.todos, events: viewModel.calendarEvents, date: today)
        scheduleNoonFeedbackNotification(stats: stats)
    }

    // MARK: - Stats Collection

    private struct DayStats {
        let completedTodos: Int
        let totalTodos: Int
        let remainingTodos: Int
        let todayEventCount: Int    // 오늘 구글 캘린더 이벤트 수
        let upcomingTodayEvents: Int // 현재 이후 이벤트 수

        var achievementPercent: Int {
            guard totalTodos > 0 else { return 100 }
            return completedTodos * 100 / totalTodos
        }
    }

    private func collectDayStats(todos: [TodoItem], events: [CalendarEvent], date: Date) -> DayStats {
        let cal = Calendar.current
        let dayTodos = todos.filter { todo in
            cal.isDate(todo.date, inSameDayAs: date) && todo.source == .local
        }
        let completedCount = dayTodos.filter { $0.isCompleted }.count
        let remainingCount = dayTodos.filter { !$0.isCompleted }.count

        let todayEvents = events.filter {
            !$0.isAllDay && cal.isDate($0.startDate, inSameDayAs: date) && $0.source == .google
        }
        let upcomingCount = todayEvents.filter { $0.startDate > Date() }.count

        return DayStats(
            completedTodos: completedCount,
            totalTodos: dayTodos.count,
            remainingTodos: remainingCount,
            todayEventCount: todayEvents.count,
            upcomingTodayEvents: upcomingCount
        )
    }

    // MARK: - Google Calendar Overdue Detection

    /// 앱이 "google:primary"에 생성한 이벤트 중 종료 시간이 지나고 완료 처리 안 된 것
    private func overdueGoogleEvents(in events: [CalendarEvent], before today: Date, completedIDs: Set<String>) -> [CalendarEvent] {
        events.filter { event in
            event.source == .google &&
            !event.isAllDay &&
            event.endDate < today &&
            !completedIDs.contains(event.id)
        }
    }

    // MARK: - Notifications

    private func scheduleMidnightFeedbackNotification(
        movedCount: Int,
        stats: DayStats,
        overdueEventCount: Int,
        rescheduleSummary: String = ""
    ) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["action": "midnight_rollover"]

        if stats.totalTodos == 0 && movedCount == 0 {
            content.title = "새 하루 시작"
            content.body  = overdueEventCount > 0
                ? "지난 일정 \(overdueEventCount)개를 확인해보세요."
                : "오늘도 파이팅!"
        } else {
            // 달성률이 있으면 제목에 표시
            if stats.totalTodos > 0 {
                content.title = "어제 달성률 \(stats.achievementPercent)% · Calen이 일정 조정 완료"
            } else {
                content.title = "Calen이 밀린 할 일 \(movedCount)개를 재배치했습니다"
            }

            var body = ""
            if !rescheduleSummary.isEmpty {
                // 구체적인 배치 내용 ("4/16(수): 보고서 · 4/17(목): 2개 할 일")
                body = rescheduleSummary
            } else if movedCount > 0 {
                body = "미완료 \(movedCount)개를 일정에 맞게 재배치했습니다."
            }
            if overdueEventCount > 0 {
                body += body.isEmpty ? "" : " · "
                body += "지난 일정 \(overdueEventCount)개 확인 필요"
            }
            content.body = body.isEmpty ? "오늘도 파이팅!" : body
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "planit.rollover.feedback.\(Int(Date().timeIntervalSince1970))",
            content: content, trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    private func scheduleNoonFeedbackNotification(stats: DayStats) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["action": "noon_review"]

        if stats.totalTodos == 0 && stats.todayEventCount == 0 {
            content.title = "정오 체크인"
            content.body  = stats.upcomingTodayEvents > 0
                ? "오후 일정 \(stats.upcomingTodayEvents)개가 남아있어요."
                : "Calen에서 오늘 계획을 세워보세요."
        } else {
            // 달성률 기반 제목
            let pct = stats.achievementPercent
            switch pct {
            case 0:
                content.title = "아직 시작 전이에요"
                content.body  = "오늘 할 일 \(stats.totalTodos)개 중 완료한 것이 없어요. 지금 시작해볼까요?"
            case 1..<50:
                content.title = "오전 달성률 \(pct)%"
                content.body  = "완료 \(stats.completedTodos)개 · 남은 할 일 \(stats.remainingTodos)개 · 오후 일정 \(stats.upcomingTodayEvents)개"
            case 50..<100:
                content.title = "반 이상 완료!"
                content.body  = "남은 할 일 \(stats.remainingTodos)개 · 오후 일정 \(stats.upcomingTodayEvents)개"
            default:
                content.title = "오늘 할 일 모두 완료!"
                content.body  = stats.upcomingTodayEvents > 0
                    ? "오후 일정 \(stats.upcomingTodayEvents)개가 남아있어요."
                    : "오늘도 수고했어요!"
            }
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "planit.noon.feedback.\(Int(Date().timeIntervalSince1970))",
            content: content, trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - Private Helpers

    private func incompletePastTodos(in todos: [TodoItem], before today: Date) -> [UUID] {
        todos.compactMap { todo in
            guard !todo.isCompleted,
                  todo.source == .local,
                  todo.date < today else { return nil }
            return todo.id
        }
    }

    private func markDone(_ date: Date, key: String) {
        UserDefaults.standard.set(date, forKey: key)
    }

    // MARK: - Trigger Scheduling

    private func scheduleNoonTrigger() {
        scheduleTrigger(hour: 12, minute: 0, identifier: "planit.trigger.noon",
                        title: "Calen 정오 리마인더",
                        body: "오전 결산 및 오후 일정을 확인하세요.",
                        action: "noon_review")
    }

    private func scheduleTrigger(hour: Int, minute: Int, identifier: String, title: String, body: String, action: String) {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.userInfo = ["action": action]

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("[DailyReview] 트리거 예약 실패 (\(identifier)): \(error)") }
        }
    }
}
