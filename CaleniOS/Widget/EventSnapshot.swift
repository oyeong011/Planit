// MARK: - EventSnapshot
//
// Widget ↔ 메인 앱 사이에서 교환되는 경량 value type.
//
// - Widget extension은 `CalenShared`(SwiftPM 패키지)에 의존하지 않고 순수
//   Foundation / WidgetKit만 쓴다. 그래서 `CalendarEvent`의 공유 포맷을 그대로 쓰기보다
//   위젯 요건(오늘의 다음 2~4개 일정)에만 필요한 필드만 뽑아 별도 Codable 구조체로 정의한다.
// - App Group `UserDefaults(suiteName:)` 또는 `Documents/widget-events.json` 파일로
//   직렬화 저장되며, `WidgetDataProvider`가 decode한다.
// - 포맷 버전은 `schemaVersion`으로 관리(앱 업데이트와 위젯 재빌드 타이밍 불일치 대비).

import Foundation

public struct EventSnapshot: Codable, Hashable, Identifiable {
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

// MARK: - EventSnapshotBundle
//
// 여러 개의 EventSnapshot을 버전 정보와 함께 번들로 묶는 Codable 컨테이너.
// (단순 `[EventSnapshot]` Codable 대비, 미래의 스키마 변경을 위해 한 단계 둔다.)

public struct EventSnapshotBundle: Codable {
    /// 포맷 호환성 체크용. v0.1.1 = 1.
    public let schemaVersion: Int

    /// 앱이 마지막으로 publish한 시각(위젯 staleness 판단에 사용).
    public let publishedAt: Date

    /// 시작시각 오름차순 정렬된 이벤트들.
    public let events: [EventSnapshot]

    public init(
        schemaVersion: Int = EventSnapshotBundle.currentSchemaVersion,
        publishedAt: Date = Date(),
        events: [EventSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.publishedAt = publishedAt
        self.events = events
    }

    /// 현재 위젯/앱이 쓰는 스키마 버전 상수.
    public static let currentSchemaVersion = 1

    // MARK: JSON helpers

    /// App Group UserDefaults에 저장할 때 쓰는 고정 key.
    public static let userDefaultsKey = "planit.widget.today-events.v1"

    /// App Group 식별자. 앱/위젯 공용.
    public static let appGroupIdentifier = "group.com.oy.planit"

    /// JSON 인코더 — ISO-8601 date 전략으로 타임존/일광절약시간 안전.
    public static func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    /// JSON 디코더 — 인코더와 쌍.
    public static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
