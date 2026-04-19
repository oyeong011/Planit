import Foundation

// MARK: - MemoryFetching

/// Hermes 메모리 저장소가 준수해야 할 조회 전용 인터페이스.
///
/// macOS는 `HermesMemoryService` (SwiftData + CloudKit) 가 준수.
/// iOS는 CloudKit read-only 어댑터가 준수 (M2 SYNC 팀장 몫).
public protocol MemoryFetching: Sendable {
    /// 최근 업데이트된 메모리 사실을 N개 조회.
    /// 정렬 기준: `updatedAt` 내림차순.
    func fetchRecentMemories(limit: Int) async throws -> [MemoryFact]
}
