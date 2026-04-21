import Foundation
import CalenShared

// MARK: - WidgetDataPublisher
//
// 메인 앱이 오늘의 이벤트 스냅샷을 App Group으로 publish하는 경량 유틸.
//
// - 위젯 extension과의 계약: 같은 `EventSnapshot` / `EventSnapshotBundle` Codable 포맷을
//   공유한다. 포맷 정의는 CaleniOS/Widget/EventSnapshot.swift 에 있고, 본 파일에서도
//   소스 파일 복제 없이 **동일한 포맷 상수**(key, suite)만 inline 재정의해 타깃 간
//   의존성을 없앤다. 포맷은 Widget 스펙과 1:1로 일치해야 하므로 변경 시 두 곳을 함께
//   수정해야 한다 (EventSnapshot.swift 상단 주석 참조).
//
// - HomeViewModel을 건드리지 않고 외곽에서 호출(권장): 예) MainTabView의 onAppear나
//   Environment observer, 혹은 앱 내 background refresh 지점에서 `publish(events:)`.
//
// - 실패는 silent(콘솔 로그만). 위젯이 읽지 못하면 empty state fallback이 있으므로
//   앱 UX는 영향을 받지 않는다.
//
// 테스트: `Tests/WidgetDataPublisherTests.swift`가 Codable round-trip과 App Group URL
// resolve 경로(nil 허용)를 검증한다. App Group 자체는 Portal 등록이 필요하므로
// CI에서는 UserDefaults read/write 모킹으로 대체한다.

public enum WidgetDataPublisher {

    // MARK: - Shared constants (Widget target의 EventSnapshotBundle과 일치해야 함)

    /// UserDefaults suite name (App Group identifier).
    public static let appGroupIdentifier = "group.com.oy.planit"

    /// UserDefaults key. Widget extension도 같은 상수를 쓴다.
    public static let userDefaultsKey = "planit.widget.today-events.v1"

    /// `Documents/widget-events.json` fallback 파일명.
    public static let fallbackFileName = "widget-events.json"

    /// 현재 스키마 버전.
    public static let schemaVersion = 1

    /// 한 번에 publish 할 최대 이벤트 개수. 위젯은 최대 4개만 표시하지만 timeline 중
    /// 지나가는 이벤트를 대비해 여유를 둠.
    public static let maxEventCount = 10

    // MARK: - Public API

    /// `CalendarEvent` 배열을 받아 오늘 이후(=`now` 이후 종료) 이벤트만 `EventSnapshotPayload`로
    /// 변환 → App Group UserDefaults + 파일에 저장.
    ///
    /// - Parameters:
    ///   - events: 앱이 보유한 현재 이벤트 집합 (repo.events 등).
    ///   - now: 기준 시각. 테스트에서 override 가능. 기본은 `Date()`.
    public static func publish(
        events: [CalendarEvent],
        now: Date = Date()
    ) {
        let snapshots = makeSnapshots(from: events, now: now)
        let bundle = EventSnapshotPayload(
            schemaVersion: schemaVersion,
            publishedAt: now,
            events: snapshots
        )
        guard let data = try? encoder().encode(bundle) else {
            print("[WidgetDataPublisher] encode failed")
            return
        }

        // 1) App Group UserDefaults.
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            defaults.set(data, forKey: userDefaultsKey)
        } else {
            print("[WidgetDataPublisher] suite UserDefaults unavailable (group entitlement 없음)")
        }

        // 2) 파일 fallback (UserDefaults 실패 시 위젯이 읽을 수 있도록).
        if let url = Self.fileURL() {
            try? data.write(to: url, options: [.atomic])
        }
    }

    /// Repo의 `events` 배열을 받아 publish. HomeViewModel 수정 없이 MainTabView 등
    /// 외곽에서 repo 바인딩을 관찰하며 호출하는 용도.
    public static func publishFromRepo(_ events: [CalendarEvent]) {
        publish(events: events)
    }

    // MARK: - Snapshot conversion

    /// Pure function — CalendarEvent → EventSnapshotPayload 의 순서/필터 정책.
    /// now 이후 종료된 이벤트만 남기고, 시작시각 오름차순 정렬, 최대 `maxEventCount`.
    public static func makeSnapshots(
        from events: [CalendarEvent],
        now: Date = Date(),
        limit: Int = WidgetDataPublisher.maxEventCount
    ) -> [EventSnapshotPayload.Event] {
        events
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { ev in
                EventSnapshotPayload.Event(
                    id: "\(ev.calendarId)::\(ev.id)",
                    title: ev.title,
                    start: ev.startDate,
                    end: ev.endDate,
                    colorHex: ev.colorHex,
                    isAllDay: ev.isAllDay
                )
            }
    }

    // MARK: - URL resolution

    /// App Group 컨테이너의 `widget-events.json` URL. Portal 미등록 등으로 실패 시 nil.
    public static func fileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(fallbackFileName, isDirectory: false)
    }

    // MARK: - Encoder / Decoder

    public static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    public static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}

// MARK: - EventSnapshotPayload
//
// Widget extension의 `EventSnapshotBundle` / `EventSnapshot` 와 **동일한 JSON 스키마**를
// 가진 App-side 미러 타입. Widget target은 이 파일을 import하지 않고 자기 쪽 타입을
// 갖기 때문에, 이름은 달라도 coding key / shape이 정확히 일치해야 한다.
//
// 이중 정의의 이유: Widget extension을 CaleniOS 타겟에 의존시키지 않기 위해서 (App Group만
// 거쳐 JSON으로 데이터 교환).

public struct EventSnapshotPayload: Codable, Equatable {
    public let schemaVersion: Int
    public let publishedAt: Date
    public let events: [Event]

    public init(schemaVersion: Int, publishedAt: Date, events: [Event]) {
        self.schemaVersion = schemaVersion
        self.publishedAt = publishedAt
        self.events = events
    }

    public struct Event: Codable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let start: Date
        public let end: Date
        public let colorHex: String
        public let isAllDay: Bool

        public init(
            id: String,
            title: String,
            start: Date,
            end: Date,
            colorHex: String,
            isAllDay: Bool
        ) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.colorHex = colorHex
            self.isAllDay = isAllDay
        }
    }
}
