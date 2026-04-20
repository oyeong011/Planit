import Foundation
import Testing
import CalenShared

// MARK: - WeekEventLayoutTests
//
// 월 그리드의 주(week) 단위 이벤트 바 배치 알고리즘 검증.
// 순수 helper라 SwiftUI/UIKit 의존 없이 macOS 테스트 타깃에서 실행.

private func weekCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
    cal.firstWeekday = 1  // 일요일 시작
    return cal
}

/// ISO8601 문자열 → Date 헬퍼.
private func date(_ s: String) -> Date {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime]
    return fmt.date(from: s) ?? Date()
}

// 주 시작: 2026-04-19(일) 00:00 KST
private let weekStart = date("2026-04-19T00:00:00+09:00")

// MARK: - Tests

@Test
func weekEventLayout_singleDay_event_assigns_lane_zero() {
    let events = [
        WeekEventLayout.Input(
            id: "a",
            startDate: date("2026-04-20T09:00:00+09:00"),  // 월요일 (col 1)
            endDate:   date("2026-04-20T10:00:00+09:00")
        )
    ]
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart, calendar: weekCalendar())
    #expect(result.placements.count == 1)
    let p = result.placements[0]
    #expect(p.id == "a")
    #expect(p.lane == 0)
    #expect(p.startColumn == 1)
    #expect(p.spanColumns == 1)
    #expect(p.continuesFromPrev == false)
    #expect(p.continuesToNext == false)
}

@Test
func weekEventLayout_multiDay_event_spans_correct_columns() {
    // 수요일~금요일 3일짜리 이벤트
    let events = [
        WeekEventLayout.Input(
            id: "trip",
            startDate: date("2026-04-22T10:00:00+09:00"),  // 수 (col 3)
            endDate:   date("2026-04-24T18:00:00+09:00")   // 금 (col 5)
        )
    ]
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart, calendar: weekCalendar())
    #expect(result.placements.count == 1)
    let p = result.placements[0]
    #expect(p.startColumn == 3)
    #expect(p.spanColumns == 3)  // 수/목/금
    #expect(p.continuesFromPrev == false)
    #expect(p.continuesToNext == false)
}

@Test
func weekEventLayout_clips_event_from_previous_week() {
    // 이전 주 토요일부터 시작 → 이 주의 일(0)~수(3)까지
    let events = [
        WeekEventLayout.Input(
            id: "carryover",
            startDate: date("2026-04-18T12:00:00+09:00"),  // 이전 주 토
            endDate:   date("2026-04-22T12:00:00+09:00")   // 이 주 수 (col 3)
        )
    ]
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart, calendar: weekCalendar())
    #expect(result.placements.count == 1)
    let p = result.placements[0]
    #expect(p.startColumn == 0)
    #expect(p.spanColumns == 4)  // 일(0)부터 수(3)까지 4칸
    #expect(p.continuesFromPrev == true)
    #expect(p.continuesToNext == false)
}

@Test
func weekEventLayout_clips_event_to_next_week() {
    // 금요일 시작, 다음 주 월요일 종료
    let events = [
        WeekEventLayout.Input(
            id: "spansOut",
            startDate: date("2026-04-24T08:00:00+09:00"),  // 금 (col 5)
            endDate:   date("2026-04-27T20:00:00+09:00")   // 다음 주 월
        )
    ]
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart, calendar: weekCalendar())
    #expect(result.placements.count == 1)
    let p = result.placements[0]
    #expect(p.startColumn == 5)
    #expect(p.spanColumns == 2)  // 금(5), 토(6)
    #expect(p.continuesFromPrev == false)
    #expect(p.continuesToNext == true)
}

@Test
func weekEventLayout_overlap_assigns_different_lanes() {
    // 월~수 하나, 화~목 하나 — 겹치면 다른 lane
    let events = [
        WeekEventLayout.Input(
            id: "A",
            startDate: date("2026-04-20T09:00:00+09:00"),  // 월
            endDate:   date("2026-04-22T11:00:00+09:00")   // 수
        ),
        WeekEventLayout.Input(
            id: "B",
            startDate: date("2026-04-21T10:00:00+09:00"),  // 화
            endDate:   date("2026-04-23T11:00:00+09:00")   // 목
        )
    ]
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart, calendar: weekCalendar())
    #expect(result.placements.count == 2)
    let pA = result.placements.first(where: { $0.id == "A" })!
    let pB = result.placements.first(where: { $0.id == "B" })!
    #expect(pA.lane != pB.lane)
    // 시작 column 오름차순 정렬이므로 A가 lane 0
    #expect(pA.lane == 0)
    #expect(pB.lane == 1)
}

@Test
func weekEventLayout_non_overlapping_reuses_lower_lane() {
    // 월~화 / 금~토 — 겹치지 않으면 같은 lane 재사용
    let events = [
        WeekEventLayout.Input(
            id: "earlyBar",
            startDate: date("2026-04-20T09:00:00+09:00"),  // 월
            endDate:   date("2026-04-21T11:00:00+09:00")   // 화
        ),
        WeekEventLayout.Input(
            id: "lateBar",
            startDate: date("2026-04-24T09:00:00+09:00"),  // 금
            endDate:   date("2026-04-25T11:00:00+09:00")   // 토
        )
    ]
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart, calendar: weekCalendar())
    let pEarly = result.placements.first(where: { $0.id == "earlyBar" })!
    let pLate = result.placements.first(where: { $0.id == "lateBar" })!
    #expect(pEarly.lane == 0)
    #expect(pLate.lane == 0)  // 같은 lane 재사용 (gap 있음)
}

@Test
func weekEventLayout_filters_events_outside_week() {
    // 이 주와 전혀 겹치지 않는 이벤트는 제외
    let events = [
        WeekEventLayout.Input(
            id: "tooEarly",
            startDate: date("2026-04-10T09:00:00+09:00"),
            endDate:   date("2026-04-10T10:00:00+09:00")
        ),
        WeekEventLayout.Input(
            id: "tooLate",
            startDate: date("2026-05-05T09:00:00+09:00"),
            endDate:   date("2026-05-05T10:00:00+09:00")
        ),
        WeekEventLayout.Input(
            id: "inWeek",
            startDate: date("2026-04-22T09:00:00+09:00"),
            endDate:   date("2026-04-22T10:00:00+09:00")
        )
    ]
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart, calendar: weekCalendar())
    #expect(result.placements.count == 1)
    #expect(result.placements[0].id == "inWeek")
}

@Test
func weekEventLayout_overflow_hidden_by_column() {
    // 같은 날에 5개 이벤트(maxVisibleLanes=4) → 1개는 hidden
    let events = (0..<5).map { i in
        WeekEventLayout.Input(
            id: "e\(i)",
            startDate: date("2026-04-22T\(String(format: "%02d", 8+i)):00:00+09:00"),
            endDate:   date("2026-04-22T\(String(format: "%02d", 9+i)):00:00+09:00")
        )
    }
    let result = WeekEventLayout.layout(events: events, weekStart: weekStart,
                                         maxVisibleLanes: 4, calendar: weekCalendar())
    #expect(result.placements.count == 4)
    // 5번째 이벤트는 lane 4 → hidden
    #expect(result.hiddenByColumn[3] == 1)  // 수요일(col 3)
}
