#if os(iOS)
import Foundation
import SwiftData
import Combine
import CalenShared

// MARK: - HomeViewModel (v4)
//
// TimeBlocks 스타일 월간 달력 + 주 확장 화면 상태 허브.
// v3의 주(週) 스트립 + 타임라인 구조를 폐기하고, 월 단위 탐색/선택 주 확장 모델로 교체.
//
// 상태 모델:
//  - `currentMonth`  : 현재 보고 있는 월(해당 월 1일 기준 Date)
//  - `selectedDate`  : 사용자가 탭한 날짜 (주 확장 영역 기준 앵커)
//  - `expandedWeekStart` : 주 확장이 펼쳐진 주의 월요일 (nil이면 닫힘)
//  - `schedulesInMonth` : 현재 월 그리드에 표시할 Schedule (SwiftData 페치 결과)
//
// 뷰와의 계약: View는 `tapDate(_:)`, `goToPreviousMonth()`, `goToNextMonth()`,
// `schedules(for:)`, `schedulesInWeek(starting:)` 만 호출한다.

// MARK: - ScheduleDisplayItem (v3 호환 유지 — EventDetailSheet/ScheduleCard에서 재사용)

struct ScheduleDisplayItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let category: ScheduleCategory
    let startTime: Date
    let endTime: Date?
    let location: String?
    let summary: String?
    let travelTimeMinutes: Int?
    let bulletPoints: [String]

    init(from schedule: Schedule) {
        self.id = schedule.id
        self.title = schedule.title
        self.category = schedule.category
        self.startTime = schedule.startTime
        self.endTime = schedule.endTime
        self.location = schedule.location
        self.summary = schedule.summary
        self.travelTimeMinutes = schedule.travelTimeMinutes

        if let notes = schedule.notes, !notes.isEmpty {
            self.bulletPoints = notes
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            self.bulletPoints = []
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: ScheduleCategory,
        startTime: Date,
        endTime: Date? = nil,
        location: String? = nil,
        summary: String? = nil,
        travelTimeMinutes: Int? = nil,
        bulletPoints: [String] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.summary = summary
        self.travelTimeMinutes = travelTimeMinutes
        self.bulletPoints = bulletPoints
    }

    static func == (lhs: ScheduleDisplayItem, rhs: ScheduleDisplayItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - HomeViewModel

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: Published state

    /// 현재 보고 있는 월(해당 월 1일 기준 Date)
    @Published var currentMonth: Date

    /// 사용자가 탭한 날짜 (초기값: 오늘)
    @Published var selectedDate: Date

    /// 주 확장 영역이 펼쳐진 주의 월요일. nil이면 접힘.
    @Published var expandedWeekStart: Date?

    /// 현재 월 그리드에 들어갈 모든 일정(display item).
    /// 전 달/다음 달 셀(스필오버)에 걸친 이벤트도 포함한다.
    @Published private(set) var schedulesInMonth: [ScheduleDisplayItem] = []

    /// v5 Phase A: 주 시트용 fake 이벤트 리포지토리.
    /// Phase B에서 Google Calendar 기반 구현체로 교체 예정.
    let eventRepository: FakeEventRepository

    /// 주 시트 표시 여부 (날짜 탭 시 true).
    @Published var showWeekSheet: Bool = false

    /// 주 시트가 보여줄 앵커 날짜.
    @Published var sheetAnchorDate: Date = Date()

    // MARK: Internal

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1 // 일요일 시작 (헤더와 일치)
        return c
    }()

    var modelContext: ModelContext? {
        didSet { seedIfNeededAndFetch() }
    }

    private var hasSeeded = false

    // MARK: - Init

    init(modelContext: ModelContext? = nil, eventRepository: FakeEventRepository? = nil) {
        let now = Date()
        var comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        comps.day = 1
        self.currentMonth = Calendar(identifier: .gregorian).date(from: comps) ?? now
        self.selectedDate = Calendar(identifier: .gregorian).startOfDay(for: now)
        self.expandedWeekStart = nil
        self.modelContext = modelContext
        self.eventRepository = eventRepository ?? FakeEventRepository()

        // 오늘이 속한 주를 기본 확장
        self.expandedWeekStart = weekStart(for: selectedDate)

        if modelContext != nil {
            seedIfNeededAndFetch()
        } else {
            // 프리뷰 / 컨텍스트 없을 때는 mock 주입
            schedulesInMonth = Self.mockMonthSchedules(around: currentMonth)
        }
    }

    // MARK: - Public API

    /// 월 그리드 날짜 탭 시 호출. 같은 주면 선택만 변경, 다른 주면 해당 주로 확장 이동.
    /// v5 Phase A: 탭 시 풀스크린 주 시트도 함께 띄움.
    func tapDate(_ date: Date) {
        let day = cal.startOfDay(for: date)
        selectedDate = day
        expandedWeekStart = weekStart(for: day)
        sheetAnchorDate = day
        showWeekSheet = true
    }

    /// 가로 스와이프로 이전 달로 이동.
    func goToPreviousMonth() {
        guard let prev = cal.date(byAdding: .month, value: -1, to: currentMonth) else { return }
        currentMonth = prev
        fetchSchedulesInMonth()
    }

    /// 가로 스와이프로 다음 달로 이동.
    func goToNextMonth() {
        guard let next = cal.date(byAdding: .month, value: 1, to: currentMonth) else { return }
        currentMonth = next
        fetchSchedulesInMonth()
    }

    /// 특정 날짜의 일정(시작시간 오름차순).
    func schedules(for date: Date) -> [ScheduleDisplayItem] {
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return schedulesInMonth
            .filter { $0.startTime >= start && $0.startTime < end }
            .sorted { $0.startTime < $1.startTime }
    }

    /// 한 주(월요일 기준)에 속한 요일별 그룹. 확장 영역용.
    /// 반환: 7개 요소, 각 (Date, [ScheduleDisplayItem]) — 월요일부터 일요일까지.
    func weekGroups(starting monday: Date) -> [(day: Date, items: [ScheduleDisplayItem])] {
        (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: monday) else { return nil }
            return (day: day, items: schedules(for: day))
        }
    }

    // MARK: - Month Grid Building (View에서 호출)

    /// 42-slot(6주 × 7일) 월 그리드. nil = 인접 달 패딩이 아닌 실제 인접 달 날짜로 채워 시각적 연속성 유지.
    func datesInMonthGrid(for monthAnchor: Date) -> [Date] {
        var comps = cal.dateComponents([.year, .month], from: monthAnchor)
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps) else { return [] }

        // 일요일 시작 헤더와 맞추기 위해, 1일이 속한 주의 일요일부터 42일 전개.
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) - 1 // Sunday = 0
        guard let gridStart = cal.date(byAdding: .day, value: -weekdayOfFirst, to: firstOfMonth) else {
            return []
        }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// 해당 날짜가 `currentMonth`와 같은 달에 속하는지.
    func isInCurrentMonth(_ date: Date) -> Bool {
        cal.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    /// date가 속한 주의 월요일을 반환.
    func weekStart(for date: Date) -> Date {
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    // MARK: - Data Fetching

    private func seedIfNeededAndFetch() {
        guard let context = modelContext else { return }

        if !hasSeeded {
            let descriptor = FetchDescriptor<Schedule>()
            let existing = (try? context.fetch(descriptor)) ?? []
            if existing.isEmpty {
                Self.seedSamples(into: context)
            }
            hasSeeded = true
        }
        fetchSchedulesInMonth()
    }

    /// 월 그리드 범위를 재페치. 일정 추가/삭제 등 외부 변경 후 호출.
    func reloadSchedules() {
        fetchSchedulesInMonth()
    }

    private func fetchSchedulesInMonth() {
        guard let context = modelContext else {
            schedulesInMonth = Self.mockMonthSchedules(around: currentMonth)
            return
        }

        // 월 그리드 전체 범위(42일) = currentMonth 1일 속한 주의 일요일 ~ 그 + 42일
        let gridStart = cal.startOfDay(for: datesInMonthGrid(for: currentMonth).first ?? currentMonth)
        guard let gridEnd = cal.date(byAdding: .day, value: 42, to: gridStart) else { return }

        let predicate = #Predicate<Schedule> {
            $0.date >= gridStart && $0.date < gridEnd
        }
        let descriptor = FetchDescriptor<Schedule>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            let results = try context.fetch(descriptor)
            schedulesInMonth = results.map { ScheduleDisplayItem(from: $0) }
        } catch {
            print("[HomeViewModel] fetch error: \(error)")
            schedulesInMonth = []
        }
    }

    // MARK: - Sample Seeding (SwiftData 컨테이너가 비어있을 때만)

    /// 오늘 기준 ±7일 범위로 5개 샘플 주입.
    private static func seedSamples(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        struct Sample {
            let offset: Int
            let hour: Int
            let minute: Int
            let durationMinutes: Int
            let title: String
            let category: ScheduleCategory
            let location: String?
            let notes: String?
        }

        let samples: [Sample] = [
            .init(offset:  0, hour:  9, minute:  0, durationMinutes: 60,
                  title: "팀 스탠드업", category: .meeting,
                  location: "본사 3층 회의실", notes: "OKR 진행 공유"),
            .init(offset:  0, hour: 12, minute: 30, durationMinutes: 60,
                  title: "점심 식사", category: .meal,
                  location: "강남 맛집", notes: nil),
            .init(offset:  2, hour: 10, minute:  0, durationMinutes: 90,
                  title: "기획 리뷰", category: .work,
                  location: "원격(Zoom)", notes: "Q2 로드맵 검토"),
            .init(offset:  4, hour: 19, minute:  0, durationMinutes: 60,
                  title: "헬스장", category: .exercise,
                  location: "피트니스 센터", notes: nil),
            .init(offset: -2, hour: 15, minute:  0, durationMinutes: 60,
                  title: "개인 독서", category: .personal,
                  location: nil, notes: "아틀라스 오브 더 하트"),
        ]

        for s in samples {
            let day = cal.date(byAdding: .day, value: s.offset, to: today) ?? today
            let start = cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: day) ?? day
            let end = cal.date(byAdding: .minute, value: s.durationMinutes, to: start)
            let schedule = Schedule(
                title: s.title,
                date: day,
                startTime: start,
                endTime: end,
                location: s.location,
                notes: s.notes,
                category: s.category
            )
            context.insert(schedule)
        }

        do {
            try context.save()
        } catch {
            print("[HomeViewModel] seed save error: \(error)")
        }
    }

    // MARK: - Mock (프리뷰 / 컨텍스트 없을 때)

    static func mockMonthSchedules(around anchor: Date) -> [ScheduleDisplayItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: anchor)

        func make(_ offset: Int, _ hour: Int, _ minute: Int, _ dur: Int,
                  _ title: String, _ cat: ScheduleCategory) -> ScheduleDisplayItem {
            let day = cal.date(byAdding: .day, value: offset, to: today) ?? today
            let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            let end = cal.date(byAdding: .minute, value: dur, to: start)
            return ScheduleDisplayItem(
                title: title, category: cat, startTime: start, endTime: end
            )
        }

        return [
            make(0,  9,  0, 60, "팀 스탠드업", .meeting),
            make(0, 12, 30, 60, "점심 식사", .meal),
            make(2, 10,  0, 90, "기획 리뷰", .work),
            make(4, 19,  0, 60, "헬스장", .exercise),
            make(-2, 15, 0, 60, "개인 독서", .personal),
        ]
    }

    /// (v3 호환) 외부에서 mock 요청 시 사용. CalendarAddView 프리뷰 등에서 참조 가능.
    static func mockSchedules(for date: Date) -> [ScheduleDisplayItem] {
        mockMonthSchedules(around: date)
    }
}
#endif
