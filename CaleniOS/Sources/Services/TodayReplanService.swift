#if os(iOS)
import Foundation
import SwiftUI
import CalenShared

// MARK: - TodayReplanService
//
// v0.1.1 AI-2 — iOS "오늘 다시 짜기" 오케스트레이션 서비스.
//
// 역할:
//   1. HomeView의 "오늘 다시 짜기" 버튼 → `generatePlan(for:)` 호출
//   2. `PlanningOrchestrator` + `ClaudePlanningAIProvider`로 AI 제안 수집
//   3. 제안(`PlanningAction`)을 `@Published suggestions`로 노출
//   4. 사용자가 수락한 action을 `GoogleCalendarRepository`(또는 fake)로 CRUD 적용
//
// 비책임:
//   - 캘린더 월 그리드 리프레시 (HomeView/HomeViewModel이 반영)
//   - AI 호출 재시도 (현재는 1회 호출)
//
// 스레드:
//   - @MainActor — @Published 직접 mutate.
//   - AI 호출은 `await`로 별 스레드에서 진행되지만 self는 main-actor에 고정.

@MainActor
public final class TodayReplanService: ObservableObject {

    // MARK: - Published

    /// 마지막으로 받은 제안(오늘 재계획 1회 결과). 새 호출 시 덮어쓰기.
    @Published public private(set) var suggestion: PlanningSuggestion?

    /// UI 편의용: 제안 리스트만 직접 접근.
    @Published public private(set) var suggestions: [PlanningAction] = []

    /// 현재 plan 생성 중인지.
    @Published public private(set) var isPlanning: Bool = false

    /// 사용자에게 표시할 에러 메시지. nil이면 정상.
    @Published public var error: String?

    /// apply 진행 중 여부 — CTA 버튼 disable 용.
    @Published public private(set) var isApplying: Bool = false

    // MARK: - Dependencies

    private let repository: EventRepository
    private let orchestratorFactory: () -> PlanningOrchestrator
    private let memoryFetcher: (any MemoryFetching)?
    private let calendar: Calendar

    // MARK: - Init

    /// 기본 초기화 — `ClaudeAPIKeychain` + `ClaudeAPIClient`로 오케스트레이터 구성.
    ///
    /// - Parameters:
    ///   - repository: 이벤트 CRUD (iOS: `GoogleCalendarRepository` 또는 `FakeEventRepository`)
    ///   - memoryFetcher: Hermes 기억 조회. nil이면 빈 리스트로 동작.
    public convenience init(
        repository: EventRepository,
        memoryFetcher: (any MemoryFetching)? = nil
    ) {
        self.init(
            repository: repository,
            memoryFetcher: memoryFetcher,
            orchestratorFactory: {
                let model = UserDefaults.standard.string(forKey: "calen-ios.claude.model")
                    ?? ClaudeAPIClient.defaultModel
                let client = ClaudeAPIClient(
                    apiKeyProvider: { ClaudeAPIKeychain.load() },
                    model: model
                )
                let provider = ClaudePlanningAIProvider(client: client)
                return PlanningOrchestrator(ai: provider)
            }
        )
    }

    /// 테스트/커스텀 주입 init.
    public init(
        repository: EventRepository,
        memoryFetcher: (any MemoryFetching)? = nil,
        orchestratorFactory: @escaping () -> PlanningOrchestrator,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.repository = repository
        self.memoryFetcher = memoryFetcher
        self.orchestratorFactory = orchestratorFactory
        self.calendar = calendar
    }

    // MARK: - Public API

    /// API 키가 설정돼 있는지. UI에서 키 없으면 일찍 배너 띄우기 위해 노출.
    public var hasAPIKey: Bool {
        guard let key = ClaudeAPIKeychain.load() else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 지정 날짜에 대해 AI 재계획 제안 생성. 완료 시 `suggestion` / `suggestions` 갱신.
    public func generatePlan(for day: Date) async {
        guard !isPlanning else { return }
        error = nil
        isPlanning = true
        defer { isPlanning = false }

        if !hasAPIKey {
            error = "Claude API 키가 설정되지 않았습니다. 설정 탭에서 입력해 주세요."
            suggestion = nil
            suggestions = []
            return
        }

        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            error = "날짜 계산 실패"
            return
        }
        let interval = DateInterval(start: dayStart, end: dayEnd)

        do {
            // 1) 오늘 이벤트 조회
            let todayEvents = (try? await repository.events(in: interval)) ?? []

            // 2) 빈 슬롯 계산 (all-day 제외, 30분 이하는 필터)
            let freeSlots = Self.computeFreeSlots(
                for: dayStart,
                dayEnd: dayEnd,
                events: todayEvents,
                minimumMinutes: 30
            )

            // 3) Hermes 기억 조회 (실패해도 치명적 X)
            let memories: [MemoryFact]
            if let fetcher = memoryFetcher {
                memories = (try? await fetcher.fetchRecentMemories(limit: 10)) ?? []
            } else {
                memories = []
            }

            let context = PlanningContext(
                currentDate: Date(),
                targetDay: dayStart,
                todayEvents: todayEvents,
                freeSlots: freeSlots,
                memories: memories
            )

            let orchestrator = orchestratorFactory()
            let result = try await orchestrator.generatePlan(context: context)
            self.suggestion = result
            self.suggestions = result.actions

            if result.actions.isEmpty {
                // 제안 0개는 에러가 아님 — 배너에 warnings 요약만.
                if let first = result.warnings.first {
                    self.error = "제안이 없습니다. \(first)"
                }
            }
        } catch let err as ClaudeAPIClient.ClaudeAPIError {
            self.error = err.userMessage
        } catch {
            self.error = "재계획 생성 실패: \(error.localizedDescription)"
        }
    }

    /// 사용자가 수락한 action 들을 각각 EventRepository로 적용.
    /// 하나라도 실패해도 나머지는 계속 시도하고, 실패 개수만큼 warning을 쌓아 throw 하지 않는다.
    ///
    /// - Returns: (성공 개수, 실패 개수)
    @discardableResult
    public func applyAccepted(_ actions: [PlanningAction]) async -> (succeeded: Int, failed: Int) {
        guard !isApplying else { return (0, 0) }
        isApplying = true
        defer { isApplying = false }

        var succeeded = 0
        var failed = 0
        var failureMessages: [String] = []

        for action in actions {
            do {
                switch action {
                case let .createEvent(_, draft, _):
                    _ = try await repository.create(draft)
                    succeeded += 1

                case let .moveEvent(_, eventId, calendarId, newStart, newEnd, _, _, _):
                    // 현재 repo에서 이벤트 위치를 찾아 patch. 찾지 못하면 실패.
                    let existing = try await repository.events(in: DateInterval(
                        start: Calendar.current.startOfDay(for: newStart).addingTimeInterval(-86400),
                        end: Calendar.current.startOfDay(for: newStart).addingTimeInterval(86400 * 2)
                    ))
                    guard let target = existing.first(where: { $0.id == eventId && $0.calendarId == calendarId }) else {
                        failed += 1
                        failureMessages.append("이동할 이벤트를 찾지 못했습니다.")
                        continue
                    }
                    var updated = target
                    updated.startDate = newStart
                    updated.endDate = newEnd
                    _ = try await repository.update(updated)
                    succeeded += 1

                case let .cancelEvent(_, eventId, calendarId, _, originalStart, _):
                    let existing = try await repository.events(in: DateInterval(
                        start: Calendar.current.startOfDay(for: originalStart).addingTimeInterval(-86400),
                        end: Calendar.current.startOfDay(for: originalStart).addingTimeInterval(86400 * 2)
                    ))
                    guard let target = existing.first(where: { $0.id == eventId && $0.calendarId == calendarId }) else {
                        failed += 1
                        failureMessages.append("취소할 이벤트를 찾지 못했습니다.")
                        continue
                    }
                    try await repository.delete(target)
                    succeeded += 1
                }
            } catch {
                failed += 1
                failureMessages.append(error.localizedDescription)
            }
        }

        if failed > 0 {
            let firstTwo = failureMessages.prefix(2).joined(separator: " / ")
            self.error = "\(succeeded)개 적용 / \(failed)개 실패: \(firstTwo)"
        }

        return (succeeded, failed)
    }

    /// 제안/에러 상태 초기화 — 시트 닫을 때 호출.
    public func reset() {
        suggestion = nil
        suggestions = []
        error = nil
    }

    // MARK: - Helpers

    /// 하루 범위에서 이벤트 사이의 빈 시간대 계산. all-day 이벤트는 제외.
    /// minimumMinutes 이하 슬롯은 drop.
    static func computeFreeSlots(
        for dayStart: Date,
        dayEnd: Date,
        events: [CalendarEvent],
        minimumMinutes: Int
    ) -> [PlanningContext.FreeSlot] {
        // all-day 이벤트는 슬롯 계산에서 제외 (하루 전체를 먹는 것으로 처리하지 않음 — 유연성 유지).
        let timed = events
            .filter { !$0.isAllDay && $0.endDate > dayStart && $0.startDate < dayEnd }
            .map { ev -> (start: Date, end: Date) in
                let s = max(ev.startDate, dayStart)
                let e = min(ev.endDate, dayEnd)
                return (s, e)
            }
            .sorted { $0.start < $1.start }

        // 겹치는 이벤트 병합
        var merged: [(Date, Date)] = []
        for (s, e) in timed {
            if var last = merged.last, s <= last.1 {
                last.1 = max(last.1, e)
                merged[merged.count - 1] = last
            } else {
                merged.append((s, e))
            }
        }

        var gaps: [PlanningContext.FreeSlot] = []
        var cursor = dayStart
        for (s, e) in merged {
            if s > cursor {
                gaps.append(.init(start: cursor, end: s))
            }
            cursor = max(cursor, e)
        }
        if cursor < dayEnd {
            gaps.append(.init(start: cursor, end: dayEnd))
        }

        return gaps.filter { $0.durationMinutes >= minimumMinutes }
    }
}
#endif
