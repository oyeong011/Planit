import SwiftUI
import Foundation

// MARK: - Dynamic Category

struct TodoCategory: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    // Default categories
    static let defaults: [TodoCategory] = [
        TodoCategory(name: "일상", colorHex: "#6699FF"),
        TodoCategory(name: "중요", colorHex: "#F27380"),
        TodoCategory(name: "공부", colorHex: "#F28E99"),
        TodoCategory(name: "운동", colorHex: "#F2BF4D"),
        TodoCategory(name: "플젝", colorHex: "#8099FF"),
        TodoCategory(name: "알바", colorHex: "#999999"),
    ]
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let num = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((num >> 16) & 0xFF) / 255.0,
            green: Double((num >> 8) & 0xFF) / 255.0,
            blue: Double(num & 0xFF) / 255.0
        )
    }

    /// 라이트/다크 모드에 따라 다른 Color 반환.
    /// 테마 tint 등 환경별로 강도를 다르게 주고 싶을 때 사용.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
        #else
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }

    /// 같은 hue/saturation을 유지하고 brightness만 덮어쓴 색을 반환.
    /// 다크 모드 배경용 — "검정에 가깝지만 테마 hue가 살짝 보이는" 색 만들 때 사용.
    /// 예: accent.withBrightness(0.10) → 거의 검정 + 미세한 accent hue.
    func withBrightness(_ newBrightness: Double) -> Color {
        #if os(macOS)
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s), brightness: newBrightness, opacity: Double(a))
        #else
        return self
        #endif
    }
}

// Available color presets for category picker
struct CategoryColor: Identifiable {
    let id = UUID()
    let name: String
    let hex: String

    static let presets: [CategoryColor] = [
        CategoryColor(name: "파랑", hex: "#6699FF"),
        CategoryColor(name: "빨강", hex: "#F27380"),
        CategoryColor(name: "분홍", hex: "#F28E99"),
        CategoryColor(name: "노랑", hex: "#F2BF4D"),
        CategoryColor(name: "초록", hex: "#4DBF7B"),
        CategoryColor(name: "보라", hex: "#9966FF"),
        CategoryColor(name: "하늘", hex: "#66CCFF"),
        CategoryColor(name: "주황", hex: "#FF9933"),
        CategoryColor(name: "회색", hex: "#999999"),
        CategoryColor(name: "남색", hex: "#336699"),
    ]
}

// MARK: - TodoItem Source

enum TodoSource: String, Codable {
    case local
    case appleReminder
}

// MARK: - TodoItem

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var categoryID: UUID
    var isCompleted: Bool
    var date: Date
    var isRepeating: Bool
    var endDate: Date?
    var googleEventId: String?
    var source: TodoSource
    var appleReminderIdentifier: String?

    init(id: UUID = UUID(), title: String, categoryID: UUID, isCompleted: Bool = false, date: Date = Date(), isRepeating: Bool = false, endDate: Date? = nil, googleEventId: String? = nil, source: TodoSource = .local, appleReminderIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.isCompleted = isCompleted
        self.date = date
        self.isRepeating = isRepeating
        self.endDate = endDate
        self.googleEventId = googleEventId
        self.source = source
        self.appleReminderIdentifier = appleReminderIdentifier
    }

    // 기존 JSON 호환성: source/appleReminderIdentifier 없는 데이터도 디코딩
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        categoryID = try container.decode(UUID.self, forKey: .categoryID)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        date = try container.decode(Date.self, forKey: .date)
        isRepeating = try container.decode(Bool.self, forKey: .isRepeating)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        googleEventId = try container.decodeIfPresent(String.self, forKey: .googleEventId)
        source = try container.decodeIfPresent(TodoSource.self, forKey: .source) ?? .local
        appleReminderIdentifier = try container.decodeIfPresent(String.self, forKey: .appleReminderIdentifier)
    }
}

// MARK: - CalendarEvent

enum CalendarEventSource: String, Codable {
    case google
    case apple
    case local // EventKit 단독 모드 (Google 미인증)
}

struct CalendarEvent: Identifiable, Hashable {
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var color: Color
    var isAllDay: Bool
    var calendarName: String = ""
    var calendarID: String = ""   // 안정적인 식별자: "google:primary", "apple:<uuid>"
    var source: CalendarEventSource = .google
    var categoryID: UUID? = nil   // 파생 상태 — 매핑 적용 후 채워짐
    /// EventKit이 제공하는 외부 동기화 ID. macOS Calendar가 Google 계정을 연결한 경우
    /// 원본 Google 이벤트 ID가 여기 담겨 있어 Google/Apple 미러 dedup 키로 사용.
    var externalID: String? = nil
}

// MARK: - Event Category Mapping (이벤트별 독립 매핑)

struct EventCategoryMapping: Codable, Hashable {
    var eventID: String          // CalendarEvent.id (이벤트별 고유 키)
    var eventTitle: String       // 표시용 스냅샷
    var categoryID: UUID
}

struct EventCategoryMappingsStore: Codable {
    var version: Int = 1
    var mappings: [EventCategoryMapping] = []
}

// MARK: - Offline Cache Models

/// Codable version of CalendarEvent for local caching
struct CachedCalendarEvent: Codable, Identifiable {
    let id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var colorHex: String
    var isAllDay: Bool
    var calendarName: String
    var calendarID: String       // 매핑 키 보존 (기존 캐시 호환: 없으면 "")
    var source: CalendarEventSource

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        isAllDay = try c.decode(Bool.self, forKey: .isAllDay)
        calendarName = try c.decode(String.self, forKey: .calendarName)
        calendarID = try c.decodeIfPresent(String.self, forKey: .calendarID) ?? ""
        source = try c.decode(CalendarEventSource.self, forKey: .source)
    }

    func toCalendarEvent() -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            color: Color(hex: colorHex) ?? .blue,
            isAllDay: isAllDay,
            calendarName: calendarName,
            calendarID: calendarID,
            source: source
        )
    }

    static func from(_ event: CalendarEvent) -> CachedCalendarEvent {
        CachedCalendarEvent(
            id: event.id,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            colorHex: event.color.toHex(),
            isAllDay: event.isAllDay,
            calendarName: event.calendarName,
            calendarID: event.calendarID,
            source: event.source
        )
    }

    // 명시적 init (Codable init from decoder와 충돌 방지)
    init(id: String, title: String, startDate: Date, endDate: Date, colorHex: String,
         isAllDay: Bool, calendarName: String, calendarID: String, source: CalendarEventSource) {
        self.id = id; self.title = title; self.startDate = startDate; self.endDate = endDate
        self.colorHex = colorHex; self.isAllDay = isAllDay; self.calendarName = calendarName
        self.calendarID = calendarID; self.source = source
    }
}

/// Offline edit operation queued for sync when back online
struct PendingCalendarEdit: Codable, Identifiable {
    let id: UUID
    let action: String  // "create", "update", "delete"
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var eventId: String?  // for update/delete
    let createdAt: Date

    init(action: String, title: String = "", startDate: Date = Date(), endDate: Date = Date(),
         isAllDay: Bool = false, eventId: String? = nil) {
        self.id = UUID()
        self.action = action
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.eventId = eventId
        self.createdAt = Date()
    }

    var isSafeForSync: Bool {
        guard ["create", "update", "delete"].contains(action) else { return false }
        guard title.count <= 500 else { return false }
        guard endDate >= startDate else { return false }
        guard endDate.timeIntervalSince(startDate) <= 366 * 24 * 60 * 60 else { return false }

        if action == "create" {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let eventId, !eventId.isEmpty, eventId.count <= 512 else { return false }
        if action == "update" {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    static func isSafeQueue(_ edits: [PendingCalendarEdit]) -> Bool {
        guard edits.count < 50 else { return false }
        return edits.allSatisfy(\.isSafeForSync)
    }
}

// Color.toHex()는 PlatformShims.swift에 정의됨 (크로스플랫폼)
