import Foundation
import Testing
import CoreGraphics
import CalenShared

// MARK: - TimeGridLayoutTests
//
// CalenShared의 순수 helper `TimeGridLayout` 단위 테스트.
// M2 UI v5 Phase A에서 도입된 시간 그리드 좌표 변환 로직 검증.
// iOS/macOS 어느 타깃에서도 실행 가능 (SwiftUI/UIKit 의존 없음).

private func makeCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
    cal.firstWeekday = 2
    return cal
}

private func date(_ string: String) -> Date {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime]
    return fmt.date(from: string) ?? Date()
}

@Test
func timeGridLayout_defaults_match_v5_spec() {
    let layout = TimeGridLayout()
    #expect(layout.startHour == 5)
    #expect(layout.durationHours == 19)
    #expect(layout.hourHeight == 60)
    #expect(layout.snapMinutes == 15)
    #expect(layout.minDurationMinutes == 15)
    #expect(layout.totalHeight == CGFloat(60 * 19))
    #expect(layout.pixelsPerMinute == CGFloat(1))
    #expect(layout.endHour == 24)
}

@Test
func timeGridLayout_y_and_minute_conversion_are_inverses() {
    let layout = TimeGridLayout()
    for minutes in stride(from: 0, through: 19 * 60, by: 15) {
        let y = layout.y(forMinutesFromStart: minutes)
        let back = layout.minutesFromStart(forY: y)
        #expect(back == minutes, "minutes=\(minutes) → y=\(y) → back=\(back)")
    }
}

@Test
func timeGridLayout_snap_rounds_to_nearest_quarter() {
    let layout = TimeGridLayout()
    #expect(layout.snap(minutes: 0) == 0)
    #expect(layout.snap(minutes: 7) == 0)   // <7.5 rounds down
    #expect(layout.snap(minutes: 8) == 15)
    #expect(layout.snap(minutes: 15) == 15)
    #expect(layout.snap(minutes: 22) == 15) // <22.5 rounds down
    #expect(layout.snap(minutes: 23) == 30)
    #expect(layout.snap(minutes: -7) == 0)
    #expect(layout.snap(minutes: -8) == -15)
}

@Test
func timeGridLayout_snappedMinutes_from_pixel_delta() {
    let layout = TimeGridLayout() // 1 px = 1 minute
    #expect(layout.snappedMinutes(forDeltaY: 0) == 0)
    #expect(layout.snappedMinutes(forDeltaY: 7) == 0)
    #expect(layout.snappedMinutes(forDeltaY: 8) == 15)
    #expect(layout.snappedMinutes(forDeltaY: 60) == 60)
    #expect(layout.snappedMinutes(forDeltaY: -22) == -15)

    // 더 촘촘한 스케일: 2pt = 1min
    let dense = TimeGridLayout(hourHeight: 120)
    // dy = 30pt → 15min → snap 15
    #expect(dense.snappedMinutes(forDeltaY: 30) == 15)
    #expect(dense.snappedMinutes(forDeltaY: 14) == 0) // 7min → round 0
}

@Test
func timeGridLayout_frame_for_event_inside_grid() {
    let cal = makeCalendar()
    let layout = TimeGridLayout()
    // 2026-04-19 08:00 ~ 09:30 (KST) — startHour=5 기준 180~270분
    let ev = CalendarEvent(
        id: "1",
        calendarId: "c",
        title: "t",
        startDate: date("2026-04-19T08:00:00+09:00"),
        endDate: date("2026-04-19T09:30:00+09:00")
    )
    let anchor = date("2026-04-19T00:00:00+09:00")

    let frame = layout.frame(for: ev, dayAnchor: anchor, calendar: cal)
    #expect(frame != nil)
    #expect(frame?.y == 180)         // (8-5)*60 = 180분 × 1pt
    #expect(frame?.height == 90)     // 1h30m = 90분
}

@Test
func timeGridLayout_frame_clamps_to_min_duration() {
    let cal = makeCalendar()
    let layout = TimeGridLayout()
    // 5분짜리 이벤트 — min 15분으로 clamp
    let ev = CalendarEvent(
        id: "2",
        calendarId: "c",
        title: "t",
        startDate: date("2026-04-19T10:00:00+09:00"),
        endDate: date("2026-04-19T10:05:00+09:00")
    )
    let frame = layout.frame(for: ev, dayAnchor: ev.startDate, calendar: cal)
    #expect(frame?.height == 15)
}

@Test
func timeGridLayout_frame_nil_for_out_of_range_and_allday() {
    let cal = makeCalendar()
    let layout = TimeGridLayout()

    // 전일 이벤트 (startHour=5 이전)
    let earlyMorning = CalendarEvent(
        id: "3",
        calendarId: "c",
        title: "t",
        startDate: date("2026-04-19T02:00:00+09:00"),
        endDate: date("2026-04-19T04:30:00+09:00")
    )
    #expect(layout.frame(for: earlyMorning, dayAnchor: earlyMorning.startDate, calendar: cal) == nil)

    // 종일 이벤트는 nil
    let allDay = CalendarEvent(
        id: "4",
        calendarId: "c",
        title: "t",
        startDate: date("2026-04-19T00:00:00+09:00"),
        endDate: date("2026-04-20T00:00:00+09:00"),
        isAllDay: true
    )
    #expect(layout.frame(for: allDay, dayAnchor: allDay.startDate, calendar: cal) == nil)
}

@Test
func timeGridLayout_yForNow_returns_nil_for_different_day() {
    let cal = makeCalendar()
    let layout = TimeGridLayout()
    let anchor = date("2026-04-19T00:00:00+09:00")
    let now = date("2026-04-20T12:00:00+09:00") // 다른 날
    #expect(layout.yForNow(on: anchor, calendar: cal, now: now) == nil)

    // 같은 날 10:00 → (10-5)*60 = 300pt
    let sameDay = date("2026-04-19T10:00:00+09:00")
    #expect(layout.yForNow(on: anchor, calendar: cal, now: sameDay) == 300)
}
