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

        // 1. 어제 완료된 Todo 통계 (피드백용)
        let yesterdayStats = collectDayStats(todos: viewModel.todos, events: viewModel.calendarEvents, date: yesterday)

        // 2. 미완료 + 지난 날짜 Todo → 오늘로 이동
        let pastTodos = incompletePastTodos(in: viewModel.todos, before: today)
        for id in pastTodos {
            viewModel.moveTodo(id: id, toDate: today)
        }

        markDone(today, key: rolloverKey)

        // 3. 지나간 구글 캘린더 이벤트 감지 (앱이 직접 생성한 것만)
        let overdueEvents = overdueGoogleEvents(in: viewModel.calendarEvents, before: today,
                                                 completedIDs: viewModel.completedEventIDs)

        // 4. 롤오버 피드백 알림
        scheduleMidnightFeedbackNotification(
            movedCount: pastTodos.count,
            stats: yesterdayStats,
            overdueEventCount: overdueEvents.count
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

    private func scheduleMidnightFeedbackNotification(movedCount: Int, stats: DayStats, overdueEventCount: Int) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        // 제목: 달성률
        if stats.totalTodos == 0 {
            content.title = "새 하루 시작 ☀️"
            content.body  = movedCount > 0
                ? "\(movedCount)개 미완료 할 일을 오늘로 이동했습니다."
                : "오늘도 파이팅!"
        } else {
            content.title = "어제 달성률: \(stats.achievementPercent)%"
            var parts: [String] = []
            if stats.completedTodos > 0 { parts.append("완료 \(stats.completedTodos)개") }
            if movedCount > 0           { parts.append("미완료 \(movedCount)개 → 오늘로 이동") }
            if overdueEventCount > 0    { parts.append("지난 일정 \(overdueEventCount)개 확인 필요") }
            content.body = parts.isEmpty ? "오늘도 파이팅!" : parts.joined(separator: " · ")
        }

        content.userInfo = ["action": "midnight_rollover"]

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

        // 오전 결산 제목
        if stats.totalTodos == 0 && stats.todayEventCount == 0 {
            content.title = "오늘 오후 일정 확인"
            content.body  = "Calen에서 오늘 남은 일정을 확인해보세요."
        } else {
            content.title = "오전 결산 · 정오 리마인더"
            var parts: [String] = []
            if stats.completedTodos > 0 { parts.append("완료 \(stats.completedTodos)개") }
            if stats.remainingTodos > 0 { parts.append("할 일 \(stats.remainingTodos)개 남음") }
            if stats.upcomingTodayEvents > 0 { parts.append("남은 일정 \(stats.upcomingTodayEvents)개") }
            content.body = parts.isEmpty ? "오후도 파이팅!" : parts.joined(separator: " · ")
        }

        // 즉시 또는 약간 딜레이 (2초)
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
