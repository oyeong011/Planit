#if os(iOS)
import Foundation
import Combine
import CalenShared

// MARK: - FakeEventRepository
//
// M1/M2 단계에서 사용하는 in-memory stub `EventRepository`.
// Google Calendar 실연동(Phase B)까지 시간 그리드/드래그/리사이즈 UX를
// 독립적으로 개발·테스트하기 위한 구현체.
//
// 특성:
//  - `@MainActor final class` + `ObservableObject`로 View가 직접 `@ObservedObject`로
//    바인딩해 rollback 애니메이션을 즉시 볼 수 있게 함.
//  - `events`는 in-memory 배열. create/update/delete 시 300ms delay로 네트워크 시뮬.
//  - `failureRate`(0.0~1.0)로 랜덤 throw를 제어. 기본 0.0 (최종 커밋 전 안정화).
//    QA/데모에서 rollback UX 확인 시 `0.1~0.3`로 끌어올려 테스트.
//  - 초기화 시 오늘 기준 ±7일 샘플 이벤트 16개 생성
//    (카테고리 다양, 종일 2개, 겹치는 쌍 2개, read-only 1개 포함).

@MainActor
public final class FakeEventRepository: EventRepository, ObservableObject {

    // MARK: - Published state

    @Published public private(set) var events: [CalendarEvent] = []

    // MARK: - Config

    /// 시뮬레이션된 네트워크 지연(초). UI hot-reload 피드백용.
    public var networkDelay: Duration = .milliseconds(300)

    /// 랜덤 실패 확률 (0.0 = never, 1.0 = always).
    /// rollback UX 시연용. 최종 커밋에선 0.0으로 두고, QA 시 `repo.failureRate = 0.2` 등으로 상향.
    public var failureRate: Double = 0.0

    /// 업데이트·생성 시 반환할 새 etag / updated 타임스탬프 생성.
    private var etagCounter: Int = 0

    // MARK: - Init

    public init(seed: Bool = true) {
        if seed {
            self.events = Self.makeSeedEvents()
        }
    }

    // MARK: - Optimistic in-memory mutation
    //
    // View가 드래그/리사이즈 시 네트워크 호출 이전에 즉시 렌더를 반영하기 위한 helper.
    // 실제 저장은 `update(_:)` async 경로에서 일어난다 — 실패 시 view는 `replaceInMemory`로 원상복구.

    /// 해당 calendarId + id 매치되는 이벤트를 in-memory에서 즉시 교체.
    public func replaceInMemory(_ event: CalendarEvent) {
        if let idx = events.firstIndex(where: {
            $0.id == event.id && $0.calendarId == event.calendarId
        }) {
            events[idx] = event
        }
    }

    // MARK: - EventRepository

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        // 읽기는 지연/실패 없음(월 단위 반복 조회를 불안정하게 만들지 않음).
        return events.filter { event in
            event.endDate > interval.start && event.startDate < interval.end
        }
    }

    public func create(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
        try await simulateLatency()
        try maybeFail(operation: "create")

        etagCounter += 1
        let event = CalendarEvent(
            id: UUID().uuidString,
            calendarId: draft.calendarId,
            title: draft.title,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            description: draft.description,
            location: draft.location,
            colorHex: draft.colorHex ?? "#3366CC",
            source: .local,
            etag: "etag-\(etagCounter)",
            updated: Date(),
            isReadOnly: false
        )
        events.append(event)
        return event
    }

    public func update(_ event: CalendarEvent) async throws -> CalendarEvent {
        try await simulateLatency()
        try maybeFail(operation: "update")

        guard let idx = events.firstIndex(where: {
            $0.id == event.id && $0.calendarId == event.calendarId
        }) else {
            throw FakeRepoError.notFound(id: event.id)
        }

        etagCounter += 1
        var updated = event
        updated.etag = "etag-\(etagCounter)"
        updated.updated = Date()
        events[idx] = updated
        return updated
    }

    public func delete(_ event: CalendarEvent) async throws {
        try await simulateLatency()
        try maybeFail(operation: "delete")

        events.removeAll {
            $0.id == event.id && $0.calendarId == event.calendarId
        }
    }

    // MARK: - Helpers

    private func simulateLatency() async throws {
        try await Task.sleep(for: networkDelay)
    }

    private func maybeFail(operation: String) throws {
        guard failureRate > 0 else { return }
        if Double.random(in: 0...1) < failureRate {
            throw FakeRepoError.simulatedFailure(operation: operation)
        }
    }

    // MARK: - Seed data

    private static func makeSeedEvents() -> [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let calendarId = "fake:primary"

        func at(_ offset: Int, _ h: Int, _ m: Int) -> Date {
            let day = cal.date(byAdding: .day, value: offset, to: today) ?? today
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
        }
        func plus(_ start: Date, minutes: Int) -> Date {
            cal.date(byAdding: .minute, value: minutes, to: start) ?? start
        }

        // 카테고리별 hex 팔레트 (Schedule.ScheduleCategory와 시각적으로 정렬).
        let workPink      = "#F56691"
        let meetingBlue   = "#3B82F6"
        let mealYellow    = "#FAC430"
        let exerciseGreen = "#40C786"
        let personalViolet = "#9A5CE8"
        let generalGray   = "#909094"

        var list: [CalendarEvent] = []

        // 오늘 — 팀 스탠드업 + 오버랩(제품 동기화)
        list.append(CalendarEvent(
            id: "seed-today-standup",
            calendarId: calendarId,
            title: "팀 스탠드업",
            startDate: at(0, 9, 0),
            endDate: at(0, 9, 30),
            colorHex: meetingBlue,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-today-product-sync",
            calendarId: calendarId,
            title: "제품 동기화",
            startDate: at(0, 9, 15),       // 스탠드업과 15분 겹침
            endDate: at(0, 10, 0),
            location: "Zoom",
            colorHex: meetingBlue,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-today-lunch",
            calendarId: calendarId,
            title: "점심 식사",
            startDate: at(0, 12, 30),
            endDate: at(0, 13, 30),
            location: "강남 샐러드",
            colorHex: mealYellow,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-today-deep-work",
            calendarId: calendarId,
            title: "딥 워크 블록",
            startDate: at(0, 14, 0),
            endDate: at(0, 16, 0),
            description: "OKR 초안 작성",
            colorHex: workPink,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-today-gym",
            calendarId: calendarId,
            title: "헬스",
            startDate: at(0, 19, 0),
            endDate: at(0, 20, 0),
            location: "피트니스 센터",
            colorHex: exerciseGreen,
            source: .local
        ))

        // 내일 — 종일 이벤트 + 일반 업무
        list.append(CalendarEvent(
            id: "seed-tmr-allday-offsite",
            calendarId: calendarId,
            title: "오프사이트 워크숍",
            startDate: cal.date(byAdding: .day, value: 1, to: today) ?? today,
            endDate: cal.date(byAdding: .day, value: 2, to: today) ?? today,
            isAllDay: true,
            colorHex: personalViolet,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-tmr-1on1",
            calendarId: calendarId,
            title: "1:1 세션",
            startDate: at(1, 11, 0),
            endDate: at(1, 12, 0),
            colorHex: meetingBlue,
            source: .local
        ))

        // +2일 — 기획 리뷰 + 오버랩(디자인 리뷰) + 읽기 전용
        list.append(CalendarEvent(
            id: "seed-d2-planning",
            calendarId: calendarId,
            title: "기획 리뷰",
            startDate: at(2, 10, 0),
            endDate: at(2, 11, 30),
            colorHex: workPink,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-d2-design",
            calendarId: calendarId,
            title: "디자인 리뷰",
            startDate: at(2, 10, 30),      // 30분 겹침
            endDate: at(2, 12, 0),
            colorHex: meetingBlue,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-d2-readonly",
            calendarId: calendarId,
            title: "전사 All-Hands (읽기 전용)",
            startDate: at(2, 15, 0),
            endDate: at(2, 16, 0),
            colorHex: generalGray,
            source: .local,
            isReadOnly: true
        ))

        // +3일 — 운동 + 개인 독서
        list.append(CalendarEvent(
            id: "seed-d3-run",
            calendarId: calendarId,
            title: "한강 러닝",
            startDate: at(3, 7, 0),
            endDate: at(3, 8, 0),
            colorHex: exerciseGreen,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-d3-reading",
            calendarId: calendarId,
            title: "독서 - 아틀라스 오브 더 하트",
            startDate: at(3, 21, 0),
            endDate: at(3, 22, 0),
            colorHex: personalViolet,
            source: .local
        ))

        // +5일 — 종일(생일) + 브런치
        list.append(CalendarEvent(
            id: "seed-d5-allday-bday",
            calendarId: calendarId,
            title: "가족 생일",
            startDate: cal.date(byAdding: .day, value: 5, to: today) ?? today,
            endDate: cal.date(byAdding: .day, value: 6, to: today) ?? today,
            isAllDay: true,
            colorHex: workPink,
            source: .local
        ))
        list.append(CalendarEvent(
            id: "seed-d5-brunch",
            calendarId: calendarId,
            title: "브런치",
            startDate: at(5, 11, 0),
            endDate: at(5, 12, 30),
            location: "연남동",
            colorHex: mealYellow,
            source: .local
        ))

        // -2일 — 과거 이벤트 (주 네비게이션 테스트용)
        list.append(CalendarEvent(
            id: "seed-dm2-review",
            calendarId: calendarId,
            title: "주간 회고",
            startDate: at(-2, 17, 0),
            endDate: at(-2, 18, 0),
            colorHex: generalGray,
            source: .local
        ))

        // -4일 — 저녁 약속
        list.append(CalendarEvent(
            id: "seed-dm4-dinner",
            calendarId: calendarId,
            title: "친구와 저녁",
            startDate: at(-4, 19, 30),
            endDate: at(-4, 21, 0),
            colorHex: mealYellow,
            source: .local
        ))

        return list
    }
}

// MARK: - Errors

public enum FakeRepoError: LocalizedError {
    case notFound(id: String)
    case simulatedFailure(operation: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "이벤트를 찾을 수 없습니다: \(id)"
        case .simulatedFailure(let op):
            return "시뮬레이션된 네트워크 실패(\(op))"
        }
    }
}
#endif
