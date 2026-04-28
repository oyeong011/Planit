#if os(iOS)
import Foundation
import CloudKit
import SwiftData

// MARK: - CalendarEventV1 (Sprint A)
//
// 일정(Event)을 CloudKit private DB에 동기화할 때 사용하는 CKRecord 스키마 v1.
// macOS Calen이 write 권한 보유, iOS는 read + 풀 CRUD.
//
// 충돌 해결:
//  - `updatedAt` 최신 우선
//  - 동일 timestamp 시 `origin == "macOS"` 우선
//  - 삭제는 `deletedAt` soft delete (30일 후 hard purge)
//
// 스키마 변경 시 V2 enum을 새로 만들고 마이그레이션 경로를 둔다 (필드명/타입 고정).

public enum CalendarEventV1 {

    public static let recordType = "CalendarEventV1"
    public static let currentSchemaVersion: Int = 1

    public enum Field: String {
        case eventId        = "eventId"          // String UUID — primary key
        case calendarId     = "calendarId"       // String — Google Calendar ID 또는 "local"
        case title          = "title"            // String
        case startAt        = "startAt"          // Date
        case endAt          = "endAt"            // Date
        case location       = "location"         // String? (optional)
        case notes          = "notes"            // String? (optional)
        case colorIndex     = "colorIndex"       // Int — 카테고리 색 인덱스 (0..7)
        case source         = "source"           // String — "google" | "apple" | "local"
        case origin         = "origin"           // String — "macOS" | "iOS" (충돌 추적)
        case updatedAt      = "updatedAt"        // Date
        case deletedAt      = "deletedAt"        // Date? (soft delete; 30일 후 purge)
        case schemaVersion  = "schemaVersion"    // Int — 현재 1
    }

    // MARK: - Encode

    public static func encode(event: CalenSyncEvent, zoneID: CKRecordZone.ID? = nil) -> CKRecord {
        let recordID: CKRecord.ID = {
            if let zoneID { return CKRecord.ID(recordName: event.eventId, zoneID: zoneID) }
            return CKRecord.ID(recordName: event.eventId)
        }()
        let record = CKRecord(recordType: recordType, recordID: recordID)
        apply(event: event, to: record)
        return record
    }

    public static func apply(event: CalenSyncEvent, to record: CKRecord) {
        record[Field.eventId.rawValue]       = event.eventId as NSString
        record[Field.calendarId.rawValue]    = event.calendarId as NSString
        record[Field.title.rawValue]         = event.title as NSString
        record[Field.startAt.rawValue]       = event.startAt as NSDate
        record[Field.endAt.rawValue]         = event.endAt as NSDate
        record[Field.location.rawValue]      = event.location as NSString?
        record[Field.notes.rawValue]         = event.notes as NSString?
        record[Field.colorIndex.rawValue]    = event.colorIndex as NSNumber
        record[Field.source.rawValue]        = event.source.rawValue as NSString
        record[Field.origin.rawValue]        = event.origin.rawValue as NSString
        record[Field.updatedAt.rawValue]     = event.updatedAt as NSDate
        record[Field.deletedAt.rawValue]     = event.deletedAt as NSDate?
        record[Field.schemaVersion.rawValue] = currentSchemaVersion as NSNumber
    }

    // MARK: - Decode

    public static func decode(record: CKRecord) -> CalenSyncEvent? {
        guard record.recordType == recordType else { return nil }

        let recordSchema = (record[Field.schemaVersion.rawValue] as? Int) ?? currentSchemaVersion
        guard recordSchema <= currentSchemaVersion else { return nil }

        let eventId = (record[Field.eventId.rawValue] as? String) ?? record.recordID.recordName
        guard !eventId.isEmpty else { return nil }
        guard let title = record[Field.title.rawValue] as? String else { return nil }
        guard let startAt = record[Field.startAt.rawValue] as? Date else { return nil }
        guard let endAt = record[Field.endAt.rawValue] as? Date else { return nil }

        let calendarId = (record[Field.calendarId.rawValue] as? String) ?? "local"
        let colorIndex = (record[Field.colorIndex.rawValue] as? Int) ?? 0
        let sourceRaw  = (record[Field.source.rawValue] as? String) ?? "local"
        let originRaw  = (record[Field.origin.rawValue] as? String) ?? "iOS"

        return CalenSyncEvent(
            eventId: eventId,
            calendarId: calendarId,
            title: title,
            startAt: startAt,
            endAt: endAt,
            location: record[Field.location.rawValue] as? String,
            notes: record[Field.notes.rawValue] as? String,
            colorIndex: colorIndex,
            source: CalenSyncEvent.Source(rawValue: sourceRaw) ?? .local,
            origin: CalenSyncEvent.Origin(rawValue: originRaw) ?? .iOS,
            updatedAt: (record[Field.updatedAt.rawValue] as? Date) ?? Date(),
            deletedAt: record[Field.deletedAt.rawValue] as? Date
        )
    }
}

// MARK: - CalenSyncEvent (iOS 동기화 전용 도메인 모델)
//
// CalenShared 의 `CalendarEvent` 와 의도적으로 분리. CalenShared 모델은 Google/Apple
// Calendar 의 platform-neutral 표현이라 etag/isReadOnly/colorHex 등을 보유한다.
// 본 타입은 **CloudKit 동기화 전용** 으로 origin/deletedAt/colorIndex/pendingPush 등
// sync 메타를 포함한다. 두 모델 간 매핑은 별도 어댑터에서 담당.

public struct CalenSyncEvent: Identifiable, Hashable, Sendable {
    public var eventId: String
    public var calendarId: String
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var location: String?
    public var notes: String?
    public var colorIndex: Int
    public var source: Source
    public var origin: Origin
    public var updatedAt: Date
    public var deletedAt: Date?

    public var id: String { eventId }
    public var isDeleted: Bool { deletedAt != nil }

    public enum Source: String, Codable, Sendable, CaseIterable {
        case google, apple, cloudkit, local
    }

    public enum Origin: String, Codable, Sendable, CaseIterable {
        case macOS, iOS
    }

    public init(
        eventId: String = UUID().uuidString,
        calendarId: String,
        title: String,
        startAt: Date,
        endAt: Date,
        location: String? = nil,
        notes: String? = nil,
        colorIndex: Int = 0,
        source: Source = .local,
        origin: Origin = .iOS,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.eventId = eventId
        self.calendarId = calendarId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.location = location
        self.notes = notes
        self.colorIndex = colorIndex
        self.source = source
        self.origin = origin
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - SwiftData Cache Record

@Model
public final class CalendarEventRecord {
    @Attribute(.unique) public var eventId: String
    public var calendarId: String
    public var title: String
    public var startAt: Date
    public var endAt: Date
    public var location: String?
    public var notes: String?
    public var colorIndex: Int
    public var sourceRaw: String
    public var originRaw: String
    public var updatedAt: Date
    public var deletedAt: Date?
    /// CloudKit push 대기 큐. true = 로컬 변경 있음, push 미완료.
    public var pendingPush: Bool

    public init(
        eventId: String, calendarId: String, title: String,
        startAt: Date, endAt: Date,
        location: String? = nil, notes: String? = nil,
        colorIndex: Int = 0,
        sourceRaw: String = "local",
        originRaw: String = "iOS",
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        pendingPush: Bool = false
    ) {
        self.eventId = eventId
        self.calendarId = calendarId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.location = location
        self.notes = notes
        self.colorIndex = colorIndex
        self.sourceRaw = sourceRaw
        self.originRaw = originRaw
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.pendingPush = pendingPush
    }

    public func toDomain() -> CalenSyncEvent {
        CalenSyncEvent(
            eventId: eventId,
            calendarId: calendarId,
            title: title,
            startAt: startAt,
            endAt: endAt,
            location: location,
            notes: notes,
            colorIndex: colorIndex,
            source: CalenSyncEvent.Source(rawValue: sourceRaw) ?? .local,
            origin: CalenSyncEvent.Origin(rawValue: originRaw) ?? .iOS,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    public static func from(_ event: CalenSyncEvent, pendingPush: Bool = true) -> CalendarEventRecord {
        CalendarEventRecord(
            eventId: event.eventId,
            calendarId: event.calendarId,
            title: event.title,
            startAt: event.startAt,
            endAt: event.endAt,
            location: event.location,
            notes: event.notes,
            colorIndex: event.colorIndex,
            sourceRaw: event.source.rawValue,
            originRaw: event.origin.rawValue,
            updatedAt: event.updatedAt,
            deletedAt: event.deletedAt,
            pendingPush: pendingPush
        )
    }
}

// MARK: - 충돌 해결

public enum CalenSyncEventConflict {
    /// updatedAt 최신 우선. 동일 timestamp 시 macOS origin 우선.
    public static func resolve(local: CalenSyncEvent, remote: CalenSyncEvent) -> CalenSyncEvent {
        if remote.updatedAt > local.updatedAt { return remote }
        if remote.updatedAt < local.updatedAt { return local }
        // 동일 timestamp
        if remote.origin == .macOS && local.origin != .macOS { return remote }
        return local
    }
}
#endif
