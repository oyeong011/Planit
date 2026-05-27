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
///
/// **Identity**: 외부 시스템(Google Calendar, EventKit)에서 event.id는 calendar 내부에서만 유일하므로
/// `calendarId + id`를 **복합 식별자**로 본다. Hashable/Equatable은 두 필드 모두 비교한다.
/// (v0.1.0에선 fake repo가 UUID id를 쓰므로 충돌 확률은 없지만,
///  Phase B에서 Google Calendar 실연동 시 동일 id가 서로 다른 calendar에서 나타날 수 있음.)
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

    /// Google Calendar/EventKit의 서버측 버전 태그. 옵티미스틱 업데이트 충돌 감지용.
    public var etag: String?

    /// 마지막 서버 반영 시각. UI 정렬/동기화 기준.
    public var updated: Date?

    /// 읽기 전용 플래그(초대된 이벤트, 공유 캘린더의 viewer-only 등).
    /// `true`면 iOS 시간 그리드에서 드래그/리사이즈 불가.
    public var isReadOnly: Bool

    /// Calen completion state. Google Calendar writes mirror this to
    /// `extendedProperties.private.calenCompleted=true` and a description marker.
    public var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case calendarId
        case title
        case startDate
        case endDate
        case isAllDay
        case description
        case location
        case colorHex
        case source
        case etag
        case updated
        case isReadOnly
        case isCompleted
    }

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
        source: CalendarEventSource = .google,
        etag: String? = nil,
        updated: Date? = nil,
        isReadOnly: Bool = false,
        isCompleted: Bool? = nil
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
        self.etag = etag
        self.updated = updated
        self.isReadOnly = isReadOnly
        self.isCompleted = isCompleted ?? Self.completionValue(fromDescription: description)
    }

    // Hashable/Equatable — `calendarId + id` 복합 identity.
    public static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id && lhs.calendarId == rhs.calendarId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(calendarId)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            calendarId: try container.decodeIfPresent(String.self, forKey: .calendarId) ?? "",
            title: try container.decode(String.self, forKey: .title),
            startDate: try container.decode(Date.self, forKey: .startDate),
            endDate: try container.decode(Date.self, forKey: .endDate),
            isAllDay: try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false,
            description: description,
            location: try container.decodeIfPresent(String.self, forKey: .location),
            colorHex: try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#3366CC",
            source: try container.decodeIfPresent(CalendarEventSource.self, forKey: .source) ?? .google,
            etag: try container.decodeIfPresent(String.self, forKey: .etag),
            updated: try container.decodeIfPresent(Date.self, forKey: .updated),
            isReadOnly: try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false,
            isCompleted: try container.decodeIfPresent(Bool.self, forKey: .isCompleted)
                ?? Self.completionValue(fromDescription: description)
        )
    }
}

public extension CalendarEvent {
    static let completionDescriptionMarker = "calenCompleted=true"

    static func completionValue(fromDescription description: String?) -> Bool {
        description?.contains(completionDescriptionMarker) == true
    }

    func settingCompleted(_ completed: Bool) -> CalendarEvent {
        var copy = self
        copy.isCompleted = completed
        copy.description = Self.description(copy.description, settingCompleted: completed)
        return copy
    }

    private static func description(_ description: String?, settingCompleted completed: Bool) -> String? {
        let lines = (description ?? "")
            .components(separatedBy: .newlines)
            .filter { !$0.contains(completionDescriptionMarker) }
        var cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if completed {
            if !cleaned.isEmpty { cleaned += "\n" }
            cleaned += completionDescriptionMarker
        }
        return cleaned.isEmpty ? nil : cleaned
    }
}
