#if os(iOS)
import Foundation
import Combine
import CalenShared

// MARK: - ReviewViewModel
//
// iOS 리뷰 탭 상태 허브 (v0.1.1 Review).
//
// 책임:
//   - 기간(`ReviewPeriod`) 변경 → EventRepository에서 해당 기간 이벤트 재조회
//   - 각 카드(CompletionRate, CategoryTime, HabitStreak, Grass, AISuggestion)에
//     필요한 순수 집계 값을 `CalenShared.ReviewAggregator`로 계산해 노출
//   - AI 요약 생성 — ClaudeAPIClient one-shot(streaming=false) 호출
//
// 비책임:
//   - SwiftUI 레이아웃 (각 카드 뷰가 담당)
//   - Google 로그인 상태 관리 (HomeViewModel 참고 — 여기선 authManager 구독만)
//
// 주의: FakeEventRepository / GoogleCalendarRepository 모두 `iOSEventRepository`를 구현한다.
// 다만 `iOSEventRepository`는 `associatedtype` 관련으로 존재 타입 바인딩이 어려워서
// 내부 저장은 `EventRepository` 프로토콜만 사용 + 로그인 상태는 `@Published` bool로 노출.

@MainActor
public final class ReviewViewModel: ObservableObject {

    // MARK: - Published

    /// 현재 선택된 기간 (일/주/월). 세그먼티드 피커 바인딩.
    @Published public var period: ReviewPeriod = .day {
        didSet {
            guard oldValue != period else { return }
            Task { await self.refresh() }
        }
    }

    /// 선택된 기간에 해당하는 이벤트(필터링 완료).
    @Published public private(set) var events: [CalendarEvent] = []

    /// 현재 period 기준 Interval (뷰에서 grass/카테고리 계산 시 공유).
    @Published public private(set) var currentInterval: DateInterval

    /// AI 요약(짧은 1~2문장). nil이면 아직 생성 전.
    @Published public var aiSummary: String? = nil

    /// AI 요약 로딩 중.
    @Published public var isLoadingSummary: Bool = false

    /// AI 요약 오류 메시지 (nil이면 오류 없음).
    @Published public var aiError: String? = nil

    /// 이벤트 조회 로딩 상태.
    @Published public private(set) var isLoading: Bool = false

    // MARK: - Dependencies

    private let repositoryProvider: () -> EventRepository
    private let clientFactory: () -> ClaudeAPIClient
    private let clock: () -> Date
    private let calendar: Calendar

    // MARK: - Init

    /// 기본 초기화 — 주 호출 (View에서 `@StateObject`로 사용).
    /// - Parameters:
    ///   - repositoryProvider: 매 호출 시 최신 EventRepository를 반환(로그인 스왑 대응).
    ///   - clientFactory: ClaudeAPIClient 생성 클로저(Keychain 키 로드 포함).
    public convenience init(
        repositoryProvider: @escaping () -> EventRepository = ReviewViewModel.defaultRepository,
        clientFactory: @escaping () -> ClaudeAPIClient = ReviewViewModel.defaultClient
    ) {
        self.init(
            repositoryProvider: repositoryProvider,
            clientFactory: clientFactory,
            clock: { Date() },
            calendar: .current
        )
    }

    /// 테스트 전용 — clock / calendar 고정 가능.
    public init(
        repositoryProvider: @escaping () -> EventRepository,
        clientFactory: @escaping () -> ClaudeAPIClient,
        clock: @escaping () -> Date,
        calendar: Calendar
    ) {
        self.repositoryProvider = repositoryProvider
        self.clientFactory = clientFactory
        self.clock = clock
        self.calendar = calendar
        self.currentInterval = ReviewPeriod.day.interval(containing: clock(), calendar: calendar)
    }

    // MARK: - Factories

    /// 기본 repo — FakeEventRepository 싱글턴. 로그인 스왑은 v0.1.2에서 HomeViewModel와 공유 예정.
    /// v0.1.1 Review에선 프리뷰/미로그인 fallback을 보장 — 로그인 케이스는 향후 RootView에서 주입.
    private static let _defaultRepo: FakeEventRepository = FakeEventRepository()

    /// 기본 초기화 경로에서 사용되는 repo 공급자. public이어야 `convenience init` 기본값에서 참조 가능.
    public static func defaultRepository() -> EventRepository { _defaultRepo }

    /// 기본 초기화 경로에서 사용되는 Claude 클라이언트. Keychain에서 API 키를 읽는다.
    public static func defaultClient() -> ClaudeAPIClient {
        let model = UserDefaults.standard.string(forKey: "calen-ios.claude.model")
            ?? ClaudeAPIClient.defaultModel
        return ClaudeAPIClient(
            apiKeyProvider: { ClaudeAPIKeychain.load() },
            model: model
        )
    }

    // MARK: - Public API

    /// 현재 기간으로 이벤트 재조회. period 변경 직후에도 호출됨.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let now = clock()
        let interval = period.interval(containing: now, calendar: calendar)
        currentInterval = interval

        let repo = repositoryProvider()
        do {
            let fetched = try await repo.events(in: interval)
            // repo가 필터링을 보장하지 않을 수 있으므로 한 번 더 클램핑.
            self.events = ReviewAggregator.eventsIn(interval: interval, from: fetched)
        } catch {
            self.events = []
        }
    }

    /// 기간 전환 — 세그먼티드 피커에서 호출(또는 `period` 직접 바인딩).
    public func select(_ newPeriod: ReviewPeriod) {
        self.period = newPeriod
    }

    /// AI 요약 재생성 — Claude one-shot(non-stream).
    /// 키 미설정 / 네트워크 오류 시 `aiError`에 메시지 세팅.
    public func regenerateAISummary() async {
        aiError = nil
        isLoadingSummary = true
        defer { isLoadingSummary = false }

        // 프롬프트 — 현재 period 이벤트 + 카테고리 누적 분.
        let prompt = buildSummaryPrompt()

        let client = clientFactory()
        let stream = await client.send(
            messages: [.user(prompt)],
            system: "당신은 Calen의 일정 리뷰 코치입니다. 반드시 2문장 이하의 간결한 한국어 조언을 제시합니다.",
            stream: false
        )

        var accumulated = ""
        do {
            for try await event in stream {
                switch event {
                case .messageStart:
                    break
                case let .contentBlockDelta(text):
                    accumulated += text
                case .messageStop:
                    break
                }
            }
            let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            aiSummary = trimmed.isEmpty ? nil : trimmed
            if trimmed.isEmpty {
                aiError = "요약이 비어 있습니다. 다시 시도해 주세요."
            }
        } catch let err as ClaudeAPIClient.ClaudeAPIError {
            aiError = err.userMessage
        } catch {
            aiError = "오류: \(error.localizedDescription)"
        }
    }

    // MARK: - Derived (카드에서 사용)

    /// 완료 비율 — (done, total, 0.0~1.0).
    public func completion(now: Date? = nil) -> (done: Int, total: Int, rate: Double) {
        ReviewAggregator.completionRate(events: events, now: now ?? clock())
    }

    /// 카테고리별 분 단위 누적 — 바 차트 입력.
    public func categoryMinutes() -> [ReviewCategory: Int] {
        ReviewAggregator.minutesByCategory(events: events, clampedTo: currentInterval)
    }

    /// 최근 7일 습관 dot — 일별 dominant 카테고리 + 이벤트 수.
    /// 주의: 현재 period에 상관없이 "최근 7일"을 본다 (macOS의 habit graph와 동일).
    public func recentHabitDays() async -> [DaySummary] {
        // 최근 7일 전체 범위의 이벤트를 repo에서 별도 조회.
        let now = clock()
        let cal = calendar
        let endDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let startDay = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
        let interval = DateInterval(start: startDay, end: endDay)
        let repo = repositoryProvider()
        let list = (try? await repo.events(in: interval)) ?? []
        return ReviewAggregator.recentDaysSummary(
            events: list,
            now: now,
            calendar: cal,
            dayCount: 7
        )
    }

    /// 30일 잔디맵 days — 현재 period와 무관하게 최근 30일 집계.
    public func grassDays(dayCount: Int = 30) async -> [GrassDay] {
        let now = clock()
        let cal = calendar
        let endDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let startDay = cal.date(byAdding: .day, value: -(dayCount - 1), to: cal.startOfDay(for: now)) ?? now
        let interval = DateInterval(start: startDay, end: endDay)
        let repo = repositoryProvider()
        let list = (try? await repo.events(in: interval)) ?? []
        return ReviewAggregator.grassDays(
            events: list,
            now: now,
            calendar: cal,
            dayCount: dayCount
        )
    }

    // MARK: - Prompt

    private func buildSummaryPrompt() -> String {
        let (done, total, rate) = completion()
        let catMin = categoryMinutes()
        let totalMin = catMin.values.reduce(0, +)

        var breakdown: [String] = []
        for cat in ReviewCategory.allCases {
            let m = catMin[cat] ?? 0
            guard m > 0 else { continue }
            let hours = Double(m) / 60.0
            let pct = totalMin > 0 ? (Double(m) / Double(totalMin)) * 100.0 : 0
            breakdown.append("\(cat.label) \(String(format: "%.1f", hours))h (\(Int(pct))%)")
        }
        let breakdownLine = breakdown.isEmpty ? "데이터 없음" : breakdown.joined(separator: ", ")

        let periodLabel = period.label
        return """
        Calen 사용자의 \(periodLabel) 일정 요약:
        - 전체 \(total)개 중 \(done)개 완료 (\(Int(rate * 100))%)
        - 카테고리 시간: \(breakdownLine)

        위 데이터를 바탕으로, 사용자에게 2문장 이하의 짧고 구체적인 조언을 한국어로 제시해 주세요.
        첫 문장은 관찰(예: "이번 주는 회의가 많았습니다"), 두 번째 문장은 개선 제안(예: "개인 시간 10% 확보 추천").
        """
    }
}
#endif
