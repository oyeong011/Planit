#if os(iOS)
import Foundation
import Combine
import CalenShared

// MARK: - GoogleCalendarRepository
//
// Phase B M4: Google Calendar 실연동 `EventRepository` 구현체.
//
// 관계:
//   View/ViewModel  →  EventRepository (protocol)
//                       ├ FakeEventRepository        (미로그인 / 프리뷰 / QA)
//                       └ GoogleCalendarRepository   (로그인 시, 이 파일)
//                                ↓
//                         GoogleCalendarClient (Shared)
//                                ↓
//                         CalendarAuthProviding → iOSGoogleAuthManager
//
// 책임:
//   1. REST client 호출 단순 위임
//   2. `@Published events` in-memory cache → UI 반응성
//   3. fetch 실패 시 기존 캐시 유지 + throw (호출자가 토스트)
//   4. write 후 서버 응답으로 cache 동기화
//
// 비책임 (Phase C 이후):
//   - offline queue (네트워크 복구 후 재시도)
//   - recurring exception edit ("이 인스턴스만 vs 전체 수정" UI)
//   - 다중 캘린더 (현재는 init(calendarId:)로 primary 고정)
//   - ETag 기반 conflict 감지 (Phase C에서 412 → refetch+diff UI)

@MainActor
public final class GoogleCalendarRepository: EventRepository, ObservableObject {

    // MARK: - Published

    /// 가장 최근 `events(in:)`로 받은 결과의 in-memory 캐시.
    /// View는 직접 `@ObservedObject`로 구독 가능 (optimistic UI 교체용).
    @Published public private(set) var events: [CalendarEvent] = []

    // MARK: - Config

    /// FakeEventRepository와 동일한 시그니처 — UI 배너 판정에 사용.
    public let isFakeRepo: Bool = false

    // MARK: - Dependencies

    private let client: GoogleCalendarClient
    public let calendarId: String

    // MARK: - Init

    public init(client: GoogleCalendarClient, calendarId: String = "primary") {
        self.client = client
        self.calendarId = calendarId
    }

    // MARK: - In-memory mutation (optimistic UI)
    //
    // FakeEventRepository가 제공하던 API와 동일 시그니처를 유지해,
    // View에서 GoogleCalendarRepository도 동일 방식으로 쓸 수 있다.

    public func replaceInMemory(_ event: CalendarEvent) {
        if let idx = events.firstIndex(where: {
            $0.id == event.id && $0.calendarId == event.calendarId
        }) {
            events[idx] = event
        }
    }

    public func removeInMemory(_ event: CalendarEvent) {
        events.removeAll {
            $0.id == event.id && $0.calendarId == event.calendarId
        }
    }

    public func insertInMemory(_ event: CalendarEvent) {
        guard !events.contains(where: {
            $0.id == event.id && $0.calendarId == event.calendarId
        }) else { return }
        events.append(event)
    }

    // MARK: - EventRepository

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        do {
            let fetched = try await client.listEvents(calendarId: calendarId, in: interval)
            // 캐시 업데이트: 현재 interval 범위의 이벤트만 교체하고 바깥은 유지.
            // 단순하게 이번 응답으로 events 전체를 덮지 않고 merge → 월 네비 시 인접 월 캐시 유지.
            mergeIntoCache(fetched, interval: interval)
            return fetched
        } catch {
            // 캐시 유지, 에러는 위로 전파 (호출자가 토스트 처리).
            throw error
        }
    }

    public func create(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
        let ev = try await client.insertEvent(calendarId: calendarId, draft: draft)
        insertInMemory(ev)
        return ev
    }

    public func update(_ event: CalendarEvent) async throws -> CalendarEvent {
        let ev = try await client.patchEvent(event)
        replaceInMemory(ev)
        return ev
    }

    public func delete(_ event: CalendarEvent) async throws {
        try await client.deleteEvent(event)
        removeInMemory(event)
    }

    // MARK: - Helpers

    /// 새로 fetch한 이벤트들을 cache로 병합.
    /// 같은 `(calendarId, id)` 매치는 덮어쓰기, 해당 interval 내 cache 잔류본은 제거.
    private func mergeIntoCache(_ fresh: [CalendarEvent], interval: DateInterval) {
        // 1. 이번 interval에 겹치는 기존 캐시 삭제.
        events.removeAll { ev in
            ev.endDate > interval.start && ev.startDate < interval.end
        }
        // 2. fresh 삽입.
        events.append(contentsOf: fresh)
    }
}
#endif
