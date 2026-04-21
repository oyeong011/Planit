import Foundation

// MARK: - ReviewPeriod
//
// iOS 리뷰 탭의 일/주/월 기간 enum + 순수 필터링 로직.
// macOS와 iOS 양쪽에서 재사용 가능하도록 CalenShared에 위치 (플랫폼 의존성 없음).
// 테스트 가능성 확보가 주요 목적 — ViewModel에서 이 함수들을 호출해 카드 데이터를 만든다.

/// 리뷰 탭 기간 선택지 — 일간/주간/월간.
public enum ReviewPeriod: String, CaseIterable, Sendable, Codable {
    case day
    case week
    case month

    /// 세그먼티드 피커 라벨(한국어).
    public var label: String {
        switch self {
        case .day:   return "일간"
        case .week:  return "주간"
        case .month: return "월간"
        }
    }
}

// MARK: - ReviewCategory

/// Calen 6색 카테고리. iOS `ScheduleCategory`의 순수 미러 — Shared에서 참조 가능하도록.
/// `colorHex` 매핑은 iOS `HomeViewModel.category(forHex:)`와 동일 규칙.
public enum ReviewCategory: String, CaseIterable, Sendable, Codable {
    case work
    case meeting
    case meal
    case exercise
    case personal
    case general

    /// 한국어 라벨.
    public var label: String {
        switch self {
        case .work:     return "직장"
        case .meeting:  return "회의"
        case .meal:     return "식사"
        case .exercise: return "운동"
        case .personal: return "개인"
        case .general:  return "일반"
        }
    }

    /// iOS HomeViewModel.category(forHex:)와 동일한 hex → 카테고리 매핑.
    public static func from(colorHex hex: String) -> ReviewCategory {
        switch hex.uppercased() {
        case "#F56691": return .work
        case "#3B82F6": return .meeting
        case "#FAC430": return .meal
        case "#40C786": return .exercise
        case "#9A5CE8": return .personal
        default:        return .general
        }
    }
}

// MARK: - Period Interval

public extension ReviewPeriod {

    /// 주어진 `now` 기준으로 기간 Interval을 계산한다.
    /// - day: 오늘 0시 ~ 내일 0시
    /// - week: 월요일(ISO) 0시 ~ 다음 월요일 0시
    /// - month: 이달 1일 0시 ~ 다음달 1일 0시
    func interval(containing now: Date, calendar: Calendar = .current) -> DateInterval {
        let cal = calendar
        switch self {
        case .day:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .week:
            // ISO 주 시작 = 월요일. iOS HomeViewModel.weekStart(for:)와 동일.
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = 2 // Monday
            let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .month:
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = 1
            let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }
}

// MARK: - Filter / Aggregations (순수 함수)

public enum ReviewAggregator {

    /// `events` 중 `interval`과 겹치는 이벤트만 필터링.
    /// iOS FakeEventRepository.events(in:)과 동일 규칙(`end > start && start < end`).
    public static func eventsIn(
        interval: DateInterval,
        from events: [CalendarEvent]
    ) -> [CalendarEvent] {
        events.filter { $0.endDate > interval.start && $0.startDate < interval.end }
    }

    /// 카테고리별 **누적 분(minute)** 을 반환한다.
    /// 종일 이벤트는 24h로 보지 않고 실제 `end - start` 기준이지만 클램프해 interval 밖은 잘라낸다.
    public static func minutesByCategory(
        events: [CalendarEvent],
        clampedTo interval: DateInterval
    ) -> [ReviewCategory: Int] {
        var result: [ReviewCategory: Int] = [:]
        for ev in events {
            let start = max(ev.startDate, interval.start)
            let end   = min(ev.endDate,   interval.end)
            guard end > start else { continue }
            let minutes = Int(end.timeIntervalSince(start) / 60.0)
            let cat = ReviewCategory.from(colorHex: ev.colorHex)
            result[cat, default: 0] += minutes
        }
        return result
    }

    /// 특정 기간의 완료 비율(0.0~1.0).
    /// iOS는 Todo 모델이 없으므로 "이미 종료된 이벤트 / 전체 이벤트" 로 근사한다.
    /// 종료 기준: `event.endDate <= now`.
    public static func completionRate(
        events: [CalendarEvent],
        now: Date = Date()
    ) -> (done: Int, total: Int, rate: Double) {
        let total = events.count
        guard total > 0 else { return (0, 0, 0) }
        let done = events.filter { $0.endDate <= now }.count
        return (done, total, Double(done) / Double(total))
    }

    /// 최근 7일 일간 카테고리 요약(dot용).
    /// 반환: today부터 뒤로 7개(오늘 포함)의 day bucket. 각 day마다 카테고리별 이벤트 수.
    /// 값이 없으면 nil 들어감 → 뷰에서 회색 dot.
    public static func recentDaysSummary(
        events: [CalendarEvent],
        now: Date = Date(),
        calendar: Calendar = .current,
        dayCount: Int = 7
    ) -> [DaySummary] {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let items: [DaySummary] = (0..<dayCount).map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let start = date
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            let dayEvents = events.filter { $0.endDate > start && $0.startDate < end }
            // 가장 많은 카테고리를 dominant로 선정 — 동률이면 macOS 6색 정렬 순으로 tie-break.
            var counts: [ReviewCategory: Int] = [:]
            for ev in dayEvents {
                counts[ReviewCategory.from(colorHex: ev.colorHex), default: 0] += 1
            }
            let dominant: ReviewCategory? = ReviewCategory.allCases
                .compactMap { cat -> (ReviewCategory, Int)? in
                    guard let c = counts[cat], c > 0 else { return nil }
                    return (cat, c)
                }
                .max(by: { $0.1 < $1.1 })?.0
            return DaySummary(date: date, totalCount: dayEvents.count, dominant: dominant)
        }
        return items.reversed() // 과거 → 오늘 순서로
    }

    /// 최근 N일 잔디맵용 day 데이터.
    /// macOS `TodoGrassStats.make`의 iOS 간소화 버전 — Todo가 없으므로 이벤트 수만 집계.
    public static func grassDays(
        events: [CalendarEvent],
        now: Date = Date(),
        calendar: Calendar = .current,
        dayCount: Int = 30
    ) -> [GrassDay] {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let items: [GrassDay] = (0..<dayCount).map { offset -> GrassDay in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let start = date
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            let count = events.filter { $0.endDate > start && $0.startDate < end }.count
            return GrassDay(date: date, count: count)
        }
        return items.reversed()
    }
}

// MARK: - DaySummary / GrassDay

public struct DaySummary: Sendable, Equatable {
    public let date: Date
    public let totalCount: Int
    public let dominant: ReviewCategory?

    public init(date: Date, totalCount: Int, dominant: ReviewCategory?) {
        self.date = date
        self.totalCount = totalCount
        self.dominant = dominant
    }
}

public struct GrassDay: Sendable, Equatable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let count: Int

    public init(date: Date, count: Int) {
        self.date = date
        self.count = count
    }
}

// `.reversed()`는 ReversedCollection을 반환 — `Array(...)` 변환이 호출자에서 쓰기 편하도록 확장 메서드 제공.
private extension Sequence {
    /// 강제 Array 변환 — 테스트/디버깅 용이성.
    var asArray: [Element] { Array(self) }
}
