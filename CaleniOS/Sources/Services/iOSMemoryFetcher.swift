#if os(iOS)
import Foundation
import CloudKit
import OSLog
@_exported import CalenShared

// MARK: - iOSMemoryFetcher
//
// iOS v0.1.0 P0 — **read-only** CloudKit fetcher.
// macOS `HermesMemorySync`가 업로드한 `HermesMemoryFactV1` 레코드를 private DB의
// default zone에서 `updatedAt` 내림차순으로 조회해 `MemoryFact` 도메인 모델로 변환.
//
// iOS는 편집/삭제 UI 없음 — 본 fetcher도 read 경로만 노출한다.
@MainActor
public final class iOSMemoryFetcher: MemoryFetching {

    // MARK: Dependencies

    private let container: CKContainer
    private let database: CKDatabase
    private let logger = Logger(subsystem: "com.oy.planit.ios", category: "hermes.fetch")

    public init(container: CKContainer = CKContainer(identifier: "iCloud.com.oy.planit")) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    // MARK: - MemoryFetching

    /// 최근 업데이트된 메모리 사실을 `updatedAt` 내림차순으로 N개 조회.
    ///
    /// - 실패(네트워크/권한/계정 없음) 시 throw. 빈 결과는 `[]` 반환.
    /// - `decode(record:)`가 nil을 반환하는 레코드(미래 schema 등)는 silent-drop.
    public func fetchRecentMemories(limit: Int) async throws -> [MemoryFact] {
        logger.info("fetchRecentMemories: limit=\(limit, privacy: .public)")

        let query = CKQuery(
            recordType: HermesMemoryFactV1.recordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: HermesMemoryFactV1.Field.updatedAt.rawValue, ascending: false)
        ]

        let records = try await runQuery(query, limit: limit)
        let facts = records.compactMap { HermesMemoryFactV1.decode(record: $0) }

        logger.info("fetchRecentMemories: \(records.count, privacy: .public)개 레코드 → \(facts.count, privacy: .public)개 fact 디코드")
        return facts
    }

    // MARK: - CloudKit plumbing

    /// `CKQueryOperation`을 Swift concurrency로 래핑. default zone의 private DB 조회.
    private func runQuery(_ query: CKQuery, limit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
            var collected: [CKRecord] = []
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = limit
            operation.zoneID = CKRecordZone.default().zoneID
            operation.qualityOfService = .userInitiated

            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    collected.append(record)
                case .failure:
                    // 개별 레코드 오류는 무시 — 상위에서 완료 결과로 판정.
                    break
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: collected)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }
}
#endif
