import Foundation

// MARK: - EventRepository
//
// 캘린더 이벤트 CRUD 추상화. View/ViewModel이 Google/EventKit/fake 구현을
// 모두 동일 인터페이스로 다룰 수 있게 한다.
//
// - `events(in:)`는 조회 전용. 캐시/네트워크 정책은 구현체 책임.
// - `create`는 draft → 서버 할당 id를 포함한 완전한 event를 반환.
// - `update/delete`는 원자적. 실패 시 throw (호출자가 rollback).
// - Sendable 프로토콜: 모든 구현체는 actor 또는 @MainActor final class.

public protocol EventRepository: Sendable {
    /// 주어진 기간과 겹치는(overlapping) 이벤트 목록을 반환.
    /// "겹침" = `event.endDate > interval.start && event.startDate < interval.end`.
    func events(in interval: DateInterval) async throws -> [CalendarEvent]

    /// Draft로부터 이벤트 생성. 성공 시 id/etag/updated가 채워진 완전한 event 반환.
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEvent

    /// 기존 이벤트 업데이트(드래그 이동, 리사이즈, 제목 편집 등).
    /// 성공 시 갱신된 etag/updated를 포함한 새 event 반환.
    func update(_ event: CalendarEvent) async throws -> CalendarEvent

    /// 이벤트 삭제.
    func delete(_ event: CalendarEvent) async throws
}
