#if os(iOS)
import Foundation
import SwiftData
import Combine
import CryptoKit
import SwiftUI
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

    /// v5 Phase A: 주 시트용 fake 이벤트 리포지토리. 미로그인/프리뷰에서 사용.
    /// Phase B: 로그인 상태에선 `googleRepository`가 대신 source of truth.
    let eventRepository: FakeEventRepository

    /// v0.1.1 Phase B M4: 로그인 시 활성화되는 실제 Google Calendar 리포지토리.
    /// nil이면 fake fallback(미로그인 데모).
    @Published private(set) var googleRepository: GoogleCalendarRepository?

    /// Auth 관리자 — 로그인 상태 변화 구독.
    private let authManager: iOSGoogleAuthManager
    private var authCancellable: AnyCancellable?

    /// 현재 repo가 Google 기반인지 (= 로그인됨).
    var usingGoogleRepo: Bool { googleRepository != nil }

    /// Day 상세 시트 표시 여부 (날짜 탭 시 true).
    /// 변수명은 호환 유지 (v0.1에서 WeekTimeGridSheet → DayDetailSheet 교체).
    @Published var showWeekSheet: Bool = false

    /// 시트가 보여줄 앵커 날짜.
    @Published var sheetAnchorDate: Date = Date()

    /// PRD v0.1: 이벤트 탭 → 편집 시트 직행. DayDetailSheet가 dismiss 후 이 값을 set하면
    /// HomeView가 EventEditSheet를 이어 띄운다.
    @Published var selectedEventForEdit: CalendarEvent?

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

    init(
        modelContext: ModelContext? = nil,
        eventRepository: FakeEventRepository? = nil,
        authManager: iOSGoogleAuthManager = .shared,
        useFakeForPreview: Bool = false
    ) {
        let now = Date()
        var comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        comps.day = 1
        self.currentMonth = Calendar(identifier: .gregorian).date(from: comps) ?? now
        self.selectedDate = Calendar(identifier: .gregorian).startOfDay(for: now)
        self.expandedWeekStart = nil
        self.modelContext = modelContext
        self.eventRepository = eventRepository ?? FakeEventRepository()
        self.authManager = authManager

        // 오늘이 속한 주를 기본 확장
        self.expandedWeekStart = weekStart(for: selectedDate)

        // Phase B M4: 로그인 상태에 따라 Google repository 활성화.
        if !useFakeForPreview && authManager.isAuthenticated {
            activateGoogleRepo()
        }

        // Phase B M4-2: 로그인 상태 변화 감지 → repo swap.
        self.authCancellable = authManager.$isAuthenticated
            .removeDuplicates()
            .sink { [weak self] isAuthed in
                guard let self else { return }
                if isAuthed && self.googleRepository == nil {
                    self.activateGoogleRepo()
                    self.refreshEventsForCurrentMonth()
                } else if !isAuthed {
                    self.googleRepository = nil
                }
            }

        if modelContext != nil {
            seedIfNeededAndFetch()
        } else {
            // 프리뷰 / 컨텍스트 없을 때는 mock 주입
            schedulesInMonth = Self.mockMonthSchedules(around: currentMonth)
        }

        // Phase B HIGH #2 fix: 앱 시작 시 이미 로그인된 세션이면 Google 이벤트를 즉시 fetch.
        // seedIfNeededAndFetch의 SwiftData/mock 경로가 schedulesInMonth를 먼저 채우므로
        // 그 다음 tick에 Google 결과로 덮어쓰게 한다.
        if googleRepository != nil {
            refreshEventsForCurrentMonth()
        }
    }

    /// Phase B M4-2: auth manager로부터 GoogleCalendarClient를 조립해 repo 활성화.
    private func activateGoogleRepo() {
        let client = GoogleCalendarClient(authProvider: authManager)
        self.googleRepository = GoogleCalendarRepository(client: client)
    }

    /// 현재 월에 대해 google repo로부터 이벤트를 가져와 `schedulesInMonth` 갱신.
    /// 로그인 직후 / 월 네비 / manual refresh 시 호출.
    func refreshEventsForCurrentMonth() {
        guard let repo = googleRepository else { return }
        let gridStart = cal.startOfDay(for: datesInMonthGrid(for: currentMonth).first ?? currentMonth)
        guard let gridEnd = cal.date(byAdding: .day, value: 42, to: gridStart) else { return }
        let interval = DateInterval(start: gridStart, end: gridEnd)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let events = try await repo.events(in: interval)
                self.schedulesInMonth = events
                    .compactMap { Self.displayItem(from: $0) }
                    .sorted { $0.startTime < $1.startTime }
            } catch {
                // 네트워크 실패: 기존 표시 유지 + 콘솔 로그 (Phase C에서 토스트 와이어링)
                print("[HomeViewModel] google fetch error: \(error)")
            }
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
        reloadForCurrentMonth()
    }

    /// 가로 스와이프로 다음 달로 이동.
    func goToNextMonth() {
        guard let next = cal.date(byAdding: .month, value: 1, to: currentMonth) else { return }
        currentMonth = next
        reloadForCurrentMonth()
    }

    /// UX 개선: 월 네비 후 "오늘로" 복귀. 오늘 날짜 선택 + 해당 월로 이동.
    func goToToday() {
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        comps.day = 1
        let monthAnchor = cal.date(from: comps) ?? now
        currentMonth = monthAnchor
        selectedDate = cal.startOfDay(for: now)
        expandedWeekStart = weekStart(for: selectedDate)
        reloadForCurrentMonth()
    }

    /// 월 이동 / 외부 변경 후 재페치.
    /// 로그인 → Google Calendar / 미로그인 → SwiftData mock.
    private func reloadForCurrentMonth() {
        if usingGoogleRepo {
            refreshEventsForCurrentMonth()
        } else {
            fetchSchedulesInMonth()
        }
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
        if usingGoogleRepo {
            refreshEventsForCurrentMonth()
        } else {
            fetchSchedulesInMonth()
        }
    }

    // MARK: - Phase B M4-4: Google Calendar create

    /// CalendarAddView가 만든 `Schedule`을 `CalendarEventDraft`로 변환 후 repo.create 호출.
    /// 성공 시 월 그리드 재페치. 실패는 콘솔 로그 (Phase C에서 토스트 와이어링).
    func createOnGoogleCalendar(from schedule: Schedule) {
        guard let repo = googleRepository else { return }

        let hex: String
        switch schedule.category {
        case .work:     hex = "#F56691"
        case .meeting:  hex = "#3B82F6"
        case .meal:     hex = "#FAC430"
        case .exercise: hex = "#40C786"
        case .personal: hex = "#9A5CE8"
        case .general:  hex = "#909094"
        }

        // Schedule은 endTime이 optional. endTime이 nil이면 +1시간 기본.
        let end = schedule.endTime ?? schedule.startTime.addingTimeInterval(3600)

        let draft = CalendarEventDraft(
            calendarId: repo.calendarId,
            title: schedule.title,
            startDate: schedule.startTime,
            endDate: end,
            isAllDay: false,
            location: schedule.location,
            description: schedule.notes,
            colorHex: hex
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await repo.create(draft)
                self.refreshEventsForCurrentMonth()
            } catch {
                print("[HomeViewModel] createOnGoogleCalendar error: \(error)")
            }
        }
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

        // UI v7: 단일일 + 다일간 이벤트 혼합 — TimeBlocks 스타일 가로 바 시각 검증용.
        // multi-day 이벤트는 `dur`(분) 대신 직접 end date를 지정하는 helper 경유.
        func multi(_ startOffset: Int, _ endOffset: Int, _ title: String, _ cat: ScheduleCategory,
                   startHour: Int = 10, endHour: Int = 18) -> ScheduleDisplayItem {
            let s = cal.date(byAdding: .day, value: startOffset, to: today) ?? today
            let e = cal.date(byAdding: .day, value: endOffset, to: today) ?? today
            let start = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: s) ?? s
            let end = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: e) ?? e
            return ScheduleDisplayItem(title: title, category: cat, startTime: start, endTime: end)
        }

        return [
            // 단일일 이벤트
            make(0,  9,  0, 60, "팀 스탠드업", .meeting),
            make(0, 12, 30, 60, "점심 식사", .meal),
            make(2, 10,  0, 90, "기획 리뷰", .work),
            make(4, 19,  0, 60, "헬스장", .exercise),
            make(-2, 15, 0, 60, "개인 독서", .personal),
            make(-7, 14, 0, 60, "치과", .general),
            // 다일간 이벤트 (TimeBlocks 스타일 가로 바)
            multi(1,  3, "제주도 가족 여행", .personal),
            multi(6,  9, "웹디자인 프로젝트", .work),
            multi(-3, -1, "호텔+렌트카 예약", .general),
            multi(8,  8, "월간 보고", .work),
        ]
    }

    /// (v3 호환) 외부에서 mock 요청 시 사용. CalendarAddView 프리뷰 등에서 참조 가능.
    static func mockSchedules(for date: Date) -> [ScheduleDisplayItem] {
        mockMonthSchedules(around: date)
    }

    // MARK: - CalendarEvent → ScheduleDisplayItem (Phase B M4-3)

    /// Shared `CalendarEvent`를 월 그리드/주 확장용 `ScheduleDisplayItem`으로 매핑.
    /// id: `event.calendarId + event.id`의 uuid5-like hash (Stable).
    /// category: colorHex → Schedule.ScheduleCategory 6색 매핑.
    static func displayItem(from event: CalendarEvent) -> ScheduleDisplayItem? {
        // `ScheduleDisplayItem.id`는 UUID 타입. 복합 식별자(`calendarId::id`)를 deterministic UUID로 변환.
        let composite = "\(event.calendarId)::\(event.id)"
        let stableID = Self.deterministicUUID(from: composite)

        return ScheduleDisplayItem(
            id: stableID,
            title: event.title,
            category: category(forHex: event.colorHex),
            startTime: event.startDate,
            endTime: event.endDate,
            location: event.location,
            summary: nil,
            travelTimeMinutes: nil,
            bulletPoints: event.description.map { notes in
                notes
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } ?? []
        )
    }

    /// Hex → Calen 6색 카테고리. Google colorId 기준 매핑과 대응.
    static func category(forHex hex: String) -> ScheduleCategory {
        switch hex.uppercased() {
        case "#F56691": return .work
        case "#3B82F6": return .meeting
        case "#FAC430": return .meal
        case "#40C786": return .exercise
        case "#9A5CE8": return .personal
        default: return .general
        }
    }

    /// `input` 문자열 → deterministic UUID. 서로 다른 이벤트가 같은 UUID를 가질 확률은 사실상 0.
    /// SHA-256 해시의 앞 16바이트로 v4 스타일 UUID를 구성 (variant/version 비트 세팅).
    private static func deterministicUUID(from input: String) -> UUID {
        let data = Data(input.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                Self.sha256(base, data.count, &hash)
            }
        }
        var bytes = Array(hash.prefix(16))
        // RFC 4122 v4 variant bits
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuidTuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidTuple)
    }

    /// CommonCrypto 헤더 직접 import를 피하기 위한 thin wrapper.
    /// 실사용 시 `_CCHashAlgorithm` → `CC_SHA256` 호출. 여기선 CryptoKit 경유.
    private static func sha256(_ ptr: UnsafeRawPointer, _ count: Int, _ out: UnsafeMutablePointer<UInt8>) {
        // CryptoKit의 SHA256 사용 — CommonCrypto 직접 바인딩 대신.
        let data = Data(bytes: ptr, count: count)
        let digest = _SHA256.hash(data: data)
        for (i, byte) in digest.enumerated() where i < 32 {
            out[i] = byte
        }
    }
}

// MARK: - SHA256 (CryptoKit thin wrapper)

/// `_SHA256`: CryptoKit 의존을 파일 내 캡슐화하기 위한 shim. iOS 13+.
private enum _SHA256 {
    static func hash(data: Data) -> [UInt8] {
        let digest = SHA256.hash(data: data)
        return Array(digest)
    }
}
#endif
