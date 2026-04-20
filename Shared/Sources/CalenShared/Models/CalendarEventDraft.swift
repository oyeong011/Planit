import Foundation

// MARK: - CalendarEventDraft
//
// 신규 이벤트 생성 요청용 value type.
// `CalendarEvent`와 달리 id/etag/updated/source 등 서버 할당 필드를 갖지 않는다.
// Repository.create(_:)에 전달되고, 성공 시 완전한 `CalendarEvent`를 반환받는다.
//
// fake repo, Google Calendar API, EventKit 세 구현이 이 같은 draft를 consume한다.

public struct CalendarEventDraft: Sendable, Equatable {
    public var calendarId: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var description: String?
    public var colorHex: String?

    public init(
        calendarId: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        description: String? = nil,
        colorHex: String? = nil
    ) {
        self.calendarId = calendarId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.description = description
        self.colorHex = colorHex
    }
}
