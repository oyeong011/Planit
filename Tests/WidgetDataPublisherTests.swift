import Foundation
import Combine
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

    @MainActor
    final class TestWidgetEventRepository: ObservableObject {
        @Published private(set) var events: [CalendarEvent]

        init(events: [CalendarEvent] = []) {
            self.events = events
        }

        func simulateFetch(_ events: [CalendarEvent]) {
            self.events = events
        }

        func create(_ event: CalendarEvent) {
            events.append(event)
        }

        func moveEvent(
            id: String,
            calendarId: String,
            startDate: Date,
            endDate: Date
        ) {
            guard let index = events.firstIndex(where: {
                $0.id == id && $0.calendarId == calendarId
            }) else { return }
            var event = events[index]
            event.startDate = startDate
            event.endDate = endDate
            events[index] = event
        }

        func updateTitle(
            id: String,
            calendarId: String,
            title: String
        ) {
            guard let index = events.firstIndex(where: {
                $0.id == id && $0.calendarId == calendarId
            }) else { return }
            var event = events[index]
            event.title = title
            events[index] = event
        }

        func delete(id: String, calendarId: String) {
            events.removeAll {
                $0.id == id && $0.calendarId == calendarId
            }
        }
    }

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

    @MainActor
    @Test("WidgetEventStreamObserver publishes after fetch, mutations, and login repo swap")
    func widgetEventStreamObserverPublishesForSixTriggers() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fetched = CalendarEvent(
            id: "fetched",
            calendarId: "cal-a",
            title: "초기 로드",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3600),
            colorHex: "#3B82F6"
        )
        let created = CalendarEvent(
            id: "created",
            calendarId: "cal-a",
            title: "새 일정",
            startDate: now.addingTimeInterval(4200),
            endDate: now.addingTimeInterval(5400),
            colorHex: "#F56691"
        )
        let swapped = CalendarEvent(
            id: "swapped",
            calendarId: "cal-b",
            title: "로그인 후 일정",
            startDate: now.addingTimeInterval(7200),
            endDate: now.addingTimeInterval(8100),
            colorHex: "#40C786"
        )

        let repository = TestWidgetEventRepository()
        var published: [[CalendarEvent]] = []
        let observer = WidgetEventStreamObserver { events in
            published.append(events)
        }

        observer.observe(repository.$events.eraseToAnyPublisher())
        #expect(published.count == 1)
        #expect(published.last == [])

        repository.simulateFetch([fetched])
        #expect(published.count == 2)
        #expect(published.last == [fetched])

        repository.create(created)
        #expect(published.count == 3)
        #expect(published.last?.map(\.id) == ["fetched", "created"])

        let movedStart = now.addingTimeInterval(1800)
        let movedEnd = now.addingTimeInterval(4800)
        repository.moveEvent(
            id: fetched.id,
            calendarId: fetched.calendarId,
            startDate: movedStart,
            endDate: movedEnd
        )
        #expect(published.count == 4)
        #expect(published.last?.first?.startDate == movedStart)
        #expect(published.last?.first?.endDate == movedEnd)

        repository.updateTitle(
            id: created.id,
            calendarId: created.calendarId,
            title: "업데이트된 일정"
        )
        #expect(published.count == 5)
        #expect(published.last?.last?.title == "업데이트된 일정")

        repository.delete(id: created.id, calendarId: created.calendarId)
        #expect(published.count == 6)
        #expect(published.last?.map(\.id) == ["fetched"])

        let swappedRepository = TestWidgetEventRepository(events: [swapped])
        observer.observe(swappedRepository.$events.eraseToAnyPublisher())
        #expect(published.count == 7)
        #expect(published.last == [swapped])
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
            #expect(url.isFileURL)
            #expect(url.lastPathComponent == "widget-events.json")
            #expect(url.pathExtension == "json")
        }
    }
}
