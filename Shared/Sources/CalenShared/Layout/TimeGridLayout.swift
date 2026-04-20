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
// 수직(y) 변환은 instance helper로, 가로(컬럼 x) 변환은 v6부터 아래
// `dayColumn`/`dayColumnWidth` helper로 함께 제공한다. 실제 그리드 뷰에는 여전히
// GeometryReader가 필요하지만, 좌표 → 요일 인덱스 매핑은 순수 함수로 단위 테스트한다.

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

    // MARK: - Day column (horizontal) — v6

    /// 7일 그리드에서 단일 요일 칼럼이 차지할 폭.
    ///
    /// iPhone 세로 같은 좁은 화면에서도 이벤트 텍스트가 잘리지 않도록 최소 120pt를 보장한다.
    /// 화면이 충분히 크면(`availableWidth / dayCount >= 120`) 비율대로 늘려 iPad/가로 모드에서도
    /// 한 화면에 7일이 완전히 펼쳐진다.
    ///
    /// - Parameters:
    ///   - availableWidth: 좌측 시간 라벨(gutter)을 뺀 실제 그리드용 가용 폭.
    ///   - dayCount: 열을 나눌 요일 수(기본 7). 0 이하는 1로 클램프.
    /// - Returns: pt 단위 컬럼 폭. `max(120, availableWidth / dayCount)`.
    public func dayColumnWidth(availableWidth: CGFloat, dayCount: Int = 7) -> CGFloat {
        let safeCount = max(1, dayCount)
        let even = availableWidth / CGFloat(safeCount)
        return max(120, even)
    }

    /// 그리드 내부 x 좌표를 요일 인덱스로 변환한다.
    ///
    /// 좌측 gutter를 이미 제외한 "그리드 로컬 x"(0 = 월요일 컬럼 좌측)가 전제다.
    /// 결과는 `[0, dayCount - 1]` 범위로 클램프된다 — 드래그가 가장자리를 넘어 튕기는 현상 방지.
    ///
    /// - Parameters:
    ///   - x: 그리드 기준 x 좌표 (pt). 음수 허용(왼쪽 끝으로 클램프됨).
    ///   - columnWidth: `dayColumnWidth(...)`로 계산된 칼럼 폭. 0 이하는 무효 → 0 반환.
    ///   - dayCount: 요일 수(기본 7).
    /// - Returns: 0-based 요일 인덱스.
    public func dayColumn(fromX x: CGFloat, columnWidth: CGFloat, dayCount: Int = 7) -> Int {
        guard columnWidth > 0 else { return 0 }
        let safeCount = max(1, dayCount)
        let raw = Int((x / columnWidth).rounded(.down))
        return max(0, min(safeCount - 1, raw))
    }
}
