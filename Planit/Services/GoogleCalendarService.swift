import Foundation
import SwiftUI

/// Direct Google Calendar REST API client — bypasses macOS Calendar/EventKit delay
@MainActor
final class GoogleCalendarService {
    private let auth: GoogleAuthManager
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    /// 세션 캐시: 한 번 불러온 캘린더 목록 재사용 (로그아웃 시 clearCache() 호출)
    private var cachedCalendars: [GoogleCalendarInfo]? = nil

    init(auth: GoogleAuthManager) {
        self.auth = auth
    }

    func clearCache() {
        cachedCalendars = nil
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

    // MARK: - Calendar List

    struct GoogleCalendarInfo {
        let id: String
        let name: String
        let color: Color     // backgroundColor hex에서 변환
        let accessRole: String
    }

    /// 사용자가 구독 중인 모든 캘린더 목록을 가져옴 (세션 캐시)
    func fetchCalendarList() async throws -> [GoogleCalendarInfo] {
        if let cached = cachedCalendars { return cached }

        let token = try await auth.getValidToken()
        var comps = URLComponents(string: "\(baseURL)/users/me/calendarList")!
        comps.queryItems = [
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "showHidden", value: "false"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }

        let calendars: [GoogleCalendarInfo] = items.compactMap { item in
            guard let id = item["id"] as? String,
                  let name = item["summary"] as? String,
                  let role = item["accessRole"] as? String else { return nil }
            // freeBusyReader도 이벤트 목록 조회 가능
            let hex = item["backgroundColor"] as? String ?? ""
            let color = Color(hex: hex) ?? Self.defaultColor
            return GoogleCalendarInfo(id: id, name: name, color: color, accessRole: role)
        }

        cachedCalendars = calendars
        return calendars
    }

    // MARK: - List Events (모든 캘린더)

    func fetchEvents(for month: Date) async throws -> [CalendarEvent] {
        let calendars = try await fetchCalendarList()
        guard !calendars.isEmpty else { return [] }

        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let timeMin = fmt.string(from: interval.start)
        let timeMax = fmt.string(from: interval.end)
        let token = try await auth.getValidToken()

        // 모든 캘린더를 병렬로 fetch, partial-succeed
        var allEvents: [CalendarEvent] = []
        await withTaskGroup(of: [CalendarEvent].self) { group in
            for calInfo in calendars {
                group.addTask {
                    do {
                        return try await self.fetchEventsForCalendar(
                            calInfo: calInfo,
                            token: token,
                            timeMin: timeMin,
                            timeMax: timeMax
                        )
                    } catch {
                        print("[Calen] 캘린더 fetch 실패 (\(calInfo.name)): \(error)")
                        return []
                    }
                }
            }
            for await events in group {
                allEvents.append(contentsOf: events)
            }
        }

        // 중복 제거 (같은 이벤트 ID가 여러 캘린더에서 오는 경우 대비)
        var seen = Set<String>()
        return allEvents.filter { seen.insert($0.id).inserted }
    }

    private func fetchEventsForCalendar(calInfo: GoogleCalendarInfo, token: String, timeMin: String, timeMax: String) async throws -> [CalendarEvent] {
        guard let encoded = calInfo.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var comps = URLComponents(string: "\(baseURL)/calendars/\(encoded)/events") else { return [] }

        comps.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
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

        return items.compactMap { parseEvent($0, calInfo: calInfo) }
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
              let event = parseEvent(json, calInfo: nil) else { throw URLError(.cannotParseResponse) }
        return event
    }

    // MARK: - Update Event

    /// 제목만 변경 (날짜 유지) — 이모지 제거 등 title-only 업데이트
    func patchEventTitle(eventID: String, title: String) async throws -> Bool {
        let token = try await auth.getValidToken()
        guard let encoded = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/calendars/primary/events/\(encoded)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["summary": title])
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

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

    private func parseEvent(_ json: [String: Any], calInfo: GoogleCalendarInfo?) -> CalendarEvent? {
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

        // 이벤트 자체의 colorId 우선, 없으면 캘린더 색상, 없으면 기본
        let colorId = json["colorId"] as? String ?? ""
        let color = Self.eventColors[colorId] ?? calInfo?.color ?? Self.defaultColor

        let calName = calInfo?.name ?? "Google"
        let calID = calInfo.map { "google:\($0.id)" } ?? "google:primary"

        return CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            color: color,
            isAllDay: isAllDay,
            calendarName: calName,
            calendarID: calID
        )
    }
}
