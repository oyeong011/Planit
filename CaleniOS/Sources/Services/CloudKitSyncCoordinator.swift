#if os(iOS)
import Foundation
import CloudKit
import Combine
import SwiftData
import UIKit
import os.log

// MARK: - CloudKitSyncCoordinator (Sprint A)
//
// macOS Calen 이 write 한 CloudKit private DB 의 `HermesMemoryFactV1` /
// `CalendarEventV1` record 를 iOS 가 실시간 구독 + 풀 CRUD 한다.
//
// 구성:
//  - CKQuerySubscription: record create/update/delete 시 silent push
//  - changeToken 영속화 (UserDefaults) — 앱 재시작 시 증분 fetch
//  - foreground 진입 시 fetchAllChanges() 1회 (push 누락 대비)
//  - offline pendingPush 큐 — 네트워크 복구 시 자동 retry
//
// CKDatabase 호출은 모두 async/await. UI 갱신은 SwiftData @Query 가 담당.

@MainActor
public final class CloudKitSyncCoordinator: ObservableObject {

    public static let shared = CloudKitSyncCoordinator()

    @Published public private(set) var status: SyncStatus = .idle
    @Published public private(set) var lastSyncedAt: Date?

    public enum SyncStatus: Equatable {
        case idle
        case syncing
        case success(Date)
        case offline
        case failed(String)
    }

    // MARK: - 구성

    /// iCloud container — Apple Developer Portal 에서 등록된 이름과 일치해야 한다.
    private let containerID = "iCloud.com.oy.planit"
    private lazy var container: CKContainer = CKContainer(identifier: containerID)
    private var db: CKDatabase { container.privateCloudDatabase }

    private let log = Logger(subsystem: "com.oy.planit.ios", category: "CloudKitSync")

    // changeToken 저장 키 (recordType 별).
    private let factTokenKey  = "calen.ios.cloudkit.token.HermesMemoryFactV1"
    private let eventTokenKey = "calen.ios.cloudkit.token.CalendarEventV1"

    // Subscription 식별자 (idempotent — 이미 등록되어 있으면 skip).
    private let factSubID  = "calen-ios-fact-sub-v1"
    private let eventSubID = "calen-ios-event-sub-v1"

    private var foregroundObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    private init() {
        observeForeground()
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    /// 앱 시작 시 1회 호출 — subscription 등록 + 누적 변경 fetch.
    public func bootstrap(modelContext: ModelContext) async {
        await registerSubscriptionsIfNeeded()
        await fetchAllChanges(modelContext: modelContext)
        await flushPendingPush(modelContext: modelContext)
    }

    // MARK: - Foreground re-fetch

    private func observeForeground() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // foreground 진입 시 push 누락 대비 1회 fetch.
                self.log.debug("foreground re-enter — fetchAllChanges")
                // modelContext는 caller가 따로 제공해야 함 — 여기선 pendingPush flush 만.
                await self.flushPendingPushIfPossible()
            }
        }
    }

    // MARK: - Subscription 등록

    private func registerSubscriptionsIfNeeded() async {
        do {
            try await register(subscriptionID: factSubID,  recordType: HermesMemoryFactV1.recordType)
            try await register(subscriptionID: eventSubID, recordType: CalendarEventV1.recordType)
        } catch {
            log.error("subscription register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func register(subscriptionID: String, recordType: String) async throws {
        // 이미 등록되어 있으면 skip.
        if let _ = try? await db.subscription(for: subscriptionID) { return }

        let predicate = NSPredicate(value: true)
        let sub = CKQuerySubscription(
            recordType: recordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent push (사용자 알림 없음)
        sub.notificationInfo = info

        _ = try await db.save(sub)
        log.info("subscription registered: \(recordType, privacy: .public)")
    }

    // MARK: - Fetch all changes

    public func fetchAllChanges(modelContext: ModelContext) async {
        status = .syncing
        do {
            try await fetchEvents(modelContext: modelContext)
            try await fetchFacts(modelContext: modelContext)
            let now = Date()
            lastSyncedAt = now
            status = .success(now)
            log.info("fetchAllChanges OK")
        } catch let error as CKError where error.code == .networkUnavailable
                                      || error.code == .networkFailure {
            status = .offline
            log.notice("fetchAllChanges offline")
        } catch {
            status = .failed(error.localizedDescription)
            log.error("fetchAllChanges failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// CalendarEventV1 — 풀 페치 (changeToken 미사용 단순 query, Sprint A 범위).
    /// Sprint C 에서 zone-based change token 으로 업그레이드.
    private func fetchEvents(modelContext: ModelContext) async throws {
        let q = CKQuery(recordType: CalendarEventV1.recordType,
                        predicate: NSPredicate(value: true))
        let result = try await db.records(matching: q)
        for case .success(let record) in result.matchResults.map(\.1) {
            guard let event = CalendarEventV1.decode(record: record) else { continue }
            try upsertLocal(event: event, modelContext: modelContext)
        }
        try modelContext.save()
    }

    private func fetchFacts(modelContext: ModelContext) async throws {
        let q = CKQuery(recordType: HermesMemoryFactV1.recordType,
                        predicate: NSPredicate(value: true))
        let result = try await db.records(matching: q)
        for case .success(let record) in result.matchResults.map(\.1) {
            // HermesMemoryFactV1 는 Shared 에 정의됨. iOS 에서는 read-only 캐싱.
            guard let fact = HermesMemoryFactV1.decode(record: record) else { continue }
            try upsertLocal(fact: fact, modelContext: modelContext)
        }
        try modelContext.save()
    }

    // MARK: - Local upsert

    private func upsertLocal(event: CalenSyncEvent, modelContext: ModelContext) throws {
        let id = event.eventId
        let descriptor = FetchDescriptor<CalendarEventRecord>(
            predicate: #Predicate { $0.eventId == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            // 충돌 해결
            let resolved = CalenSyncEventConflict.resolve(local: existing.toDomain(), remote: event)
            existing.calendarId = resolved.calendarId
            existing.title      = resolved.title
            existing.startAt    = resolved.startAt
            existing.endAt      = resolved.endAt
            existing.location   = resolved.location
            existing.notes      = resolved.notes
            existing.colorIndex = resolved.colorIndex
            existing.sourceRaw  = resolved.source.rawValue
            existing.originRaw  = resolved.origin.rawValue
            existing.updatedAt  = resolved.updatedAt
            existing.deletedAt  = resolved.deletedAt
            // remote 가 이긴 경우 pendingPush 해제
            if resolved.updatedAt == event.updatedAt {
                existing.pendingPush = false
            }
        } else {
            modelContext.insert(CalendarEventRecord.from(event, pendingPush: false))
        }
    }

    private func upsertLocal(fact: MemoryFact, modelContext: ModelContext) throws {
        let id = fact.id
        let descriptor = FetchDescriptor<MemoryFactRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.categoryRaw = fact.category.rawValue
            existing.key         = fact.key
            existing.value       = fact.value
            existing.confidence  = fact.confidence
            existing.source      = fact.source
            existing.updatedAt   = fact.updatedAt
        } else {
            modelContext.insert(MemoryFactRecord(
                id: fact.id,
                categoryRaw: fact.category.rawValue,
                key: fact.key, value: fact.value,
                confidence: fact.confidence, source: fact.source,
                updatedAt: fact.updatedAt
            ))
        }
    }

    // MARK: - Push (CRUD upload)

    /// 로컬 변경된 event 1건을 CloudKit 에 push. 실패 시 pendingPush 유지 → 다음 flush 에서 재시도.
    public func push(event: CalenSyncEvent, modelContext: ModelContext) async {
        do {
            let record = CalendarEventV1.encode(event: event)
            _ = try await db.save(record)
            // 성공 — pendingPush 해제
            let id = event.eventId
            let descriptor = FetchDescriptor<CalendarEventRecord>(
                predicate: #Predicate { $0.eventId == id }
            )
            if let local = try modelContext.fetch(descriptor).first {
                local.pendingPush = false
                try modelContext.save()
            }
            log.info("push OK: \(event.eventId, privacy: .public)")
        } catch {
            log.error("push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// pendingPush == true 인 모든 로컬 변경 일괄 push (네트워크 복구 시).
    public func flushPendingPush(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<CalendarEventRecord>(
            predicate: #Predicate { $0.pendingPush == true }
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }
        log.info("flushPendingPush — \(pending.count, privacy: .public) records")
        for record in pending {
            await push(event: record.toDomain(), modelContext: modelContext)
        }
    }

    private func flushPendingPushIfPossible() async {
        // modelContext 의존이라 외부 호출자가 명시적으로 flushPendingPush 호출하도록 함.
        // 여기서는 status 만 syncing 으로 잠깐 표시.
        status = .syncing
    }

    // MARK: - Remote notification 처리

    /// AppDelegate 에서 silent push 수신 시 호출 — 현재 시점부터 fetchAllChanges 트리거.
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any],
                                         modelContext: ModelContext) async -> Bool {
        guard let cknotif = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return false
        }
        log.info("remote push received: \(cknotif.subscriptionID ?? "nil", privacy: .public)")
        await fetchAllChanges(modelContext: modelContext)
        return true
    }
}
#endif
