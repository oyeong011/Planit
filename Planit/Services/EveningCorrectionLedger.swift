import Foundation

struct EveningCorrectionRecord: Codable, Equatable {
    enum Result: String, Codable {
        case started
        case planned
        case applied
        case skipped
        case failed
    }

    enum ApplyMode: String, Codable {
        case manual
        case automatic
    }

    let reviewDateKey: String
    var startedAt: Date
    var result: Result
    var itemCount: Int
    var applyMode: ApplyMode
    var failureReason: String?
}

final class EveningCorrectionLedger {
    static let storageKey = "calen.review.eveningCorrectionLedger"

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = EveningCorrectionLedger.storageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func recordStarted(
        reviewDateKey: String,
        startedAt: Date = Date(),
        applyMode: EveningCorrectionRecord.ApplyMode
    ) {
        upsertRecord(for: reviewDateKey) { existing in
            EveningCorrectionRecord(
                reviewDateKey: reviewDateKey,
                startedAt: startedAt,
                result: .started,
                itemCount: existing?.itemCount ?? 0,
                applyMode: applyMode,
                failureReason: nil
            )
        }
    }

    func recordResult(
        reviewDateKey: String,
        result: EveningCorrectionRecord.Result,
        itemCount: Int,
        applyMode: EveningCorrectionRecord.ApplyMode,
        failureReason: String? = nil
    ) {
        upsertRecord(for: reviewDateKey) { existing in
            EveningCorrectionRecord(
                reviewDateKey: reviewDateKey,
                startedAt: existing?.startedAt ?? Date(),
                result: result,
                itemCount: max(0, itemCount),
                applyMode: applyMode,
                failureReason: Self.redactedFailureReason(from: failureReason)
            )
        }
    }

    func recordFailure(
        reviewDateKey: String,
        itemCount: Int,
        applyMode: EveningCorrectionRecord.ApplyMode,
        failureReason: String
    ) {
        recordResult(
            reviewDateKey: reviewDateKey,
            result: .failed,
            itemCount: itemCount,
            applyMode: applyMode,
            failureReason: failureReason
        )
    }

    func record(for reviewDateKey: String) -> EveningCorrectionRecord? {
        loadRecords()[reviewDateKey]
    }

    func allRecords() -> [EveningCorrectionRecord] {
        loadRecords()
            .values
            .sorted {
                if $0.reviewDateKey != $1.reviewDateKey {
                    return $0.reviewDateKey < $1.reviewDateKey
                }
                return $0.startedAt < $1.startedAt
            }
    }

    private func upsertRecord(
        for reviewDateKey: String,
        update: (EveningCorrectionRecord?) -> EveningCorrectionRecord
    ) {
        var records = loadRecords()
        records[reviewDateKey] = update(records[reviewDateKey])
        saveRecords(records)
    }

    private func loadRecords() -> [String: EveningCorrectionRecord] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? decoder.decode([String: EveningCorrectionRecord].self, from: data)) ?? [:]
    }

    private func saveRecords(_ records: [String: EveningCorrectionRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func redactedFailureReason(from raw: String?) -> String? {
        guard let raw else { return nil }

        let normalized = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        let lower = normalized.lowercased()
        if lower.contains("calendar write timed out") {
            return "calendar write timed out"
        }
        if lower.contains("timed out"), lower.contains("calendar") || lower.contains("event") || lower.contains("apply") {
            return "calendar write timed out"
        }
        if lower.contains("timed out") {
            return "operation timed out"
        }
        if lower.contains("unauthorized") || lower.contains("forbidden") || lower.contains("permission") {
            return "authorization error"
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("connection") {
            return "network error"
        }

        let hasPrivateMarkers =
            normalized.contains("\"") ||
            normalized.contains("'") ||
            lower.contains("title ") ||
            lower.contains("title=") ||
            lower.contains("event ") ||
            lower.contains("event=") ||
            lower.contains("todo ") ||
            lower.contains("todo=")

        if hasPrivateMarkers {
            return "redacted failure"
        }

        return String(normalized.prefix(120))
    }
}
