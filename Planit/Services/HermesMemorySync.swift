import Foundation
import CloudKit
import OSLog
@_exported import CalenShared

// MARK: - HermesMemorySync
//
// macOS → iOS 단방향 업스트림 동기화 (v0.1.0 P0).
// `HermesMemoryService` 로컬 SwiftData 저장소의 최근 fact 중 상위 N개를
// `HermesMemoryFactV1` CKRecord로 인코딩해 private DB의 default zone에
// `CKModifyRecordsOperation` (savePolicy: `.changedKeys`) 으로 배치 업로드한다.
//
// 본 서비스는 `HermesMemoryService` 본체를 수정하지 않고 **의존성 주입**만으로
// 접근한다. 업로드 실패 시 재시도 로직은 v0.1.1 이후로 미룬다 (현재는 throw만).
@MainActor
final class HermesMemorySync {

    // MARK: Configuration
    // Swift 6: @MainActor class의 static let은 기본 isolated. default parameter / nonisolated
    // init에서 참조해야 하므로 명시적으로 `nonisolated` 지정.

    /// 한 번의 upstream sync에서 업로드할 최근 fact 최대 개수.
    nonisolated static let defaultBatchLimit: Int = 200

    /// Background sync Timer 주기 (30분).
    nonisolated static let defaultSyncInterval: TimeInterval = 30 * 60

    /// 앱이 사용하는 iCloud 컨테이너 식별자.
    nonisolated static let cloudContainerIdentifier = "iCloud.com.oy.planit"

    // MARK: Dependencies

    private let hermesMemoryService: HermesMemoryService
    private let container: CKContainer
    private let database: CKDatabase
    private let logger = Logger(subsystem: "com.oy.planit", category: "hermes.sync")

    private var backgroundTimer: Timer?

    // MARK: Init

    init(
        hermesMemoryService: HermesMemoryService,
        container: CKContainer = CKContainer(identifier: HermesMemorySync.cloudContainerIdentifier)
    ) {
        self.hermesMemoryService = hermesMemoryService
        self.container = container
        self.database = container.privateCloudDatabase
    }

    deinit {
        backgroundTimer?.invalidate()
    }

    // MARK: - Public API

    /// 로컬 DB의 최근 N개 fact를 CloudKit private DB에 batch upload.
    ///
    /// - 기존 recordName(fact.id.uuidString) 충돌 시 `.changedKeys` policy로 overwrite.
    /// - 네트워크/권한 실패 시 throw (재시도는 v0.1.1 이후).
    public func syncUpstream(limit: Int = HermesMemorySync.defaultBatchLimit) async throws {
        let recentFacts = hermesMemoryService.recentFactsForSync(limit: limit)
        guard !recentFacts.isEmpty else {
            logger.debug("syncUpstream: 업로드할 fact 없음 — skip")
            return
        }

        let records = recentFacts.map { HermesMemoryFactV1.encode(fact: $0) }
        logger.info("syncUpstream: \(records.count, privacy: .public)개 fact 업로드 시작")

        do {
            try await modifyRecords(records)
            logger.info("syncUpstream: \(records.count, privacy: .public)개 fact 업로드 완료")
        } catch {
            logger.error("syncUpstream 실패: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// 30분 주기 Timer로 `syncUpstream()`을 반복 호출.
    ///
    /// 호출 즉시 1회 sync 후 interval마다 반복. 이미 예약되어 있으면 재예약.
    public func scheduleBackgroundSync(interval: TimeInterval = HermesMemorySync.defaultSyncInterval) {
        backgroundTimer?.invalidate()
        logger.info("scheduleBackgroundSync: \(Int(interval), privacy: .public)초 주기 예약")

        // 즉시 1회 실행
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.syncUpstream()
            } catch {
                self.logger.error("초기 syncUpstream 실패: \(String(describing: error), privacy: .public)")
            }
        }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.syncUpstream()
                } catch {
                    self.logger.error("주기 syncUpstream 실패: \(String(describing: error), privacy: .public)")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    /// Background timer 해제 (테스트·로그아웃·기능 비활성화용).
    public func stopBackgroundSync() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        logger.info("stopBackgroundSync: 타이머 해제")
    }

    // MARK: - CloudKit plumbing

    /// `CKModifyRecordsOperation`을 Swift concurrency로 래핑.
    ///
    /// `.changedKeys` savePolicy로 기존 레코드의 필드만 갱신 (서버 타임스탬프 보존).
    private func modifyRecords(_ records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(
                recordsToSave: records,
                recordIDsToDelete: nil
            )
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility
            // 본 사용처는 default zone (개인 DB). atomic 보장은 custom zone 필요.
            operation.isAtomic = false

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }
}

// MARK: - HermesMemoryService bridge

extension HermesMemoryService {
    /// Sync 업로드용 — 가장 최근 업데이트된 fact N개를 반환.
    ///
    /// `HermesMemoryService.facts`는 이미 `updatedAt` 내림차순으로 정렬되어 있다
    /// (`fetchFactRecords`의 SortDescriptor 참조). 본 메서드는 본체를 수정하지 않기
    /// 위한 얇은 read-only 어댑터다.
    func recentFactsForSync(limit: Int) -> [MemoryFact] {
        Array(facts.prefix(limit))
    }
}
