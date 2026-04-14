import Foundation
import SwiftUI

/// Direct Google Calendar REST API client — bypasses macOS Calendar/EventKit delay
@MainActor
final class GoogleCalendarService {
    private let auth: GoogleAuthManager
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    init(auth: GoogleAuthManager) {
        self.auth = auth
    }

    // MARK: - Color mapping (Google Calendar colorId → Color)

    private static let eventColors: [String: Color] = [
        "1": Color(red: 0.47, green: 0.53, blue: 0.87),  // Lavender
        "2": Color(red: 0.20, green: 0.66, blue: 0.33),  // Sage
        "3": Color(red: 0.54, green: 0.35, blue: 0.72),  // Grape
        "4": Color(red: 0.89, green: 0.42, blue: 0.43),  // Flamingo
        "5": Color(red: 0.96, green: 0.72, blue: 0.24),  // Banana
        "6": Color(red: 0.94, green: 0.60, blue: 0.22),  // Tangerine
        "7": Color(red: 0.10, green: 0.67, blue: 0.65),  // Peacock
        "8": Color(red: 0.38, green: 0.38, blue: 0.38),  // Graphite
        "9": Color(red: 0.31, green: 0.48, blue: 0.78),  // Blueberry
        "10": Color(red: 0.05, green: 0.62, blue: 0.07), // Basil
        "11": Color(red: 0.84, green: 0.28, blue: 0.17), // Tomato
    ]

    private static let defaultColor = Color(red: 0.26, green: 0.52, blue: 0.96)

    // MARK: - List Events

    func fetchEvents(for month: Date) async throws -> [CalendarEvent] {
        let token = try await auth.getValidToken()
        let cal = Calendar.current

        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        var comps = URLComponents(string: "\(baseURL)/calendars/primary/events")!
        comps.queryItems = [
            URLQueryItem(name: "timeMin", value: fmt.string(from: interval.start)),
            URLQueryItem(name: "timeMax", value: fmt.string(from: interval.end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "timeZone", value: TimeZone.current.identifier),
        ]

        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }

        return items.compactMap { parseEvent($0) }
    }

    // MARK: - Create Event

    func createEvent(title: String, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> CalendarEvent? {
        let token = try await auth.getValidToken()
        let url = URL(string: "\(baseURL)/calendars/primary/events")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["summary": title]
        if isAllDay {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            body["start"] = ["date": fmt.string(from: startDate)]
            body["end"] = ["date": fmt.string(from: endDate)]
        } else {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            body["start"] = ["dateTime": fmt.string(from: startDate), "timeZone": TimeZone.current.identifier]
            body["end"] = ["dateTime": fmt.string(from: endDate), "timeZone": TimeZone.current.identifier]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = parseEvent(json) else { throw URLError(.cannotParseResponse) }
        return event
    }

    // MARK: - Update Event

    func updateEvent(eventID: String, title: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> Bool {
        let token = try await auth.getValidToken()
        guard let encoded = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/calendars/primary/events/\(encoded)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Only include summary when the caller explicitly provides a new title
        var body: [String: Any] = title.map { ["summary": $0] } ?? [:]
        if isAllDay {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            body["start"] = ["date": fmt.string(from: startDate)]
            body["end"] = ["date": fmt.string(from: endDate)]
        } else {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            body["start"] = ["dateTime": fmt.string(from: startDate), "timeZone": TimeZone.current.identifier]
            body["end"] = ["dateTime": fmt.string(from: endDate), "timeZone": TimeZone.current.identifier]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Delete Event

    func deleteEvent(eventID: String) async throws -> Bool {
        let token = try await auth.getValidToken()
        guard let encoded = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/calendars/primary/events/\(encoded)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return code == 204 || code == 200
    }

    // MARK: - Parse

    private func parseEvent(_ json: [String: Any]) -> CalendarEvent? {
        guard let id = json["id"] as? String,
              let title = json["summary"] as? String else { return nil }

        let start = json["start"] as? [String: Any] ?? [:]
        let end = json["end"] as? [String: Any] ?? [:]

        let isAllDay = start["date"] != nil
        let startDate: Date
        let endDate: Date

        if isAllDay {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = TimeZone.current
            startDate = fmt.date(from: start["date"] as? String ?? "") ?? Date()
            endDate = fmt.date(from: end["date"] as? String ?? "") ?? Date()
        } else {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fmtBasic = ISO8601DateFormatter()
            fmtBasic.formatOptions = [.withInternetDateTime]

            let startStr = start["dateTime"] as? String ?? ""
            let endStr = end["dateTime"] as? String ?? ""
            startDate = fmt.date(from: startStr) ?? fmtBasic.date(from: startStr) ?? Date()
            endDate = fmt.date(from: endStr) ?? fmtBasic.date(from: endStr) ?? Date()
        }

        let colorId = json["colorId"] as? String ?? ""
        let color = Self.eventColors[colorId] ?? Self.defaultColor

        return CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            color: color,
            isAllDay: isAllDay,
            calendarName: "Google"
        )
    }
}
