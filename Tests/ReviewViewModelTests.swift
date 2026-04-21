import Foundation
import Testing
@testable import CalenShared

// MARK: - ReviewViewModelTests (via CalenShared.ReviewAggregator / ReviewPeriod)
//
// iOS `ReviewViewModel` 자체는 `#if os(iOS)`로 감싸져 있어 macOS 테스트 타겟(Calen 기반)에서
// 직접 참조할 수 없다. 대신 VM이 위임하는 **순수 로직**인 `ReviewPeriod` 인터벌 계산과
// `ReviewAggregator.*` (필터링 / 카테고리 누적 / 완료율 / grass / 최근 7일) 를 검증한다.
//
// 이는 DoD의 "period 전환 시 events 필터링 테스트 3~5개"를 그대로 커버한다 — 실제 VM의
// `refresh()`가 이 함수들을 그대로 호출하기 때문.

// MARK: - Helpers

private func makeEvent(
    id: String = UUID().uuidString,
    start: Date,
    end: Date,
    hex: String = "#3B82F6"
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        calendarId: "test",
        title: "T",
        startDate: start,
        endDate: end,
        isAllDay: false,
        description: nil,
        location: nil,
        colorHex: hex,
        source: .local
    )
}

// 한국 시간대 고정 — ISO 주/월 경계가 UTC와 9h 차이나므로 테스트 안정화.
private let kstCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
    // firstWeekday는 interval(.week) 계산에서 월요일 고정이라 영향 없음.
    cal.firstWeekday = 2
    return cal
}()

// MARK: - Tests

@Suite("ReviewPeriod + Aggregator")
struct ReviewPeriodAggregatorTests {

    // 1. Day interval: "오늘 0시 ~ 내일 0시" — 24h 정확.
    @Test("day interval은 now가 속한 24h 구간")
    func dayIntervalExact() {
        let now = DateComponents(
            calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 15, minute: 30
        ).date!

        let iv = ReviewPeriod.day.interval(containing: now, calendar: kstCalendar)

        #expect(iv.duration == 24 * 60 * 60)
        #expect(kstCalendar.component(.hour, from: iv.start) == 0)
        #expect(kstCalendar.component(.day, from: iv.start) == 19)
        #expect(kstCalendar.component(.day, from: iv.end) == 20)
    }

    // 2. Week interval: "월요일 0시 ~ 다음 월요일 0시" — 7일 고정.
    @Test("week interval은 월요일 시작 7일")
    func weekIntervalExact() {
        // 2026-04-19 (일)  -> 포함 주의 월요일은 2026-04-13
        let sunday = DateComponents(
            calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 10
        ).date!

        let iv = ReviewPeriod.week.interval(containing: sunday, calendar: kstCalendar)

        #expect(iv.duration == 7 * 24 * 60 * 60)
        let startComp = kstCalendar.dateComponents([.year, .month, .day, .weekday], from: iv.start)
        #expect(startComp.day == 13)
        // 월요일 = Gregorian weekday 2
        #expect(startComp.weekday == 2)
    }

    // 3. Month interval: "이달 1일 ~ 다음달 1일".
    @Test("month interval은 이달 1일부터 다음달 1일")
    func monthIntervalExact() {
        let midApril = DateComponents(
            calendar: kstCalendar, year: 2026, month: 4, day: 19
        ).date!

        let iv = ReviewPeriod.month.interval(containing: midApril, calendar: kstCalendar)

        let startComp = kstCalendar.dateComponents([.year, .month, .day], from: iv.start)
        let endComp = kstCalendar.dateComponents([.year, .month, .day], from: iv.end)
        #expect(startComp.day == 1)
        #expect(startComp.month == 4)
        #expect(endComp.day == 1)
        #expect(endComp.month == 5)
    }

    // 4. filterEvents: day 범위로 자르면 주/월 이벤트가 제외된다(period 전환 검증).
    @Test("period 전환 시 events 필터링 — day는 오늘만, week는 이번 주만")
    func periodFiltering() {
        let now = DateComponents(
            calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 12
        ).date!

        // 오늘(일요일) 10:00 - 11:00
        let todayEv = makeEvent(
            id: "today",
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 10).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 11).date!
        )
        // 같은 주 월요일(04-13) 14:00-15:00
        let weekEv = makeEvent(
            id: "week",
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 13, hour: 14).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 13, hour: 15).date!
        )
        // 같은 월 04-05 14:00-15:00 (주는 다름)
        let monthEv = makeEvent(
            id: "month",
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 5, hour: 14).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 5, hour: 15).date!
        )
        let all = [todayEv, weekEv, monthEv]

        // Day
        let dayIv = ReviewPeriod.day.interval(containing: now, calendar: kstCalendar)
        let dayEvents = ReviewAggregator.eventsIn(interval: dayIv, from: all)
        #expect(dayEvents.map(\.id) == ["today"])

        // Week
        let weekIv = ReviewPeriod.week.interval(containing: now, calendar: kstCalendar)
        let weekEvents = Set(ReviewAggregator.eventsIn(interval: weekIv, from: all).map(\.id))
        #expect(weekEvents == Set(["today", "week"]))

        // Month
        let monthIv = ReviewPeriod.month.interval(containing: now, calendar: kstCalendar)
        let monthEvents = Set(ReviewAggregator.eventsIn(interval: monthIv, from: all).map(\.id))
        #expect(monthEvents == Set(["today", "week", "month"]))
    }

    // 5. Category minutes: 같은 카테고리의 누적이 분 단위로 합산되고 인터벌 밖은 clamp된다.
    @Test("카테고리별 누적 분 — 인터벌 clamp")
    func categoryMinutesClamp() {
        let start = DateComponents(
            calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 0
        ).date!
        let end = DateComponents(
            calendar: kstCalendar, year: 2026, month: 4, day: 20, hour: 0
        ).date!
        let interval = DateInterval(start: start, end: end)

        // meeting 60분(09:00-10:00)
        let meeting = makeEvent(
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 9).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 10).date!,
            hex: "#3B82F6" // meeting
        )
        // work 120분 (14:00-16:00)
        let work = makeEvent(
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 14).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 16).date!,
            hex: "#F56691" // work
        )
        // 전날-오늘 걸친 이벤트 (23:00 전날 ~ 01:00 오늘) — 오늘 부분 60분만 계산되어야 함
        let straddle = makeEvent(
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 18, hour: 23).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 1).date!,
            hex: "#9A5CE8" // personal
        )

        let minutes = ReviewAggregator.minutesByCategory(
            events: [meeting, work, straddle],
            clampedTo: interval
        )

        #expect(minutes[.meeting] == 60)
        #expect(minutes[.work] == 120)
        #expect(minutes[.personal] == 60)
        #expect(minutes[.meal] == nil)
    }

    // 6. Completion rate: 종료된 이벤트만 done, 미래 이벤트는 pending.
    @Test("완료 비율 — 종료 시각 <= now인 이벤트만 done")
    func completionRate() {
        let now = DateComponents(
            calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 15
        ).date!

        let past1 = makeEvent(
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 9).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 10).date!
        )
        let past2 = makeEvent(
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 13).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 14).date!
        )
        let future = makeEvent(
            start: DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 18).date!,
            end:   DateComponents(calendar: kstCalendar, year: 2026, month: 4, day: 19, hour: 19).date!
        )
        let r = ReviewAggregator.completionRate(events: [past1, past2, future], now: now)
        #expect(r.done == 2)
        #expect(r.total == 3)
        #expect(abs(r.rate - (2.0 / 3.0)) < 0.0001)

        // empty
        let empty = ReviewAggregator.completionRate(events: [], now: now)
        #expect(empty.done == 0)
        #expect(empty.total == 0)
        #expect(empty.rate == 0)
    }
}
