import Foundation

// MARK: - CalendarEventSource

/// 이벤트 출처 — Google / Apple EventKit / 로컬(EventKit 단독 모드).
public enum CalendarEventSource: String, Codable, Sendable {
    case google
    case apple
    case local
}

// MARK: - CalendarEvent (platform-neutral)

/// 플랫폼 중립 캘린더 이벤트 value type.
///
/// SwiftUI.Color / AppKit / UIKit 의존이 없고 색은 `colorHex`(예: "#3366CC")만 담는다.
/// macOS 앱은 자체 `Planit.CalendarEvent`(SwiftUI.Color 포함)를 우선 사용할 수 있고,
/// iOS 앱은 이 타입을 직접 사용한다.
public struct CalendarEvent: Sendable, Identifiable, Hashable, Codable {
    public let id: String
    public var calendarId: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var description: String?
    public var location: String?
    public var colorHex: String     // 예: "#3366CC". SwiftUI/UIColor 변환은 플랫폼 측에서 수행.
    public var source: CalendarEventSource

    public init(
        id: String,
        calendarId: String = "",
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        description: String? = nil,
        location: String? = nil,
        colorHex: String = "#3366CC",
        source: CalendarEventSource = .google
    ) {
        self.id = id
        self.calendarId = calendarId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.description = description
        self.location = location
        self.colorHex = colorHex
        self.source = source
    }

    // Hashable/Equatable — id만으로 식별.
    public static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
