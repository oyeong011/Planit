import Foundation
import CoreGraphics

// MARK: - TimeGridLayout
//
// 주(週) 시간 그리드 좌표 변환 순수 helper.
// SwiftUI/UIKit/AppKit 의존 없음 → SwiftPM 단위 테스트에서 직접 검증 가능.
// CalenShared에 위치시켜 iOS 시간 그리드 + macOS 잠재적 재사용 모두 커버.
//
// 좌표 시스템:
//   y = 0  → `startHour`시 정각 (예: 5시)
//   y = H  → (startHour + durationHours)시 정각 (예: 24시)
//   분당 pixel = hourHeight / 60  (기본 60pt/h → 1pt/min)
//
// 수직(y) 변환만 담당. 가로(컬럼 x)는 View가 GeometryReader로 처리.

public struct TimeGridLayout: Sendable, Equatable {

    // MARK: - Config

    /// 그리드 시작 시각 (0..<24). 기본 5시.
    public var startHour: Int

    /// 그리드 표시 시간 수. 기본 19 (5시 ~ 24시).
    public var durationHours: Int

    /// 시간당 pixel. 기본 60pt. 분당 = 1pt.
    public var hourHeight: CGFloat

    /// 드래그·리사이즈 snap 간격(분). 기본 15분.
    public var snapMinutes: Int

    /// 최소 이벤트 지속 시간(분). 리사이즈 clamp. 기본 15분.
    public var minDurationMinutes: Int

    public init(
        startHour: Int = 5,
        durationHours: Int = 19,
        hourHeight: CGFloat = 60,
        snapMinutes: Int = 15,
        minDurationMinutes: Int = 15
    ) {
        self.startHour = startHour
        self.durationHours = durationHours
        self.hourHeight = hourHeight
        self.snapMinutes = snapMinutes
        self.minDurationMinutes = minDurationMinutes
    }

    // MARK: - Derived

    /// 전체 그리드 높이 (pt).
    public var totalHeight: CGFloat {
        CGFloat(durationHours) * hourHeight
    }

    /// 분당 pixel.
    public var pixelsPerMinute: CGFloat {
        hourHeight / 60
    }

    /// 그리드 종료 시각(시 단위, exclusive).
    public var endHour: Int {
        startHour + durationHours
    }

    // MARK: - Y ↔ minute conversion

    /// 분(그리드 시작 기준) → y pixel.
    public func y(forMinutesFromStart minutes: Int) -> CGFloat {
        CGFloat(minutes) * pixelsPerMinute
    }

    /// y pixel → 분(그리드 시작 기준, 클램프됨).
    public func minutesFromStart(forY y: CGFloat) -> Int {
        let raw = Int((y / pixelsPerMinute).rounded())
        return max(0, min(durationHours * 60, raw))
    }

    /// Date → 그 날짜의 "startHour 기준" 분 오프셋.
    /// 종일 이벤트거나 그리드 범위 밖이면 nil.
    public func minutesFromDayStart(for date: Date, dayAnchor: Date, calendar: Calendar) -> Int? {
        let startOfDay = calendar.startOfDay(for: dayAnchor)
        guard let gridStart = calendar.date(
            byAdding: .minute,
            value: startHour * 60,
            to: startOfDay
        ) else { return nil }

        let diff = date.timeIntervalSince(gridStart)
        let minutes = Int((diff / 60.0).rounded(.down))
        if minutes < 0 || minutes > durationHours * 60 { return nil }
        return minutes
    }

    // MARK: - Snap

    /// 분 단위 snap.
    public func snap(minutes: Int) -> Int {
        let snapped = Int((Double(minutes) / Double(snapMinutes)).rounded()) * snapMinutes
        return snapped
    }

    /// pixel 단위 delta → 분 단위 snapped delta.
    public func snappedMinutes(forDeltaY dy: CGFloat) -> Int {
        let minutes = Int((dy / pixelsPerMinute).rounded())
        return snap(minutes: minutes)
    }

    // MARK: - Event block layout

    /// 하루 내부 이벤트 블록의 y 시작 / 높이.
    /// 그리드 범위 바깥(예: 이벤트가 startHour 이전 또는 endHour 이후)은 가시 범위로 클램프.
    /// 반환값은 y/height 모두 하루 그리드 좌표(0...totalHeight).
    public func frame(
        for event: CalendarEvent,
        dayAnchor: Date,
        calendar: Calendar
    ) -> (y: CGFloat, height: CGFloat)? {
        guard !event.isAllDay else { return nil }

        let dayStart = calendar.startOfDay(for: dayAnchor)
        guard
            let gridStart = calendar.date(byAdding: .minute, value: startHour * 60, to: dayStart),
            let gridEnd = calendar.date(byAdding: .minute, value: (startHour + durationHours) * 60, to: dayStart)
        else { return nil }

        // 이벤트가 해당 날짜 그리드와 전혀 겹치지 않으면 nil
        if event.endDate <= gridStart || event.startDate >= gridEnd { return nil }

        let visibleStart = max(event.startDate, gridStart)
        let visibleEnd = min(event.endDate, gridEnd)

        let startMin = Int(visibleStart.timeIntervalSince(gridStart) / 60.0)
        let endMin = Int(visibleEnd.timeIntervalSince(gridStart) / 60.0)
        let duration = max(minDurationMinutes, endMin - startMin)

        return (
            y: y(forMinutesFromStart: startMin),
            height: CGFloat(duration) * pixelsPerMinute
        )
    }

    // MARK: - Now indicator

    /// 현재 시각이 그리드 범위 안에 있을 때의 y 오프셋. 바깥이면 nil.
    public func yForNow(on dayAnchor: Date, calendar: Calendar, now: Date = Date()) -> CGFloat? {
        guard calendar.isDate(now, inSameDayAs: dayAnchor) else { return nil }
        guard let minutes = minutesFromDayStart(for: now, dayAnchor: dayAnchor, calendar: calendar) else {
            return nil
        }
        return y(forMinutesFromStart: minutes)
    }
}
