import Foundation
import CloudKit

// MARK: - HermesMemoryFactV1
//
// Hermes 메모리가 CloudKit에 저장될 때 쓰는 CKRecord 스키마 버전 1.
// 스키마 해시가 바뀌면 sync가 깨지므로 **필드명과 타입은 고정**한다.
//
// 이 enum은 schema **정의만** 제공한다. 실제 CKDatabase 호출(fetch/save/subscribe)은
// M2 SYNC 팀장 구현부에서 담당한다. 이 파일은 encode/decode만 플랫폼 중립으로 구현.
public enum HermesMemoryFactV1 {

    /// CKRecordType name. 가볍게 바꾸면 호환 깨지므로 주의.
    public static let recordType = "HermesMemoryFactV1"

    /// CKRecord 안에서 사용되는 field key 이름들.
    public enum Field: String {
        case factId         = "factId"          // UUID String — MemoryFact.id.uuidString
        case text           = "text"            // `key`와 `value`를 `\u{001F}` 구분자로 이어붙인 단일 문자열
        case category       = "category"        // MemoryCategory.rawValue
        case source         = "source"          // String — MemoryFact.source (예: "chat", "planning")
        case updatedAt      = "updatedAt"       // Date — MemoryFact.updatedAt
        case weight         = "weight"          // Double — MemoryFact.confidence
        case schemaVersion  = "schemaVersion"   // Int — 현재 1
    }

    /// 현재 스키마 버전. 호환 깨는 변경 시 V2 enum을 새로 만들고 migration 경로 둔다.
    public static let currentSchemaVersion: Int = 1

    /// key/value를 하나의 text 필드로 이어붙일 때 쓰는 구분자 (US — Unit Separator).
    /// 사용자 입력에 나타날 확률이 0에 가까운 control character 선택.
    public static let textSeparator: Character = "\u{001F}"

    // MARK: - Encode

    /// MemoryFact → CKRecord. recordName은 fact.id.uuidString을 사용한다.
    public static func encode(fact: MemoryFact, zoneID: CKRecordZone.ID? = nil) -> CKRecord {
        let recordID: CKRecord.ID
        if let zoneID {
            recordID = CKRecord.ID(recordName: fact.id.uuidString, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: fact.id.uuidString)
        }
        let record = CKRecord(recordType: recordType, recordID: recordID)
        apply(fact: fact, to: record)
        return record
    }

    /// 기존 CKRecord에 fact 내용을 덮어쓴다 (save 재시도 시 사용).
    public static func apply(fact: MemoryFact, to record: CKRecord) {
        record[Field.factId.rawValue]        = fact.id.uuidString as NSString
        record[Field.text.rawValue]          = joinText(key: fact.key, value: fact.value) as NSString
        record[Field.category.rawValue]      = fact.category.rawValue as NSString
        record[Field.source.rawValue]        = fact.source as NSString
        record[Field.updatedAt.rawValue]     = fact.updatedAt as NSDate
        record[Field.weight.rawValue]        = fact.confidence as NSNumber
        record[Field.schemaVersion.rawValue] = currentSchemaVersion as NSNumber
    }

    // MARK: - Decode

    /// CKRecord → MemoryFact. 필수 필드 누락 또는 미지원 schemaVersion 시 nil 반환.
    public static func decode(record: CKRecord) -> MemoryFact? {
        guard record.recordType == recordType else { return nil }

        // 미래 schema에서 온 레코드는 silent-drop — 상위 버전의 필드를 해석할 수 없음.
        let recordSchema = (record[Field.schemaVersion.rawValue] as? Int) ?? currentSchemaVersion
        guard recordSchema <= currentSchemaVersion else { return nil }

        let factIdString = (record[Field.factId.rawValue] as? String) ?? record.recordID.recordName
        guard let factId = UUID(uuidString: factIdString) else { return nil }

        guard let text = record[Field.text.rawValue] as? String else { return nil }
        let (key, value) = splitText(text)

        let categoryRaw = (record[Field.category.rawValue] as? String) ?? MemoryCategory.preference.rawValue
        let category = MemoryCategory(rawValue: categoryRaw) ?? .preference

        let source = (record[Field.source.rawValue] as? String) ?? "cloudkit"
        let updatedAt = (record[Field.updatedAt.rawValue] as? Date) ?? Date()
        let weight = (record[Field.weight.rawValue] as? Double) ?? 0.5

        return MemoryFact(
            id: factId,
            category: category,
            key: key,
            value: value,
            confidence: weight,
            source: source,
            updatedAt: updatedAt
        )
    }

    // MARK: - Text packing helpers

    public static func joinText(key: String, value: String) -> String {
        // key/value 안에 구분자가 있으면 split이 왜곡됨 → 입력 시 제거.
        // 실전 데이터(사용자 메모)에 US(\u{001F})가 자연 발생할 확률은 0에 가깝지만
        // 안전하게 방어한다. value는 원문 보존을 위해 split 후 재조합하지 않도록 first-only.
        let sep = String(textSeparator)
        let cleanKey = key.replacingOccurrences(of: sep, with: "")
        return cleanKey + sep + value
    }

    public static func splitText(_ text: String) -> (key: String, value: String) {
        // 구분자가 여러 개 있을 수 있으므로 **첫 구분자만** 기준으로 split.
        // joinText에서 key의 구분자는 제거했으므로, 남아있다면 value 안의 것.
        guard let sepRange = text.range(of: String(textSeparator)) else {
            return (key: text, value: "")
        }
        let key = String(text[..<sepRange.lowerBound])
        let value = String(text[sepRange.upperBound...])
        return (key: key, value: value)
    }
}
