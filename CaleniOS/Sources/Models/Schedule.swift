#if os(iOS)
import Foundation
import SwiftUI
import SwiftData

// MARK: - Schedule
//
// 레퍼런스 `Calen-iOS/Calen/Models/Schedule.swift` 1:1 포팅 (M2 UI v3).
//
// **공존 주의**: `Shared/Sources/CalenShared/Models/CalendarEvent.swift`가 있지만
// 역할이 다르다.
//  - `Schedule` (이 파일): iOS 로컬 전용 SwiftData 엔티티. 샘플/mock 용.
//    Google Calendar 연동은 v0.1.1에서 `CalendarEvent` 기반으로 바뀔 예정.
//  - `CalendarEvent`: Shared(read-only) 도메인. macOS/iOS 공통 이벤트 모델.
//
// v0.1.0(현재)은 오프라인 데모/디자인 QA를 위한 샘플 데이터가 목적.

// MARK: - Schedule Category

enum ScheduleCategory: String, Codable, CaseIterable {
    case work      = "직장"
    case meeting   = "회의"
    case meal      = "식사"
    case exercise  = "운동"
    case personal  = "개인"
    case general   = "일반"

    /// Korean display label (same as raw value for this enum)
    var label: String { rawValue }

    var icon: String {
        switch self {
        case .work:     return "building.2"
        case .meeting:  return "person.3"
        case .meal:     return "fork.knife"
        case .exercise: return "figure.walk"
        case .personal: return "person"
        case .general:  return "calendar"
        }
    }

    /// Alias for `icon` — kept for backward compatibility with existing call sites.
    var iconName: String { icon }

    /// String token for use when a plain-string color name is needed (e.g. JSON).
    var color: String {
        switch self {
        case .work:     return "pink"
        case .meeting:  return "blue"
        case .meal:     return "yellow"
        case .exercise: return "green"
        case .personal: return "purple"
        case .general:  return "gray"
        }
    }

    /// Resolved SwiftUI Color for direct use in views.
    var swiftUIColor: Color {
        switch self {
        case .work:     return Color(red: 0.96, green: 0.40, blue: 0.57)  // pink
        case .meeting:  return Color.calenBlue                             // blue
        case .meal:     return Color(red: 0.98, green: 0.77, blue: 0.19)  // yellow
        case .exercise: return Color(red: 0.25, green: 0.78, blue: 0.52)  // green
        case .personal: return Color(red: 0.60, green: 0.36, blue: 0.91)  // purple
        case .general:  return Color(red: 0.56, green: 0.56, blue: 0.58)  // gray
        }
    }
}

// MARK: - Schedule

@Model
final class Schedule {
    var id: UUID
    var title: String
    var date: Date
    var startTime: Date
    var endTime: Date?
    var location: String?
    var notes: String?
    var category: ScheduleCategory
    var travelTimeMinutes: Int?
    var summary: String?
    var createdAt: Date

    init(
        title: String,
        date: Date,
        startTime: Date,
        endTime: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        category: ScheduleCategory = .general,
        travelTimeMinutes: Int? = nil,
        summary: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.notes = notes
        self.category = category
        self.travelTimeMinutes = travelTimeMinutes
        self.summary = summary
        self.createdAt = Date()
    }
}

// MARK: - Computed helpers

extension Schedule {
    /// Duration in minutes. Returns nil when endTime is not set.
    var durationMinutes: Int? {
        guard let endTime else { return nil }
        return Int(endTime.timeIntervalSince(startTime) / 60)
    }

    /// True when the schedule overlaps with the current moment.
    var isOngoing: Bool {
        let now = Date()
        guard let endTime else { return startTime <= now }
        return startTime <= now && now <= endTime
    }

    /// Formatted start–end time range string, e.g. "09:00 – 10:30".
    var timeRangeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let start = fmt.string(from: startTime)
        if let endTime {
            return "\(start) – \(fmt.string(from: endTime))"
        }
        return start
    }
}
#endif
