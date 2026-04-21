import Foundation
import Testing
import CalenShared
@testable import CaleniOS

// MARK: - WidgetDataPublisherTests
//
// v0.1.1 홈스크린 위젯 — WidgetDataPublisher의 순수 로직 검증.
// App Group 자체는 Apple Developer Portal 등록이 필요하므로, 여기서는
//  1) CalendarEvent → EventSnapshotPayload.Event 변환 규칙
//  2) EventSnapshotPayload Codable round-trip
//  3) App Group 컨테이너 URL resolve (Portal 미등록 시 nil 허용)
// 세 가지 경로만 검증한다.

@Suite("WidgetDataPublisher")
struct WidgetDataPublisherTests {

    // MARK: - (1) CalendarEvent → snapshot 변환

    @Test("makeSnapshots filters past events and sorts by start")
    func makeSnapshotsFiltersAndSorts() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = CalendarEvent(
            id: "past",
            calendarId: "cal-a",
            title: "지난 일정",
            startDate: now.addingTimeInterval(-7200),
            endDate: now.addingTimeInterval(-3600),
            colorHex: "#3B82F6"
        )
        let later = CalendarEvent(
            id: "later",
            calendarId: "cal-a",
            title: "나중 일정",
            startDate: now.addingTimeInterval(7200),
            endDate: now.addingTimeInterval(10800),
            colorHex: "#F56691"
        )
        let soon = CalendarEvent(
            id: "soon",
            calendarId: "cal-b",
            title: "곧 시작",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3600),
            colorHex: "#40C786"
        )

        let snapshots = WidgetDataPublisher.makeSnapshots(
            from: [past, later, soon],
            now: now
        )

        #expect(snapshots.count == 2)
        #expect(snapshots[0].id == "cal-b::soon")
        #expect(snapshots[1].id == "cal-a::later")
        #expect(snapshots[0].title == "곧 시작")
        #expect(snapshots[0].colorHex == "#40C786")
    }

    @Test("makeSnapshots respects limit")
    func makeSnapshotsRespectsLimit() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = (0..<15).map { i in
            CalendarEvent(
                id: "e\(i)",
                calendarId: "cal",
                title: "일정 \(i)",
                startDate: now.addingTimeInterval(TimeInterval(i * 600)),
                endDate: now.addingTimeInterval(TimeInterval(i * 600 + 1800)),
                colorHex: "#3B82F6"
            )
        }
        let snapshots = WidgetDataPublisher.makeSnapshots(from: events, now: now, limit: 5)
        #expect(snapshots.count == 5)
        #expect(snapshots.first?.id == "cal::e0")
        #expect(snapshots.last?.id == "cal::e4")
    }

    // MARK: - (2) Codable round-trip

    @Test("EventSnapshotPayload encodes and decodes losslessly")
    func payloadRoundTrip() throws {
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let start = publishedAt.addingTimeInterval(600)
        let end = publishedAt.addingTimeInterval(3600)
        let original = EventSnapshotPayload(
            schemaVersion: 1,
            publishedAt: publishedAt,
            events: [
                EventSnapshotPayload.Event(
                    id: "cal::abc",
                    title: "라운드트립 테스트",
                    start: start,
                    end: end,
                    colorHex: "#3B82F6",
                    isAllDay: false
                )
            ]
        )

        let data = try WidgetDataPublisher.encoder().encode(original)
        let decoded = try WidgetDataPublisher.decoder().decode(EventSnapshotPayload.self, from: data)

        #expect(decoded == original)
        #expect(decoded.events.first?.title == "라운드트립 테스트")
        #expect(decoded.schemaVersion == 1)
    }

    // MARK: - (3) App Group URL resolve

    @Test("fileURL returns nil or valid path but never crashes")
    func fileURLResolvesSafely() {
        // Portal 미등록 환경(CI, 워크트리 빌드)에서는 nil이 정상.
        // Portal 등록된 환경이라면 .json 으로 끝나는 URL 반환.
        let url = WidgetDataPublisher.fileURL()
        if let url {
            #expect(url.lastPathComponent == "widget-events.json")
        } else {
            #expect(Bool(true)) // nil 허용
        }
    }

    @Test("publish does not throw when group container is missing")
    func publishIsSafeWithoutContainer() {
        // App Group entitlement 없는 환경에서 publish 호출해도 crash / throw 없어야 함
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = CalendarEvent(
            id: "safety",
            calendarId: "cal",
            title: "safety net",
            startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(3600),
            colorHex: "#3B82F6"
        )
        WidgetDataPublisher.publish(events: [event], now: now)
        // 도달하면 성공.
        #expect(true)
    }
}
