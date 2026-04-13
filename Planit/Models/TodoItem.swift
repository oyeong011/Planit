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

    init(id: UUID = UUID(), title: String, categoryID: UUID, isCompleted: Bool = false, date: Date = Date(), isRepeating: Bool = false, endDate: Date? = nil, googleEventId: String? = nil) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.isCompleted = isCompleted
        self.date = date
        self.isRepeating = isRepeating
        self.endDate = endDate
        self.googleEventId = googleEventId
    }
}

// MARK: - CalendarEvent

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

    func toCalendarEvent() -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            color: Color(hex: colorHex) ?? .blue,
            isAllDay: isAllDay,
            calendarName: calendarName
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
            calendarName: event.calendarName
        )
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
}

// MARK: - Color to Hex

extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#6699FF" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
