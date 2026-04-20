#if os(iOS)
import Foundation
import Combine
import CalenShared

// MARK: - iOSEventRepository
//
// Phase B M4: 뷰 계층에서 FakeEventRepository / GoogleCalendarRepository를
// 동일 인터페이스로 소비하기 위한 iOS 전용 슈퍼-프로토콜.
//
// 이유:
//   - `EventRepository`(Shared)는 Sendable actor/MainActor 지원용 순수 프로토콜.
//   - 그러나 SwiftUI View는 `@ObservedObject`로 `ObservableObject & EventRepository`가
//     동시에 필요.
//   - 그리고 `WeekTimeGridSheet`는 optimistic UI를 위해 `replaceInMemory/removeInMemory/
//     insertInMemory` helper를 호출한다 — 두 repo 구현이 동일 시그니처를 공유.
//
// 이 프로토콜은 두 구현체의 공통 외형을 뷰에 노출하기 위한 얇은 marker 역할.
@MainActor
public protocol iOSEventRepository: EventRepository, ObservableObject {
    var events: [CalendarEvent] { get }

    /// UI 배너 표시 조건. Fake만 true.
    var isFakeRepo: Bool { get }

    /// 낙관적 UI 교체 — 메모리의 같은 id 이벤트를 교체.
    func replaceInMemory(_ event: CalendarEvent)
    /// 낙관적 제거.
    func removeInMemory(_ event: CalendarEvent)
    /// 낙관적 제거 롤백.
    func insertInMemory(_ event: CalendarEvent)
}

extension FakeEventRepository: iOSEventRepository {}
extension GoogleCalendarRepository: iOSEventRepository {}
#endif
