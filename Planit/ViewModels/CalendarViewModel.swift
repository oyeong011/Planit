import SwiftUI
import EventKit
import Combine
import Network
import OSLog

struct MirrorFilterStats: Equatable {
    var extCount: Int = 0
    var fingerprintCount: Int = 0
    var suppressCount: Int = 0
    var lastUpdated: Date?
}

struct HistoryCalendarSyncState: Codable {
    var syncToken: String
    var lastFullSyncAt: Date
}

@MainActor
final class CalendarViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedDate: Date = Date() {
        didSet {
            if appleRemindersEnabled {
                fetchAppleReminders(for: selectedDate)
            }
        }
    }
    @Published var currentMonth: Date = Date()
    @Published var todos: [TodoItem] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var historyEvents: [CalendarEvent] = []
    @Published var isLoadingHistory: Bool = false
    @Published var completedEventIDs: Set<String> = []
    @Published var categories: [TodoCategory] = []
    @Published var eventCategoryMappings: [String: EventCategoryMapping] = [:]  // eventID → mapping
    @Published var isOffline: Bool = false
    @Published var pendingEditsCount: Int = 0
    @Published var appleCalendarEnabled: Bool = UserDefaults.standard.bool(forKey: "planit.appleCalendarEnabled") {
        didSet {
            UserDefaults.standard.set(appleCalendarEnabled, forKey: "planit.appleCalendarEnabled")
            if appleCalendarEnabled {
                enableAppleCalendar()
            } else {
                disableAppleCalendar()
            }
        }
    }
    @Published var appleCalendarAccessGranted: Bool = false
    @Published var appleRemindersEnabled: Bool = UserDefaults.standard.bool(forKey: "planit.appleRemindersEnabled") {
        didSet {
            UserDefaults.standard.set(appleRemindersEnabled, forKey: "planit.appleRemindersEnabled")
            if appleRemindersEnabled {
                enableAppleReminders()
            } else {
                disableAppleReminders()
            }
        }
    }
    @Published var appleRemindersAccessGranted: Bool = false
    @Published var appleReminders: [TodoItem] = []
    /// calendarList 스코프 없을 때 true → UI에서 재로그인 배너 표시
    @Published var needsReauth: Bool = false
    /// Calen이 자동 재배치한 Todo ID 집합 (UI 인디케이터용)
    @Published var rescheduledTodoIDs: Set<UUID> = []
    /// Last user-visible CRUD failure for inline UI feedback.
    @Published var lastCRUDError: CRUDErrorNotice?
    @Published var lastMirrorFilterStats = MirrorFilterStats()

    // MARK: - Services

    let authManager: GoogleAuthManager
    lazy var googleService = GoogleCalendarService(auth: authManager)
    weak var goalService: GoalService?
    private let eventStore = EKEventStore()
    private let calendar = Calendar.current
    private let fileManager = FileManager.default

    // DateFormatter를 호출마다 새로 생성하면 42개 셀 렌더링 시마다 alloc 폭증 → 캐시
    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        return f
    }()
    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f
    }()
    private static let formattedDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMd EEEE")
        return f
    }()

    /// Apple Reminders 전용 카테고리 ID (고정)
    static let remindersCategoryID = UUID(uuidString: "00000000-0000-0000-0000-AE1D0DE50001")!

    private var appSupportDir: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Planit", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        return dir
    }

    private var todosPath: URL { appSupportDir.appendingPathComponent("todos.json") }
    private var completedEventsPath: URL { appSupportDir.appendingPathComponent("completed_events.json") }
    private var categoriesPath: URL { appSupportDir.appendingPathComponent("categories.json") }
    private var eventCachePath: URL { appSupportDir.appendingPathComponent("events_cache.json") }
    private var historyEventsCachePath: URL { appSupportDir.appendingPathComponent("events_history_cache.json") }
    private var pendingEditsPath: URL { appSupportDir.appendingPathComponent("pending_edits.json") }
    private var eventCategoryMappingsPath: URL { appSupportDir.appendingPathComponent("event_category_mappings.json") }
    private let historySyncStatesKey = "planit.calendarHistorySyncStates"
    private let pendingEditsIntegrityMigratedKey = "planit.pendingEditsIntegrityMigrated.v1"

    // MARK: - Init

    private var refreshTimer: Timer?
    private var dateChangeTimer: Timer?
    private var googleFetchTask: Task<Void, Never>?
    private var googleFetchMonthKey: String?
    private var googleFetchGeneration = 0
    /// 월별 마지막 실제 fetch 시각 — TTL 내 중복 요청 방지
    private var lastFetchAtByMonthKey: [String: Date] = [:]
    nonisolated static let googleFetchTTL: TimeInterval = 120
    nonisolated static let periodicRefreshInterval: TimeInterval = 180

    private var notificationObserver: Any?
    private var popoverObserver: Any?
    private var authCancellable: AnyCancellable?
    private var authSucceededCancellable: AnyCancellable?
    /// syncPendingEdits 재진입 방지 플래그
    private var isSyncingPendingEdits = false

    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.oy.calen.pathmonitor", qos: .utility)

    private func recordCRUDFailure(
        operation: CRUDOperation,
        source: CRUDSource,
        eventID: String? = nil,
        error: Error? = nil,
        userVisible: Bool = true
    ) {
        let notice = CRUDErrorNotice(operation: operation, source: source, eventID: eventID)
        let errorSummary = error.map(Self.sanitizedErrorSummary) ?? "none"
        PlanitLoggers.crud.error(
            "CRUD failure operation=\(operation.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public) eventID=\(notice.logMetadata["eventID"] ?? "none", privacy: .public) error=\(errorSummary, privacy: .public)"
        )
        // update/delete 403 → 재인증 필요 플래그 설정
        if Self.shouldMarkNeedsReauth(after: error) {
            needsReauth = true
        }
        if userVisible {
            lastCRUDError = notice
        }
    }

    func dismissLastCRUDError() {
        lastCRUDError = nil
    }

    func reportCRUDFailure(
        operation: CRUDOperation,
        source: CRUDSource,
        eventID: String? = nil,
        error: Error? = nil
    ) {
        recordCRUDFailure(operation: operation, source: source, eventID: eventID, error: error)
    }

    nonisolated static func sanitizedErrorSummary(_ error: Error) -> String {
        if let calendarError = error as? GoogleCalendarError {
            switch calendarError {
            case .httpStatus(let code):
                return "GoogleCalendarError.httpStatus(\(code))"
            }
        }
        if let urlError = error as? URLError {
            return "URLError.\(urlError.code.rawValue)"
        }
        return String(reflecting: type(of: error))
    }

    nonisolated static func shouldMarkNeedsReauth(after error: Error?) -> Bool {
        guard let calendarError = error as? GoogleCalendarError else { return false }
        switch calendarError {
        case .httpStatus(let code):
            return code == 403
        }
    }

    nonisolated static func shouldSkipGoogleFetch(lastFetch: Date?, now: Date = Date(), force: Bool) -> Bool {
        guard !force, let lastFetch else { return false }
        return now.timeIntervalSince(lastFetch) < googleFetchTTL
    }

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
        loadCategories()
        loadTodos()
        loadTodoOrder()
        loadDayItemOrder()
        loadCompletedEvents()
        loadPendingEdits()
        loadEventCategoryMappings()
        startPeriodicRefresh()

        // 자정 롤오버 + 정오 리뷰 트리거 등록
        Task { @MainActor in
            MidnightRolloverService.shared.performIfNeeded(viewModel: self)
            MidnightRolloverService.shared.scheduleAllTriggers()
        }

        // 날짜 변경 감지 (앱이 켜진 상태로 자정 넘길 때)
        observeDateChange()

        // 로그아웃 감지: 구글 캐시 + 이벤트 정리
        authCancellable = authManager.$isAuthenticated.dropFirst().sink { [weak self] authenticated in
            guard let self, !authenticated else { return }
            self.googleService.clearCache()
            self.calendarEvents.removeAll { $0.source == .google }
            self.needsReauth = false
            self.lastCRUDError = nil
            self.cacheEvents(self.calendarEvents)
        }

        // 팝오버 열릴 때 force-fetch — 외부 캘린더 앱/웹에서 추가된 이벤트 즉시 반영
        popoverObserver = NotificationCenter.default.addObserver(
            forName: .calenPopoverWillShow, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.authManager.isAuthenticated else { return }
                self.fetchEventsFromGoogle(for: self.currentMonth, force: true)
            }
        }

        // OAuth 성공(로그인 + 재연결 모두)마다 이벤트 리프레시
        // — isAuthenticated 변화 없는 재연결(true→true)도 처리
        authSucceededCancellable = authManager.authSucceeded.sink { [weak self] in
            guard let self else { return }
            self.googleService.clearCache()
            self.googleFetchTask?.cancel()
            self.googleFetchTask = nil
            self.googleFetchMonthKey = nil
            self.lastFetchAtByMonthKey.removeAll()
            self.isOffline = false
            self.needsReauth = false
            self.lastCRUDError = nil
            self.fetchEventsFromGoogle(for: self.currentMonth, force: true)
            self.loadHistory()
        }

        // Load cached events first (instant display), then try network
        loadCachedEvents()
        loadHistory()

        if authManager.isAuthenticated {
            fetchEventsFromGoogle(for: currentMonth, force: true)
            // Apple Calendar도 활성화되어 있으면 병합
            if appleCalendarEnabled {
                enableAppleCalendar()
            }
        } else {
            requestCalendarAccess()
            observeCalendarChanges()
        }

        // Apple Reminders 활성화되어 있으면 접근 요청
        if appleRemindersEnabled {
            enableAppleReminders()
        }

        // 네트워크 복구 감지 → pending edits 자동 플러시
        startNetworkMonitoring()
    }

    deinit {
        googleFetchTask?.cancel()
        googleFetchTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        suppressedAppleMirrors.removeAll()
        dateChangeTimer?.invalidate()
        dateChangeTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = popoverObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = reminderObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Periodic refresh every 3 minutes
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.periodicRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cleanupExpiredAppleMirrorSuppressions()
                self.refreshEvents()
            }
        }
    }

    /// 자정(00:00) 날짜 변경 감지 → 재배치 실행
    private func observeDateChange() {
        var lastDay = Calendar.current.startOfDay(for: Date())
        dateChangeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let today = Calendar.current.startOfDay(for: Date())
            guard today > lastDay else { return }
            lastDay = today
            Task { @MainActor in
                // 자정: 미완료 할 일 스마트 재배치
                MidnightRolloverService.shared.performIfNeeded(viewModel: self)
                self.currentMonth = today
                self.selectedDate = today
                self.refreshEvents()
            }
        }
    }

    func refreshEvents() {
        if authManager.isAuthenticated {
            fetchEventsFromGoogle(for: currentMonth)
        } else {
            fetchEventsFromEventKit(for: currentMonth)
        }
        // Reminders도 갱신
        if appleRemindersEnabled {
            fetchAppleReminders(for: selectedDate)
        }
    }

    // MARK: - Apple Calendar (EventKit 병합 모드)

    nonisolated static func eventsExcludingAppleCalendar(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.filter { $0.source != .apple }
    }

    nonisolated static func inferredEventSource(
        eventID: String,
        calendarID: String,
        events: [CalendarEvent],
        googleAuthenticated: Bool
    ) -> CalendarEventSource {
        if let loaded = events.first(where: { $0.id == eventID }) {
            return loaded.source
        }
        if calendarID.hasPrefix("apple:") {
            return .apple
        }
        if calendarID.hasPrefix("google:") {
            return .google
        }
        if eventID.hasPrefix("apple-") {
            return .apple
        }
        if eventID.hasPrefix("pending-") {
            return .google
        }
        return googleAuthenticated ? .google : .local
    }

    nonisolated static func eventKitLookupIdentifier(for eventID: String) -> String {
        if eventID.hasPrefix("apple-") {
            return String(eventID.dropFirst("apple-".count))
        }
        return eventID
    }

    nonisolated static func deduplicatedCalendarEvents(
        _ events: [CalendarEvent],
        todoGoogleEventIDs: Set<String>
    ) -> [CalendarEvent] {
        var result: [CalendarEvent] = []

        for event in events {
            if event.source == .google, todoGoogleEventIDs.contains(event.id) {
                continue
            }

            if let existingIndex = result.firstIndex(where: { existing in
                existing.id == event.id || areCalendarMirrors(existing, event)
            }) {
                if result[existingIndex].id == event.id || shouldPreferCalendarEvent(event, over: result[existingIndex]) {
                    result[existingIndex] = event
                }
            } else {
                result.append(event)
            }
        }

        return result
    }

    struct SuppressKey: Hashable {
        let title: String
        let oldStartMinute: Int
        let calendarID: String

        init(title: String, oldStartMinute: Int, calendarID: String) {
            self.title = Self.normalizedTitle(title)
            self.oldStartMinute = oldStartMinute
            self.calendarID = calendarID
        }

        nonisolated static func normalizedTitle(_ title: String) -> String {
            title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    struct AppleMirrorFilterResult {
        let events: [CalendarEvent]
        let mirrorByExternalID: Int
        let mirrorByFingerprint: Int
        let mirrorBySuppress: Int
    }

    struct LegacyAppleMirrorFilterResult {
        let events: [CalendarEvent]
        let stats: MirrorFilterStats
    }

    private nonisolated static func startMinute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    private nonisolated static func durationMinutes(_ event: CalendarEvent) -> Int {
        max(0, Int((event.endDate.timeIntervalSince(event.startDate) / 60).rounded()))
    }

    nonisolated static func appleMirrorSuppressKey(for event: CalendarEvent) -> SuppressKey {
        SuppressKey(
            title: event.title,
            oldStartMinute: startMinute(event.startDate),
            calendarID: event.calendarID
        )
    }

    nonisolated static func appleMirrorFingerprint(_ event: CalendarEvent) -> String {
        let title = SuppressKey.normalizedTitle(event.title)
        if event.isAllDay {
            // all-day는 시작 '날짜'만 비교 (minute/duration은 Apple↔Google 다름)
            let day = Calendar.current.startOfDay(for: event.startDate)
            let dayKey = Int(day.timeIntervalSince1970)
            return "allday|\(title)|\(dayKey)"
        }
        let minute = startMinute(event.startDate)
        return "\(title)|\(minute)|\(durationMinutes(event))|\(event.isAllDay)"
    }

    nonisolated static func filteredAppleCalendarEvents(
        _ appleRaw: [CalendarEvent],
        googleEvents: [CalendarEvent],
        suppressedAppleMirrors: [SuppressKey: Date],
        now: Date
    ) -> AppleMirrorFilterResult {
        let googleIDs = Set(googleEvents.map(\.id))
        let googleFingerprints = Set(googleEvents.map(appleMirrorFingerprint))
        let activeSuppressKeys = Set(suppressedAppleMirrors.filter { $0.value > now }.keys)

        var mirrorByExternalID = 0
        var mirrorByFingerprint = 0
        var mirrorBySuppress = 0
        let events = appleRaw.filter { apple in
            if let ext = apple.externalID, googleIDs.contains(ext) {
                mirrorByExternalID += 1
                return false
            }
            if googleFingerprints.contains(appleMirrorFingerprint(apple)) {
                mirrorByFingerprint += 1
                return false
            }
            if activeSuppressKeys.contains(appleMirrorSuppressKey(for: apple)) {
                mirrorBySuppress += 1
                return false
            }
            return true
        }

        return AppleMirrorFilterResult(
            events: events,
            mirrorByExternalID: mirrorByExternalID,
            mirrorByFingerprint: mirrorByFingerprint,
            mirrorBySuppress: mirrorBySuppress
        )
    }

    nonisolated static func filteredAppleMirrorEvents(
        _ appleRaw: [CalendarEvent],
        googleEvents: [CalendarEvent],
        suppressedTitles: Set<String>,
        updatedAt: Date
    ) -> LegacyAppleMirrorFilterResult {
        let suppressed = Dictionary(uniqueKeysWithValues: appleRaw
            .filter { suppressedTitles.contains($0.title) }
            .map { (appleMirrorSuppressKey(for: $0), updatedAt.addingTimeInterval(1)) })
        let result = filteredAppleCalendarEvents(
            appleRaw,
            googleEvents: googleEvents,
            suppressedAppleMirrors: suppressed,
            now: updatedAt
        )
        return LegacyAppleMirrorFilterResult(
            events: result.events,
            stats: MirrorFilterStats(
                extCount: result.mirrorByExternalID,
                fingerprintCount: result.mirrorByFingerprint,
                suppressCount: result.mirrorBySuppress,
                lastUpdated: updatedAt
            )
        )
    }

    private nonisolated static func areCalendarMirrors(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        guard lhs.id != rhs.id else { return true }
        let canMirror = lhs.source != rhs.source || lhs.id.hasPrefix("pending-") || rhs.id.hasPrefix("pending-")
        guard canMirror else { return false }
        return eventFingerprint(lhs) == eventFingerprint(rhs)
    }

    private nonisolated static func eventFingerprint(_ event: CalendarEvent) -> String {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let start = Int(event.startDate.timeIntervalSinceReferenceDate.rounded())
        let end = Int(event.endDate.timeIntervalSinceReferenceDate.rounded())
        return "\(title)|\(start)|\(end)|\(event.isAllDay)"
    }

    private nonisolated static func shouldPreferCalendarEvent(_ candidate: CalendarEvent, over existing: CalendarEvent) -> Bool {
        if existing.id.hasPrefix("pending-"), !candidate.id.hasPrefix("pending-") {
            return true
        }
        return sourcePriority(candidate.source) > sourcePriority(existing.source)
    }

    private nonisolated static func sourcePriority(_ source: CalendarEventSource) -> Int {
        switch source {
        case .google: return 3
        case .apple: return 2
        case .local: return 1
        }
    }

    func enableAppleCalendar() {
        requestAppleCalendarAccess()
    }

    func disableAppleCalendar() {
        removeCalendarObserver()
        appleCalendarAccessGranted = false
        calendarEvents = Self.eventsExcludingAppleCalendar(calendarEvents)
        applyEventCategoryMappings()
        cacheEvents(calendarEvents)
    }

    /// Apple Calendar 접근 권한 요청 (Google 인증 상태에서 병합용)
    func requestAppleCalendarAccess() {
        if #available(iOS 17.0, macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.appleCalendarEnabled else {
                        self.appleCalendarAccessGranted = false
                        return
                    }
                    self.appleCalendarAccessGranted = granted && error == nil
                    if self.appleCalendarAccessGranted {
                        self.observeCalendarChanges()
                        // 현재 Google 이벤트에 Apple Calendar 이벤트 병합
                        self.mergeAppleCalendarEvents(for: self.currentMonth)
                    } else {
                        self.calendarEvents = Self.eventsExcludingAppleCalendar(self.calendarEvents)
                        self.cacheEvents(self.calendarEvents)
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.appleCalendarEnabled else {
                        self.appleCalendarAccessGranted = false
                        return
                    }
                    self.appleCalendarAccessGranted = granted && error == nil
                    if self.appleCalendarAccessGranted {
                        self.observeCalendarChanges()
                        self.mergeAppleCalendarEvents(for: self.currentMonth)
                    } else {
                        self.calendarEvents = Self.eventsExcludingAppleCalendar(self.calendarEvents)
                        self.cacheEvents(self.calendarEvents)
                    }
                }
            }
        }
    }

    /// EventKit에서 이벤트를 가져와 로컬 Apple Calendar 이벤트 목록 반환
    func fetchLocalCalendarEvents(for month: Date) -> [CalendarEvent] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        // all-day 이벤트 누락 방지 — 월 경계 ±1일로 확장해서 fetch.
        // EKEventStore.predicateForEvents는 주어진 범위에 '걸친' 이벤트를 반환하지만,
        // timezone 경계 이슈로 월 첫날/마지막날 all-day를 놓치는 경우가 보고됨.
        let expandedStart = calendar.date(byAdding: .day, value: -1, to: monthInterval.start) ?? monthInterval.start
        let expandedEnd = calendar.date(byAdding: .day, value: 1, to: monthInterval.end) ?? monthInterval.end
        let predicate = eventStore.predicateForEvents(
            withStart: expandedStart,
            end: expandedEnd,
            calendars: nil
        )
        let ekEvents = eventStore.events(matching: predicate)
        let allDayCount = ekEvents.filter { $0.isAllDay }.count
        PlanitLoggers.sync.info(
            "EventKit fetch month=\(Self.logDate(month), privacy: .public) total=\(ekEvents.count, privacy: .public) allDay=\(allDayCount, privacy: .public)"
        )
        return ekEvents.map { event in
            let cgColor = event.calendar.cgColor ?? CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
            return CalendarEvent(
                id: "apple-\(event.eventIdentifier ?? UUID().uuidString)",
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                color: Color(cgColor: cgColor),
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                calendarID: "apple:\(event.calendar.calendarIdentifier)",
                source: .apple,
                // EventKit이 외부 제공자(Google 등)와 동기화된 경우 원본 ID를 담고 있음.
                // 이것으로 Google API에서 직접 받은 이벤트와 중복 제거.
                externalID: event.calendarItemExternalIdentifier
            )
        }
    }

    /// Google 이벤트에 Apple Calendar 이벤트를 병합.
    /// Apple 미러(macOS Calendar가 Google 계정을 연결한 경우) 제거 전략 3단:
    ///   1) externalID == Google event.id 매칭 (가장 안전한 dedup)
    ///   2) 현재 위치 fingerprint(title + startDate 분 + duration + allDay) 동일 → 미러
    ///   3) 최근 수정된 이벤트의 (title, oldStartMinute, calendarID)와 동일 →
    ///      macOS Calendar가 Google sync 받는 지연 동안 해당 위치 Apple 미러만 차단
    func mergeAppleCalendarEvents(for month: Date) {
        guard appleCalendarEnabled, appleCalendarAccessGranted else { return }
        let googleEvents = calendarEvents.filter { $0.source == .google }

        // 만료된 suppress 엔트리 청소
        let now = Date()
        cleanupExpiredAppleMirrorSuppressions(now: now)

        // 현재 보는 월이 오늘이 속한 월과 다르면 오늘 월도 함께 병합한다.
        // 그렇지 않으면 월을 이동할 때마다 리뷰탭 "오늘" 달성률 분모가 바뀐다 (Apple 이벤트가 빠짐).
        // 5초 캐시로 짧은 시간 내 반복 호출 시 EventKit 쿼리 재실행 방지 (CPU 부하 완화).
        var appleRaw = fetchLocalCalendarEvents(for: month)
        let today = Date()
        if !calendar.isDate(today, equalTo: month, toGranularity: .month) {
            let now = Date()
            let cacheValid = todayAppleCache.flatMap {
                now.timeIntervalSince($0.fetchedAt) < 5 ? $0.events : nil
            }
            let todayAppleRaw: [CalendarEvent]
            if let cached = cacheValid {
                todayAppleRaw = cached
            } else {
                todayAppleRaw = fetchLocalCalendarEvents(for: today)
                todayAppleCache = (fetchedAt: now, events: todayAppleRaw)
            }
            let existingIDs = Set(appleRaw.map { $0.id })
            appleRaw.append(contentsOf: todayAppleRaw.filter { !existingIDs.contains($0.id) })
        }
        let filterResult = Self.filteredAppleCalendarEvents(
            appleRaw,
            googleEvents: googleEvents,
            suppressedAppleMirrors: suppressedAppleMirrors,
            now: now
        )
        let appleEvents = filterResult.events
        // 진단 UI용 stats 업데이트 (narrow key 기반 카운트 그대로 표시)
        lastMirrorFilterStats = MirrorFilterStats(
            extCount: filterResult.mirrorByExternalID,
            fingerprintCount: filterResult.mirrorByFingerprint,
            suppressCount: filterResult.mirrorBySuppress,
            lastUpdated: now
        )

        var merged = calendarEvents.filter { $0.source != .apple }
        let existingNonAppleCount = merged.count
        merged.append(contentsOf: appleEvents)
        let todoEventIds = Set(todos.compactMap { $0.googleEventId })
        let deduped = Self.deduplicatedCalendarEvents(merged, todoGoogleEventIDs: todoEventIds)
        PlanitLoggers.sync.info(
            "Merged Apple events month=\(Self.logDate(month), privacy: .public) existingNonApple=\(existingNonAppleCount, privacy: .public) appleRaw=\(appleRaw.count, privacy: .public) mirrorByExt=\(filterResult.mirrorByExternalID, privacy: .public) mirrorByFingerprint=\(filterResult.mirrorByFingerprint, privacy: .public) mirrorBySuppress=\(filterResult.mirrorBySuppress, privacy: .public) appleKept=\(appleEvents.count, privacy: .public) deduped=\(deduped.count, privacy: .public)"
        )
        calendarEvents = deduped
        applyEventCategoryMappings()
    }

    /// 최근 Google 수정한 이벤트의 Apple 미러 복합키 → 유예 시각.
    private var suppressedAppleMirrors: [SuppressKey: Date] = [:]

    private nonisolated static let appleMirrorSuppressTTL: TimeInterval = 60

    /// 최근 update/move한 Google 이벤트 id → 유예 시각.
    /// Google Calendar의 eventual consistency로 PATCH 직후 fetch가 옛 상태를
    /// 반환하면 local에서 이동/수정해둔 값이 옛 값으로 덮어씌워져 원본 위치에
    /// 이벤트가 재출현하는 문제가 있다. 이 기간 동안은 서버 응답에서 해당 id의
    /// 이벤트를 무시하고 local 값을 유지한다.
    private var recentlyMutatedGoogleIDs: [String: Date] = [:]
    private var recentlyDeletedGoogleIDs: [String: Date] = [:]

    private nonisolated static let recentlyMutatedTTL: TimeInterval = 12
    private nonisolated static let recentlyDeletedTTL: TimeInterval = 30

    /// today 월의 Apple 이벤트 5초 캐시 — 월 이동 시 EventKit 중복 쿼리 부하 경감.
    private var todayAppleCache: (fetchedAt: Date, events: [CalendarEvent])?

    private func markRecentlyMutatedGoogle(_ eventID: String,
                                           ttl: TimeInterval = recentlyMutatedTTL) {
        let now = Date()
        recentlyMutatedGoogleIDs[eventID] = now.addingTimeInterval(ttl)
        recentlyMutatedGoogleIDs = recentlyMutatedGoogleIDs.filter { $0.value > now }
    }

    private func isRecentlyMutatedGoogle(_ eventID: String) -> Bool {
        guard let expiresAt = recentlyMutatedGoogleIDs[eventID] else { return false }
        if expiresAt <= Date() {
            recentlyMutatedGoogleIDs.removeValue(forKey: eventID)
            return false
        }
        return true
    }

    private func markRecentlyDeletedGoogle(_ eventID: String) {
        let now = Date()
        recentlyDeletedGoogleIDs[eventID] = now.addingTimeInterval(Self.recentlyDeletedTTL)
        recentlyDeletedGoogleIDs = recentlyDeletedGoogleIDs.filter { $0.value > now }
    }

    private func isRecentlyDeletedGoogle(_ eventID: String) -> Bool {
        guard let expiresAt = recentlyDeletedGoogleIDs[eventID] else { return false }
        if expiresAt <= Date() {
            recentlyDeletedGoogleIDs.removeValue(forKey: eventID)
            return false
        }
        return true
    }

    private func cleanupExpiredAppleMirrorSuppressions(now: Date = Date()) {
        suppressedAppleMirrors = suppressedAppleMirrors.filter { $0.value > now }
    }

    /// updateGoogleEvent 등이 호출할 suppress 등록 헬퍼
    fileprivate func suppressAppleMirror(
        title: String,
        startDate: Date,
        calendarID: String,
        for duration: TimeInterval = CalendarViewModel.appleMirrorSuppressTTL
    ) {
        let key = SuppressKey(
            title: title,
            oldStartMinute: Self.startMinute(startDate),
            calendarID: calendarID
        )
        guard !key.title.isEmpty, !key.calendarID.isEmpty else { return }
        suppressedAppleMirrors[key] = Date().addingTimeInterval(duration)
    }

    @discardableResult
    private func suppressAppleMirrorCandidates(
        eventID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        appleCandidates: [CalendarEvent]
    ) -> Set<SuppressKey> {
        let normalizedTitle = SuppressKey.normalizedTitle(title)
        guard !normalizedTitle.isEmpty else { return [] }

        let targetMinute = Self.startMinute(startDate)
        let targetDuration = max(0, Int((endDate.timeIntervalSince(startDate) / 60).rounded()))
        let byExternalID = appleCandidates.filter {
            $0.externalID == eventID
            && Self.startMinute($0.startDate) == targetMinute
        }
        let byExactPosition = appleCandidates.filter {
            SuppressKey.normalizedTitle($0.title) == normalizedTitle
            && Self.startMinute($0.startDate) == targetMinute
            && Self.durationMinutes($0) == targetDuration
            && $0.isAllDay == isAllDay
        }
        let byLoosePosition = appleCandidates.filter {
            SuppressKey.normalizedTitle($0.title) == normalizedTitle
            && Self.startMinute($0.startDate) == targetMinute
        }

        let matchedCandidates = byExternalID.isEmpty
            ? (byExactPosition.isEmpty ? byLoosePosition : byExactPosition)
            : byExternalID
        let keys = Set(matchedCandidates.map(Self.appleMirrorSuppressKey))
        for key in keys {
            suppressAppleMirror(title: key.title, startDate: startDate, calendarID: key.calendarID)
        }
        return keys
    }

    // MARK: - Apple Reminders (EventKit)

    func enableAppleReminders() {
        requestAppleRemindersAccess()
    }

    func disableAppleReminders() {
        removeReminderObserver()
        appleReminders = []
        appleRemindersAccessGranted = false
    }

    /// Apple Reminders 접근 권한 요청
    func requestAppleRemindersAccess() {
        if #available(iOS 17.0, macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { [weak self] granted, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.appleRemindersEnabled else {
                        self.appleRemindersAccessGranted = false
                        return
                    }
                    self.appleRemindersAccessGranted = granted && error == nil
                    if self.appleRemindersAccessGranted {
                        self.observeReminderChanges()
                        self.fetchAppleReminders(for: self.selectedDate)
                    } else {
                        self.appleReminders = []
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.appleRemindersEnabled else {
                        self.appleRemindersAccessGranted = false
                        return
                    }
                    self.appleRemindersAccessGranted = granted && error == nil
                    if self.appleRemindersAccessGranted {
                        self.observeReminderChanges()
                        self.fetchAppleReminders(for: self.selectedDate)
                    } else {
                        self.appleReminders = []
                    }
                }
            }
        }
    }

    private var reminderObserver: Any?

    private func removeReminderObserver() {
        if let observer = reminderObserver {
            NotificationCenter.default.removeObserver(observer)
            reminderObserver = nil
        }
    }

    private func observeReminderChanges() {
        // EKEventStoreChanged는 reminders 변경도 포함
        guard reminderObserver == nil else { return }
        reminderObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.appleRemindersEnabled else { return }
                self.fetchAppleReminders(for: self.selectedDate)
            }
        }
    }

    /// Reminders 카테고리가 없으면 생성
    func ensureRemindersCategory() {
        guard !categories.contains(where: { $0.id == Self.remindersCategoryID }) else { return }
        let cat = TodoCategory(id: Self.remindersCategoryID, name: "미리알림", colorHex: "#FF9500")
        categories.append(cat)
        saveCategories()
    }

    /// 특정 날짜의 Apple Reminders를 가져와 appleReminders에 저장
    func fetchAppleReminders(for date: Date) {
        guard appleRemindersEnabled, appleRemindersAccessGranted else {
            appleReminders = []
            return
        }
        ensureRemindersCategory()

        // 미완료 + 완료된 미리알림 모두 가져오기 (해당 날짜)
        let predicate = eventStore.predicateForReminders(in: nil)

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            Task { @MainActor in
                guard let self = self, let reminders = reminders else { return }
                guard self.appleRemindersEnabled, self.appleRemindersAccessGranted else {
                    self.appleReminders = []
                    return
                }

                let targetDay = self.calendar.startOfDay(for: date)
                let items: [TodoItem] = reminders.compactMap { reminder in
                    // 1) 시스템 안내/업그레이드 메시지 등 '가짜 미리알림' 필터
                    guard Self.isMeaningfulReminder(reminder) else { return nil }

                    // 2) 완료된 미리알림은 오늘 날짜에서 최근 완료만 유지 (1일 이내)
                    if reminder.isCompleted {
                        if let completionDate = reminder.completionDate {
                            let ageDays = Calendar.current.dateComponents([.day], from: completionDate, to: Date()).day ?? 999
                            guard ageDays <= 1 else { return nil }
                        } else {
                            return nil
                        }
                    }

                    // 3) due date가 있는 경우 해당 날짜만 표시
                    if let dueDateComponents = reminder.dueDateComponents,
                       let dueDate = Calendar.current.date(from: dueDateComponents) {
                        let reminderDay = self.calendar.startOfDay(for: dueDate)
                        guard reminderDay == targetDay else { return nil }
                    } else {
                        // due date가 없는 미리알림은 오늘만 표시
                        guard self.calendar.isDateInToday(date) else { return nil }
                    }

                    let dueDate: Date
                    if let dc = reminder.dueDateComponents,
                       let d = Calendar.current.date(from: dc) {
                        dueDate = d
                    } else {
                        dueDate = date
                    }

                    return TodoItem(
                        title: reminder.title ?? "(제목 없음)",
                        categoryID: Self.remindersCategoryID,
                        isCompleted: reminder.isCompleted,
                        date: dueDate,
                        source: .appleReminder,
                        appleReminderIdentifier: reminder.calendarItemIdentifier
                    )
                }

                self.appleReminders = items
            }
        }
    }

    /// Apple Reminder의 완료 상태를 토글
    func toggleAppleReminder(identifier: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        reminder.isCompleted.toggle()
        do {
            try eventStore.save(reminder, commit: true)
            // UI 업데이트
            if let idx = appleReminders.firstIndex(where: { $0.appleReminderIdentifier == identifier }) {
                appleReminders[idx].isCompleted = reminder.isCompleted
            }
        } catch {
            PlanitLoggers.crud.error("Apple reminder toggle failed eventID=\(identifier, privacy: .public) error=\(Self.sanitizedErrorSummary(error), privacy: .public)")
        }
    }

    /// 특정 날짜의 Apple Reminders 반환 (이미 fetch된 것에서 필터)
    func appleRemindersForDate(_ date: Date) -> [TodoItem] {
        appleReminders.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Apple Reminders에서 스팸/시스템 메시지 류 'fake reminder' 필터.
    /// - 빈 제목 / 공백만 있는 제목
    /// - Apple이 자동 생성하는 '이 목록의 작성자가 미리 알림을 업그레이드했습니다' 등 안내 메시지
    /// - 구독 전용 캘린더의 reminder (allowsContentModifications == false)
    private static func isMeaningfulReminder(_ reminder: EKReminder) -> Bool {
        guard let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return false }

        // 구독 전용(쓰기 불가) 캘린더는 외부 소스 — 앱에서 관리 불가
        if reminder.calendar?.allowsContentModifications == false { return false }

        // Apple 시스템 안내 메시지 패턴 (ko/en 주요 시즌 메시지)
        let systemPatterns = [
            "업그레이드했습니다",     // 이 목록의 작성자가 미리 알림을 업그레이드했습니다.
            "upgraded",                 // This list was upgraded...
            "미리 알림이 보이지",
            "Reminders not showing",
            "업그레이드하시겠습니까",
            "Upgrade to this version",
        ]
        let lowered = title.lowercased()
        for pat in systemPatterns {
            if title.contains(pat) || lowered.contains(pat.lowercased()) { return false }
        }
        return true
    }

    // MARK: - Google Calendar API

    func fetchEventsFromGoogle(for month: Date, force: Bool = false) {
        let key = monthKey(month)
        if googleFetchTask != nil, googleFetchMonthKey == key {
            // Timers, popover lifecycle, and CRUD callbacks can request the same month at once.
            PlanitLoggers.sync.info("Skipping duplicate in-flight Google fetch month=\(key, privacy: .public)")
            return
        }

        // 2분 TTL — 동일 월은 2분 내 재요청 skip (force=true이면 무시)
        let now = Date()
        if Self.shouldSkipGoogleFetch(lastFetch: lastFetchAtByMonthKey[key], now: now, force: force) {
            PlanitLoggers.sync.info("Skipping TTL-throttled Google fetch month=\(key, privacy: .public)")
            return
        }

        // 실제 fetch 시작 시각 기록
        lastFetchAtByMonthKey[key] = now

        googleFetchTask?.cancel()
        googleFetchMonthKey = key
        googleFetchGeneration += 1
        let generation = googleFetchGeneration
        googleFetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.googleFetchGeneration == generation {
                    self.googleFetchTask = nil
                    self.googleFetchMonthKey = nil
                }
            }
            // Try syncing pending edits first
            await syncPendingEdits()
            guard !Task.isCancelled else { return }

            do {
                // 현재 달 + 인접 달(격자에 표시되는 날짜들) 병렬 fetch
                let prevMonth = calendar.date(byAdding: .month, value: -1, to: month) ?? month
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) ?? month

                async let current = googleService.fetchEvents(for: month)
                async let prev = googleService.fetchEvents(for: prevMonth)
                async let next = googleService.fetchEvents(for: nextMonth)

                var merged: [CalendarEvent] = []
                var seen = Set<String>()
                for batch in try await [current, prev, next] {
                    guard !Task.isCancelled else { return }
                    for ev in batch where seen.insert(ev.id).inserted {
                        merged.append(ev)
                    }
                }
                guard !Task.isCancelled else { return }

                // Google 이벤트에 source 태그 설정
                for i in merged.indices {
                    merged[i].source = .google
                }
                let todoEventIds = Set(self.todos.compactMap { $0.googleEventId })
                let deduped = Self.deduplicatedCalendarEvents(merged, todoGoogleEventIDs: todoEventIds)
                PlanitLoggers.sync.info(
                    "Fetched Google events month=\(Self.logDate(month), privacy: .public) raw=\(merged.count, privacy: .public) deduped=\(deduped.count, privacy: .public) todoMirrors=\(todoEventIds.count, privacy: .public)"
                )
                // Google eventual consistency로 옛 상태가 올 수 있어, 최근 mutate한
                // id는 서버 응답 대신 local 값을 유지한다 (드래그 이동 직후 원본 재출현 방지).
                // 최근 삭제한 id는 서버가 아직 반환하더라도 필터링 (30초 TTL).
                let localByID = Dictionary(uniqueKeysWithValues: self.calendarEvents.map { ($0.id, $0) })
                let reconciled: [CalendarEvent] = deduped.compactMap { serverEvent in
                    if self.isRecentlyDeletedGoogle(serverEvent.id) { return nil }
                    if self.isRecentlyMutatedGoogle(serverEvent.id),
                       let localCopy = localByID[serverEvent.id] {
                        return localCopy
                    }
                    return serverEvent
                }
                self.calendarEvents = reconciled
                self.isOffline = false
                self.needsReauth = googleService.needsReauth
                cacheEvents(deduped)
                // Google extendedProperties에 저장된 카테고리 매핑을 로컬로 복원 (재설치 후 자동 복구)
                restoreCategoryMappingsFromGoogle()
                // Apple Calendar 이벤트 병합
                mergeAppleCalendarEvents(for: month)
                applyEventCategoryMappings()
            } catch {
                PlanitLoggers.sync.error("Google Calendar fetch failed; using cached data error=\(Self.sanitizedErrorSummary(error), privacy: .public)")
                self.isOffline = true
                self.needsReauth = googleService.needsReauth
                loadCachedEvents()
                // 오프라인에서도 Apple Calendar 병합
                mergeAppleCalendarEvents(for: month)
                applyEventCategoryMappings()
            }
        }
    }

    func addEventToGoogleCalendar(title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        Task {
            do {
                if try await googleService.createEvent(title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay) == nil {
                    recordCRUDFailure(operation: .create, source: .google)
                }
                fetchEventsFromGoogle(for: currentMonth, force: true)
            } catch {
                guard Self.shouldQueueGoogleMutation(after: error) else {
                    recordCRUDFailure(operation: .create, source: .google, error: error)
                    return
                }
                PlanitLoggers.sync.info("Offline Google create queued")
                queuePendingEdit(PendingCalendarEdit(
                    action: "create", title: title, startDate: startDate,
                    endDate: endDate, isAllDay: isAllDay))
                // Optimistic local update
                let tempEvent = CalendarEvent(
                    id: "pending-\(UUID().uuidString)", title: title,
                    startDate: startDate, endDate: endDate,
                    color: .blue, isAllDay: isAllDay,
                    calendarName: "Google", calendarID: "google:primary", source: .google)
                calendarEvents.append(tempEvent)
                applyEventCategoryMappings()
                cacheEvents(calendarEvents)
            }
        }
    }

    func updateGoogleEvent(eventID: String, calendarID: String = "google:primary", title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        // 낙관 UI: API 호출 전에 로컬 state를 새 날짜로 먼저 반영 + 같은 제목의
        // Apple 미러를 옛 위치에서 선제 제거. EventKit이 Google 싱크하기 전까지
        // macOS Calendar가 옛 위치 이벤트를 재표시하는 '깜빡임' 방지.
        let appleCandidates = (appleCalendarEnabled && appleCalendarAccessGranted)
            ? fetchLocalCalendarEvents(for: currentMonth)
            : calendarEvents.filter { $0.source == .apple }
        var suppressKeysForImmediateRemoval = Set<SuppressKey>()
        if let idx = calendarEvents.firstIndex(where: { $0.id == eventID }) {
            let oldStart = calendarEvents[idx].startDate
            let oldEnd = calendarEvents[idx].endDate
            let oldTitle = calendarEvents[idx].title
            let oldIsAllDay = calendarEvents[idx].isAllDay
            suppressKeysForImmediateRemoval.formUnion(suppressAppleMirrorCandidates(
                eventID: eventID,
                title: oldTitle,
                startDate: oldStart,
                endDate: oldEnd,
                isAllDay: oldIsAllDay,
                appleCandidates: appleCandidates
            ))
            calendarEvents[idx].title = title
            calendarEvents[idx].startDate = startDate
            calendarEvents[idx].endDate = endDate
            calendarEvents[idx].isAllDay = isAllDay

            // 옛 시작시각 + 같은 제목의 Apple 미러 즉시 제거
            calendarEvents.removeAll { ev in
                ev.source == .apple
                && suppressKeysForImmediateRemoval.contains(Self.appleMirrorSuppressKey(for: ev))
            }
        }
        // 60초간 Apple 미러 suppress — macOS Calendar sync 지연 구간 커버
        suppressAppleMirrorCandidates(
            eventID: eventID,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            appleCandidates: appleCandidates
        )
        markRecentlyMutatedGoogle(eventID)
        Task {
            do {
                PlanitLoggers.sync.info(
                    "Updating Google event eventID=\(eventID, privacy: .public) calendarID=\(calendarID, privacy: .public) start=\(Self.logDate(startDate), privacy: .public) end=\(Self.logDate(endDate), privacy: .public) allDay=\(isAllDay, privacy: .public)"
                )
                if try await googleService.updateEvent(eventID: eventID, calendarID: calendarID, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay) == false {
                    recordCRUDFailure(operation: .update, source: .google, eventID: eventID)
                }
                fetchEventsFromGoogle(for: currentMonth, force: true)
            } catch {
                guard Self.shouldQueueGoogleMutation(after: error) else {
                    recordCRUDFailure(operation: .update, source: .google, eventID: eventID, error: error)
                    return
                }
                PlanitLoggers.sync.info("Offline Google update queued eventID=\(eventID, privacy: .public)")
                queuePendingEdit(PendingCalendarEdit(
                    action: "update", title: title, startDate: startDate,
                    endDate: endDate, isAllDay: isAllDay, eventId: eventID, calendarID: calendarID))
                // Optimistic local update
                if let idx = calendarEvents.firstIndex(where: { $0.id == eventID }) {
                    calendarEvents[idx].title = title
                    calendarEvents[idx].startDate = startDate
                    calendarEvents[idx].endDate = endDate
                    calendarEvents[idx].isAllDay = isAllDay
                    cacheEvents(calendarEvents)
                }
            }
        }
    }

    func deleteGoogleEvent(eventID: String, calendarID: String = "google:primary") {
        // Apple Calendar 미러 재출현 방지: 실제 Apple calendarID로 suppress
        if let target = calendarEvents.first(where: { $0.id == eventID }) {
            let appleCandidates = calendarEvents.filter { $0.source == .apple }
            suppressAppleMirrorCandidates(
                eventID: eventID,
                title: target.title,
                startDate: target.startDate,
                endDate: target.endDate,
                isAllDay: target.isAllDay,
                appleCandidates: appleCandidates
            )
            // 후보 없을 경우 title+startDate 기반 fallback suppress (TTL 4분)
            if appleCandidates.filter({
                SuppressKey.normalizedTitle($0.title) == SuppressKey.normalizedTitle(target.title) &&
                Self.startMinute($0.startDate) == Self.startMinute(target.startDate)
            }).isEmpty {
                suppressAppleMirror(title: target.title, startDate: target.startDate,
                                    calendarID: calendarID,
                                    for: CalendarViewModel.appleMirrorSuppressTTL * 4)
            }
        }
        // Optimistic removal: 연속 삭제 시 fetch 스킵으로 이벤트가 되살아나는 레이스 방지
        calendarEvents.removeAll { $0.id == eventID }
        markRecentlyDeletedGoogle(eventID)
        cacheEvents(calendarEvents)
        Task {
            do {
                if try await googleService.deleteEvent(eventID: eventID, calendarID: calendarID) == false {
                    recordCRUDFailure(operation: .delete, source: .google, eventID: eventID)
                }
                completedEventIDs.remove(eventID)
                goalService?.removeCompletion(eventId: eventID)
                saveCompletedEvents()
                fetchEventsFromGoogle(for: currentMonth, force: true)
            } catch {
                guard Self.shouldQueueGoogleMutation(after: error) else {
                    recordCRUDFailure(operation: .delete, source: .google, eventID: eventID, error: error)
                    return
                }
                PlanitLoggers.sync.info("Offline Google delete queued eventID=\(eventID, privacy: .public)")
                queuePendingEdit(PendingCalendarEdit(
                    action: "delete", eventId: eventID, calendarID: calendarID))
                // 이미 위에서 optimistic removal 완료 — completedEvents만 처리
                completedEventIDs.remove(eventID)
                goalService?.removeCompletion(eventId: eventID)
                saveCompletedEvents()
            }
        }
    }

    nonisolated static func shouldQueueGoogleMutation(after error: Error) -> Bool {
        if let calendarError = error as? GoogleCalendarError {
            switch calendarError {
            case .httpStatus(let code):
                return code == 408 || code == 429 || (500...599).contains(code)
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }

        return false
    }

    // MARK: - EventKit (fallback when not using Google API)

    private func removeCalendarObserver() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }

    private func observeCalendarChanges() {
        // 기존 observer 제거 후 재등록 — 중복 리스너 누수 방지
        removeCalendarObserver()
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Google 인증 상태일 때 EventKit만 불러오면 Google 이벤트가 유실되므로
                // refreshEvents()를 통해 적절한 소스에서 로드
                if self.authManager.isAuthenticated {
                    self.refreshEvents()
                } else {
                    self.fetchEventsFromEventKit(for: self.currentMonth)
                }
            }
        }
    }

    func requestCalendarAccess() {
        if #available(iOS 17.0, macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                guard granted, error == nil else { return }
                Task { @MainActor in
                    self?.fetchEventsFromEventKit(for: self?.currentMonth ?? Date())
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                guard granted, error == nil else { return }
                Task { @MainActor in
                    self?.fetchEventsFromEventKit(for: self?.currentMonth ?? Date())
                }
            }
        }
    }

    func fetchEventsFromEventKit(for month: Date) {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return }
        let predicate = eventStore.predicateForEvents(
            withStart: monthInterval.start,
            end: monthInterval.end,
            calendars: nil
        )
        let ekEvents = eventStore.events(matching: predicate)
        let localEvents = ekEvents.map { event in
            let cgColor = event.calendar.cgColor ?? CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
            return CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                color: Color(cgColor: cgColor),
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                calendarID: "apple:\(event.calendar.calendarIdentifier)",
                source: .local
            )
        }
        let todoEventIds = Set(todos.compactMap { $0.googleEventId })
        let deduped = Self.deduplicatedCalendarEvents(localEvents, todoGoogleEventIDs: todoEventIds)
        PlanitLoggers.sync.info(
            "Fetched EventKit events month=\(Self.logDate(month), privacy: .public) raw=\(localEvents.count, privacy: .public) deduped=\(deduped.count, privacy: .public)"
        )
        calendarEvents = deduped
        applyEventCategoryMappings()
    }

    // EventKit write methods (fallback)
    func addEventToCalendar(title: String, startDate: Date, endDate: Date, isAllDay: Bool) -> Bool {
        if authManager.isAuthenticated {
            addEventToGoogleCalendar(title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
            return true
        }
        guard let cal = writableCalendar else {
            recordCRUDFailure(operation: .create, source: .local)
            return false
        }
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = title
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.isAllDay = isAllDay
        ekEvent.calendar = cal
        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            fetchEventsFromEventKit(for: currentMonth)
            return true
        } catch {
            recordCRUDFailure(operation: .create, source: .local, error: error)
            return false
        }
    }

    func updateCalendarEvent(eventID: String, calendarID: String = "google:primary", title: String, startDate: Date, endDate: Date, isAllDay: Bool) -> Bool {
        let source = Self.inferredEventSource(
            eventID: eventID,
            calendarID: calendarID,
            events: calendarEvents,
            googleAuthenticated: authManager.isAuthenticated
        )
        PlanitLoggers.sync.info(
            "Routing calendar update eventID=\(eventID, privacy: .public) calendarID=\(calendarID, privacy: .public) source=\(source.rawValue, privacy: .public)"
        )
        switch source {
        case .google:
            guard authManager.isAuthenticated else { return false }
            updateGoogleEvent(eventID: eventID, calendarID: calendarID, title: title, startDate: startDate, endDate: endDate, isAllDay: isAllDay)
            return true
        case .apple:
            guard let ekEvent = eventKitEvent(withIdentifier: eventID) else {
                recordCRUDFailure(operation: .update, source: .apple, eventID: eventID)
                return false
            }
            ekEvent.title = title
            ekEvent.startDate = startDate
            ekEvent.endDate = endDate
            ekEvent.isAllDay = isAllDay
            do {
                try eventStore.save(ekEvent, span: .thisEvent)
                refreshAfterEventKitMutation()
                return true
            } catch {
                recordCRUDFailure(operation: .update, source: .apple, eventID: eventID, error: error)
                return false
            }
        case .local:
            guard let ekEvent = eventKitEvent(withIdentifier: eventID) else {
                recordCRUDFailure(operation: .update, source: .local, eventID: eventID)
                return false
            }
            ekEvent.title = title
            ekEvent.startDate = startDate
            ekEvent.endDate = endDate
            ekEvent.isAllDay = isAllDay
            do {
                try eventStore.save(ekEvent, span: .thisEvent)
                refreshAfterEventKitMutation()
                return true
            } catch {
                recordCRUDFailure(operation: .update, source: .local, eventID: eventID, error: error)
                return false
            }
        }
    }

    func deleteCalendarEvent(eventID: String, calendarID: String = "google:primary") -> Bool {
        let source = Self.inferredEventSource(
            eventID: eventID,
            calendarID: calendarID,
            events: calendarEvents,
            googleAuthenticated: authManager.isAuthenticated
        )
        switch source {
        case .google:
            guard authManager.isAuthenticated else { return false }
            deleteGoogleEvent(eventID: eventID, calendarID: calendarID)
            return true
        case .apple:
            guard let ekEvent = eventKitEvent(withIdentifier: eventID) else {
                recordCRUDFailure(operation: .delete, source: .apple, eventID: eventID)
                return false
            }
            do {
                try eventStore.remove(ekEvent, span: .thisEvent)
                completedEventIDs.remove(eventID)
                completedEventIDs.remove(Self.eventKitLookupIdentifier(for: eventID))
                goalService?.removeCompletion(eventId: eventID)
                goalService?.removeCompletion(eventId: Self.eventKitLookupIdentifier(for: eventID))
                saveCompletedEvents()
                calendarEvents.removeAll { $0.id == eventID || $0.id == Self.eventKitLookupIdentifier(for: eventID) }
                refreshAfterEventKitMutation()
                return true
            } catch {
                recordCRUDFailure(operation: .delete, source: .apple, eventID: eventID, error: error)
                return false
            }
        case .local:
            guard let ekEvent = eventKitEvent(withIdentifier: eventID) else {
                recordCRUDFailure(operation: .delete, source: .local, eventID: eventID)
                return false
            }
            do {
                try eventStore.remove(ekEvent, span: .thisEvent)
                completedEventIDs.remove(eventID)
                completedEventIDs.remove(Self.eventKitLookupIdentifier(for: eventID))
                goalService?.removeCompletion(eventId: eventID)
                goalService?.removeCompletion(eventId: Self.eventKitLookupIdentifier(for: eventID))
                saveCompletedEvents()
                calendarEvents.removeAll { $0.id == eventID || $0.id == Self.eventKitLookupIdentifier(for: eventID) }
                refreshAfterEventKitMutation()
                return true
            } catch {
                recordCRUDFailure(operation: .delete, source: .local, eventID: eventID, error: error)
                return false
            }
        }
    }

    private func eventKitEvent(withIdentifier eventID: String) -> EKEvent? {
        eventStore.event(withIdentifier: eventID)
            ?? eventStore.event(withIdentifier: Self.eventKitLookupIdentifier(for: eventID))
    }

    private func refreshAfterEventKitMutation() {
        let googleAuthenticated = authManager.isAuthenticated
        let monthForLog = currentMonth
        PlanitLoggers.sync.info(
            "Refreshing after EventKit mutation googleAuthenticated=\(googleAuthenticated, privacy: .public) currentMonth=\(Self.logDate(monthForLog), privacy: .public)"
        )
        if authManager.isAuthenticated {
            mergeAppleCalendarEvents(for: currentMonth)
            cacheEvents(calendarEvents)
        } else {
            fetchEventsFromEventKit(for: currentMonth)
        }
    }

    private var writableCalendar: EKCalendar? {
        if let google = eventStore.calendars(for: .event).first(where: {
            $0.source.sourceType == .calDAV && $0.allowsContentModifications
        }) { return google }
        return eventStore.defaultCalendarForNewEvents
    }

    // MARK: - Category Helpers

    func category(for id: UUID) -> TodoCategory {
        categories.first(where: { $0.id == id }) ?? categories.first ?? TodoCategory(name: String(localized: "viewmodel.default.category"), colorHex: "#6699FF")
    }

    var defaultCategoryID: UUID {
        categories.first?.id ?? UUID()
    }

    // MARK: - Calendar Grid

    func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthRange = calendar.range(of: .day, in: .month, for: currentMonth) else {
            return Array(repeating: nil, count: 42)
        }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingNils = firstWeekday - 1
        let totalDays = monthRange.count

        var slots: [Date?] = Array(repeating: nil, count: leadingNils)
        for day in 0..<totalDays {
            if let date = calendar.date(byAdding: .day, value: day, to: firstDay) {
                slots.append(date)
            }
        }
        while slots.count < 42 { slots.append(nil) }
        return slots
    }

    struct MonthGridDay: Identifiable {
        let id: String
        let date: Date?
        let isSelected: Bool
        let isToday: Bool
        let isSunday: Bool
        let isSaturday: Bool
        let isCurrentMonth: Bool
        let events: [CalendarEvent]
        let todos: [TodoItem]
    }

    func monthGridRows() -> [[MonthGridDay]] {
        let todoEventIds = Set(todos.compactMap { $0.googleEventId })
        let gridDays = daysInMonth().enumerated().map { offset, date -> MonthGridDay in
            guard let date else {
                return MonthGridDay(
                    id: "empty-\(offset)",
                    date: nil,
                    isSelected: false,
                    isToday: false,
                    isSunday: false,
                    isSaturday: false,
                    isCurrentMonth: false,
                    events: [],
                    todos: []
                )
            }
            return MonthGridDay(
                id: dateKey(date),
                date: date,
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                isToday: calendar.isDateInToday(date),
                isSunday: calendar.component(.weekday, from: date) == 1,
                isSaturday: calendar.component(.weekday, from: date) == 7,
                isCurrentMonth: calendar.isDate(date, equalTo: currentMonth, toGranularity: .month),
                events: eventsForDate(date, todoEventIds: todoEventIds),
                todos: todosForDate(date)
            )
        }
        // Build rows once per render instead of recomputing day/event/todo filters in every cell.
        return stride(from: 0, to: gridDays.count, by: 7).map {
            Array(gridDays[$0..<min($0 + 7, gridDays.count)])
        }
    }

    func monthTitle() -> String {
        Self.monthTitleFormatter.string(from: currentMonth)
    }
    func yearTitle() -> String { "\(calendar.component(.year, from: currentMonth))" }

    func previousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = prev
            // 월 이동은 TTL 무시 — 이전에 fetch한 달로 돌아올 때도 반드시 최신 데이터 로드
            if authManager.isAuthenticated {
                fetchEventsFromGoogle(for: prev, force: true)
            } else {
                fetchEventsFromEventKit(for: prev)
            }
        }
    }

    func nextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = next
            if authManager.isAuthenticated {
                fetchEventsFromGoogle(for: next, force: true)
            } else {
                fetchEventsFromEventKit(for: next)
            }
        }
    }

    func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
    func isSunday(_ date: Date) -> Bool { calendar.component(.weekday, from: date) == 1 }
    func isSaturday(_ date: Date) -> Bool { calendar.component(.weekday, from: date) == 7 }
    func isCurrentMonth(_ date: Date) -> Bool { calendar.isDate(date, equalTo: currentMonth, toGranularity: .month) }

    func daysSinceToday(_ date: Date) -> Int {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    func formattedDate(_ date: Date) -> String {
        Self.formattedDateFormatter.string(from: date)
    }

    func overdueLocalTodoCount(now: Date = Date()) -> Int {
        let today = calendar.startOfDay(for: now)
        return todos.filter {
            !$0.isCompleted && $0.source == .local && $0.date < today
        }.count
    }

    // MARK: - Filtering

    func eventsForDate(_ date: Date) -> [CalendarEvent] {
        // 할 일로 등록된 Google 이벤트는 ID로 제외 (오탐 없는 정확한 방식)
        let todoEventIds = Set(todos.compactMap { $0.googleEventId })
        return calendarEvents.filter { event in
            guard !todoEventIds.contains(event.id) else { return false }
            return eventOccurs(event, on: date)
        }
    }

    private func eventsForDate(_ date: Date, todoEventIds: Set<String>) -> [CalendarEvent] {
        return calendarEvents.filter { event in
            guard !todoEventIds.contains(event.id) else { return false }
            return eventOccurs(event, on: date)
        }
    }

    private func eventOccurs(_ event: CalendarEvent, on date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        if event.isAllDay {
            let eventStart = calendar.startOfDay(for: event.startDate)
            let eventEnd = calendar.startOfDay(for: event.endDate)
            return dayStart >= eventStart && dayStart < eventEnd
        } else {
            return event.startDate < dayEnd && event.endDate > dayStart
        }
    }

    func todosForDate(_ date: Date) -> [TodoItem] {
        let localTodos = todos.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let reminders = appleRemindersForDate(date)
        // 수동 정렬: todoOrder에 있는 순서 우선, 없는 건 date 순으로 뒤에
        let order = todoOrder[dateKey(date)] ?? []
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let ordered = localTodos.sorted { a, b in
            let ai = orderIndex[a.id] ?? Int.max
            let bi = orderIndex[b.id] ?? Int.max
            if ai != bi { return ai < bi }
            return a.date < b.date
        }
        return ordered + reminders
    }

    // MARK: - Manual Ordering (per-date, 통합 events + todos)

    /// 이벤트와 할일을 함께 재배치할 수 있는 통합 아이템 타입.
    enum DayItem: Identifiable {
        case event(CalendarEvent)
        case todo(TodoItem)
        var id: String {
            switch self {
            case .event(let e): return "event:\(e.id)"
            case .todo(let t):  return "todo:\(t.id.uuidString)"
            }
        }
        var sortDate: Date {
            switch self {
            case .event(let e): return e.startDate
            case .todo(let t):  return t.date
            }
        }
    }

    /// date("yyyy-MM-dd") → [itemID] 순서 (이벤트와 할일이 섞인 통합 순서)
    @Published private var dayItemOrder: [String: [String]] = [:]
    private let dayItemOrderKey = "planit.dayItemOrder.v1"

    /// (하위 호환) todosForDate가 참조하던 per-type 순서 — 이제 dayItemOrder에서 파생
    @Published private var todoOrder: [String: [UUID]] = [:]
    private let todoOrderKey = "planit.todoOrder.v1"

    /// 특정 날짜의 통합 아이템 목록. dayItemOrder 있으면 그 순서,
    /// 없으면 이벤트 먼저(시간순) + 할일(date순) 기본 정렬.
    /// Apple Reminder는 외부 관리라 항상 맨 뒤에 분리 배치.
    func itemsForDate(_ date: Date) -> [DayItem] {
        let events = eventsForDate(date)
        let localTodos = todos
            .filter { calendar.isDate($0.date, inSameDayAs: date) && $0.source == .local }
        let reminders = appleRemindersForDate(date)
        return Self.orderedDayItems(
            events: events,
            localTodos: localTodos,
            reminders: reminders,
            order: dayItemOrder[dateKey(date)] ?? []
        )
    }

    nonisolated static func orderedDayItems(
        events: [CalendarEvent],
        localTodos: [TodoItem],
        reminders: [TodoItem],
        order: [String]
    ) -> [DayItem] {
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let unified = events.map { DayItem.event($0) } + localTodos.map { DayItem.todo($0) }
        // Pre-index manual order so drag renders do not scan the order array for every comparison.
        let sorted = unified.sorted { a, b in
            let ai = orderIndex[a.id] ?? Int.max
            let bi = orderIndex[b.id] ?? Int.max
            if ai != bi { return ai < bi }
            return a.sortDate < b.sortDate
        }
        return sorted + reminders.map { DayItem.todo($0) }
    }

    /// 드래그 완료 시 통합 순서를 통째로 저장. Apple Reminder는 입력에서 제외됨.
    func setDayItemOrder(_ ids: [String], on date: Date) {
        guard !ids.isEmpty else { return }
        dayItemOrder[dateKey(date)] = ids
        saveDayItemOrder()
    }

    func loadDayItemOrder() {
        guard let data = UserDefaults.standard.data(forKey: dayItemOrderKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }
        dayItemOrder = decoded
    }

    private func saveDayItemOrder() {
        if let data = try? JSONEncoder().encode(dayItemOrder) {
            UserDefaults.standard.set(data, forKey: dayItemOrderKey)
        }
    }

    private func dateKey(_ date: Date) -> String {
        Self.dateKeyFormatter.string(from: date)
    }

    private func monthKey(_ date: Date) -> String {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return dateKey(start)
    }

    /// 특정 날짜의 local todo 순서를 통째로 설정. Apple Reminder는 영향 없음.
    func setLocalTodoOrder(_ ids: [UUID], on date: Date) {
        let localIDs = Set(todos.filter { calendar.isDate($0.date, inSameDayAs: date) && $0.source == .local }.map(\.id))
        let filtered = ids.filter(localIDs.contains)
        guard !filtered.isEmpty else { return }
        todoOrder[dateKey(date)] = filtered
        saveTodoOrder()
    }

    /// 드래그된 todo를 타겟 todo 위치로 이동. 같은 날짜 안에서만 동작.
    /// Apple Reminder(외부 관리)는 재배치 대상에서 제외.
    func reorderLocalTodo(draggedID: UUID, droppedOnTargetID targetID: UUID, on date: Date) {
        guard draggedID != targetID else { return }
        let localIDs = todos.filter { calendar.isDate($0.date, inSameDayAs: date) }.map(\.id)
        guard localIDs.contains(draggedID), localIDs.contains(targetID) else { return }

        let key = dateKey(date)
        var order = todoOrder[key] ?? []
        for id in localIDs where !order.contains(id) { order.append(id) }
        order = order.filter(localIDs.contains)

        guard let from = order.firstIndex(of: draggedID),
              let to   = order.firstIndex(of: targetID) else { return }
        let item = order.remove(at: from)
        let insertAt = from < to ? to - 1 : to
        order.insert(item, at: insertAt)
        todoOrder[key] = order
        saveTodoOrder()
    }

    func loadTodoOrder() {
        guard let data = UserDefaults.standard.data(forKey: todoOrderKey),
              let decoded = try? JSONDecoder().decode([String: [UUID]].self, from: data)
        else { return }
        todoOrder = decoded
    }

    private func saveTodoOrder() {
        if let data = try? JSONEncoder().encode(todoOrder) {
            UserDefaults.standard.set(data, forKey: todoOrderKey)
        }
    }

    // MARK: - Todo Bulk Sync

    /// Sync all existing todos that don't have a googleEventId to Google Calendar
    func syncAllTodosToGoogle() async -> Int {
        guard authManager.isAuthenticated else { return 0 }
        var synced = 0
        for i in todos.indices {
            guard todos[i].googleEventId == nil else { continue }
            let todo = todos[i]
            let startOfDay = calendar.startOfDay(for: todo.date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let prefix = todo.isCompleted ? "✅ " : ""
            do {
                if let event = try await googleService.createEvent(
                    title: "\(prefix)\(todo.title)", startDate: startOfDay,
                    endDate: endOfDay, isAllDay: true) {
                    todos[i].googleEventId = event.id
                    synced += 1
                }
            } catch {
                recordCRUDFailure(operation: .create, source: .todo, error: error, userVisible: false)
            }
        }
        if synced > 0 {
            saveTodos()
            refreshEvents()
        }
        return synced
    }

    // MARK: - Todo CRUD

    func addTodo(title: String, categoryID: UUID? = nil, date: Date? = nil, isRepeating: Bool = false) {
        let todo = TodoItem(
            title: title,
            categoryID: categoryID ?? defaultCategoryID,
            date: date ?? selectedDate,
            isRepeating: isRepeating
        )
        todos.append(todo)
        saveTodos()

        // Sync to Google Calendar
        if authManager.isAuthenticated {
            Task {
                let startOfDay = Calendar.current.startOfDay(for: todo.date)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                do {
                    let event = try await googleService.createEvent(title: title, startDate: startOfDay, endDate: endOfDay, isAllDay: true)
                    if let event, let idx = self.todos.firstIndex(where: { $0.id == todo.id }) {
                        self.todos[idx].googleEventId = event.id
                        self.saveTodos()
                    } else {
                        recordCRUDFailure(operation: .create, source: .todo)
                    }
                } catch {
                    recordCRUDFailure(operation: .create, source: .todo, error: error)
                }
                self.refreshEvents()
            }
        }
    }

    func toggleTodo(id: UUID) {
        // Apple Reminder인 경우 EventKit으로 토글
        if let reminderItem = appleReminders.first(where: { $0.id == id }),
           let identifier = reminderItem.appleReminderIdentifier {
            toggleAppleReminder(identifier: identifier)
            return
        }

        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        saveTodos()

        // 달성률 반영 — 항상 UUID 기반 고정 키 사용 (googleEventId는 나중에 할당될 수 있어 키가 불안정)
        let completionKey = "todo:\(todos[index].id.uuidString)"
        if todos[index].isCompleted {
            goalService?.markCompletion(eventId: completionKey, eventTitle: todos[index].title, goalId: nil, status: .done, plannedMinutes: 30)
        } else {
            goalService?.removeCompletion(eventId: completionKey)
        }

        if authManager.isAuthenticated, let eventId = todos[index].googleEventId {
            let todo = todos[index]
            let prefix = todo.isCompleted ? "✅ " : ""
            let cleanTitle = todo.title.replacingOccurrences(of: "✅ ", with: "")
            Task {
                let startOfDay = Calendar.current.startOfDay(for: todo.date)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                do {
                    if try await googleService.updateEvent(eventID: eventId, title: "\(prefix)\(cleanTitle)", startDate: startOfDay, endDate: endOfDay, isAllDay: true) == false {
                        recordCRUDFailure(operation: .update, source: .todo, eventID: eventId)
                    }
                } catch {
                    recordCRUDFailure(operation: .update, source: .todo, eventID: eventId, error: error)
                }
                self.refreshEvents()
            }
        }
    }

    func deleteTodo(id: UUID) {
        // Apple Reminder인 경우 EventKit으로 삭제
        if let reminderItem = appleReminders.first(where: { $0.id == id }),
           let identifier = reminderItem.appleReminderIdentifier {
            deleteAppleReminder(identifier: identifier)
            return
        }

        if let todo = todos.first(where: { $0.id == id }) {
            // 완료 기록 정리
            goalService?.removeCompletion(eventId: "todo:\(id.uuidString)")
            if let eventId = todo.googleEventId, authManager.isAuthenticated {
                Task {
                    do {
                        if try await googleService.deleteEvent(eventID: eventId) == false {
                            recordCRUDFailure(operation: .delete, source: .todo, eventID: eventId)
                        }
                    } catch {
                        recordCRUDFailure(operation: .delete, source: .todo, eventID: eventId, error: error)
                    }
                    self.refreshEvents()
                }
            }
        }
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func updateTodo(id: UUID, title: String, categoryID: UUID, date: Date? = nil) {
        // Apple Reminder인 경우 EventKit으로 업데이트
        if let reminderItem = appleReminders.first(where: { $0.id == id }),
           let identifier = reminderItem.appleReminderIdentifier {
            updateAppleReminder(identifier: identifier, title: title, date: date)
            return
        }

        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].title = title
        todos[index].categoryID = categoryID
        if let newDate = date { todos[index].date = newDate }
        saveTodos()

        if authManager.isAuthenticated, let eventId = todos[index].googleEventId {
            let todo = todos[index]
            let prefix = todo.isCompleted ? "✅ " : ""
            Task {
                let startOfDay = Calendar.current.startOfDay(for: todo.date)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
                do {
                    if try await googleService.updateEvent(eventID: eventId, title: "\(prefix)\(title)", startDate: startOfDay, endDate: endOfDay, isAllDay: true) == false {
                        recordCRUDFailure(operation: .update, source: .todo, eventID: eventId)
                    }
                } catch {
                    recordCRUDFailure(operation: .update, source: .todo, eventID: eventId, error: error)
                }
                self.refreshEvents()
            }
        }
    }

    /// Apple Reminder를 EventKit에서 직접 삭제
    func deleteAppleReminder(identifier: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            recordCRUDFailure(operation: .delete, source: .apple, eventID: identifier)
            return
        }
        // 완료 기록 정리 (id가 appleReminderIdentifier로도 추적되는 경우)
        goalService?.removeCompletion(eventId: identifier)
        do {
            try eventStore.remove(reminder, commit: true)
            appleReminders.removeAll { $0.appleReminderIdentifier == identifier }
        } catch {
            recordCRUDFailure(operation: .delete, source: .apple, eventID: identifier, error: error)
        }
    }

    /// Apple Reminder의 제목/날짜를 EventKit에서 업데이트
    func updateAppleReminder(identifier: String, title: String, date: Date? = nil) {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            recordCRUDFailure(operation: .update, source: .apple, eventID: identifier)
            return
        }
        reminder.title = title
        if let newDate = date {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: newDate)
            reminder.dueDateComponents = components
        }
        do {
            try eventStore.save(reminder, commit: true)
            if let idx = appleReminders.firstIndex(where: { $0.appleReminderIdentifier == identifier }) {
                appleReminders[idx].title = title
                if let newDate = date { appleReminders[idx].date = newDate }
            }
        } catch {
            recordCRUDFailure(operation: .update, source: .apple, eventID: identifier, error: error)
        }
    }

    // MARK: - Drag & Drop Move

    func moveTodo(id: UUID, toDate: Date) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let oldDate = todos[idx].date
        todos[idx].date = Calendar.current.startOfDay(for: toDate)
        let newDate = todos[idx].date
        let hasGoogleMirror = todos[idx].googleEventId != nil
        PlanitLoggers.sync.info(
            "Moving todo id=\(id.uuidString, privacy: .public) oldDate=\(Self.logDate(oldDate), privacy: .public) newDate=\(Self.logDate(newDate), privacy: .public) hasGoogleMirror=\(hasGoogleMirror, privacy: .public)"
        )
        saveTodos()

        if authManager.isAuthenticated, let eventId = todos[idx].googleEventId {
            let todo = todos[idx]
            let prefix = todo.isCompleted ? "✅ " : ""
            let todoPrefix = "✅ "
            let clean = todo.title.hasPrefix(todoPrefix) ? String(todo.title.dropFirst(todoPrefix.count)) : todo.title
            Task {
                let start = Calendar.current.startOfDay(for: toDate)
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                do {
                    if try await googleService.updateEvent(eventID: eventId, title: "\(prefix)\(clean)", startDate: start, endDate: end, isAllDay: true) == false {
                        recordCRUDFailure(operation: .update, source: .todo, eventID: eventId)
                    }
                } catch {
                    recordCRUDFailure(operation: .update, source: .todo, eventID: eventId, error: error)
                }
                self.refreshEvents()
            }
        }
    }

    /// Calen 자동 재배치 전용 — rescheduledTodoIDs에 기록
    func moveTodoBySystem(id: UUID, toDate: Date) {
        moveTodo(id: id, toDate: toDate)
        rescheduledTodoIDs.insert(id)
    }

    /// 지금 즉시 재배치 실행 (자정 안 기다리고 수동 트리거)
    func rescheduleNow() {
        // rolloverKey 리셋 → performIfNeeded가 다시 실행되도록
        UserDefaults.standard.removeObject(forKey: "planit.lastRolloverDate")
        MidnightRolloverService.shared.performIfNeeded(viewModel: self)
    }

    /// 같은 날 시간대 이동 (예: 10:00 → 14:00). Planning apply 경로에서 사용.
    /// 기존 duration을 유지하며 startDate를 toStartDate로 이동.
    func moveCalendarEvent(id: String, toStartDate: Date) {
        guard let event = calendarEvents.first(where: { $0.id == id }) else { return }
        let duration = event.endDate.timeIntervalSince(event.startDate)
        var movedEvent = event
        movedEvent.startDate = toStartDate
        movedEvent.endDate = toStartDate.addingTimeInterval(duration)
        applyMove(event: event, movedEvent: movedEvent, id: id)
    }

    func moveCalendarEvent(id: String, toDate: Date) {
        guard let event = calendarEvents.first(where: { $0.id == id }) else { return }
        let cal = Calendar.current
        let srcDay = cal.startOfDay(for: event.startDate)
        let dstDay = cal.startOfDay(for: toDate)
        let delta = dstDay.timeIntervalSince(srcDay)
        var movedEvent = event
        movedEvent.startDate = event.startDate.addingTimeInterval(delta)
        movedEvent.endDate = event.endDate.addingTimeInterval(delta)
        applyMove(event: event, movedEvent: movedEvent, id: id)
    }

    /// 공통 이동 로직 — moveCalendarEvent(id:toDate:) 와 moveCalendarEvent(id:toStartDate:) 모두 사용.
    private func applyMove(event: CalendarEvent, movedEvent: CalendarEvent, id: String) {
        // Apple Calendar eventual consistency: replaceCalendarEventLocally 호출 전에
        // 옛 위치의 Apple 미러를 억제해야 함.
        if event.source == .google {
            let appleCandidates = (appleCalendarEnabled && appleCalendarAccessGranted)
                ? fetchLocalCalendarEvents(for: currentMonth)
                : calendarEvents.filter { $0.source == .apple }
            let suppressKeys = suppressAppleMirrorCandidates(
                eventID: id,
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                appleCandidates: appleCandidates
            )
            calendarEvents.removeAll { ev in
                ev.source == .apple
                    && suppressKeys.contains(Self.appleMirrorSuppressKey(for: ev))
            }
        }
        replaceCalendarEventLocally(movedEvent)
        if event.source == .google {
            markRecentlyMutatedGoogle(id)
        }

        PlanitLoggers.sync.info(
            "Moving calendar event id=\(id, privacy: .public) source=\(event.source.rawValue, privacy: .public) oldStart=\(Self.logDate(event.startDate), privacy: .public) oldEnd=\(Self.logDate(event.endDate), privacy: .public) newStart=\(Self.logDate(movedEvent.startDate), privacy: .public) newEnd=\(Self.logDate(movedEvent.endDate), privacy: .public) allDay=\(event.isAllDay, privacy: .public)"
        )

        switch event.source {
        case .google:
            updateGoogleEvent(eventID: id, calendarID: event.calendarID, title: event.title, startDate: movedEvent.startDate, endDate: movedEvent.endDate, isAllDay: event.isAllDay)
        case .apple, .local:
            _ = updateCalendarEvent(eventID: id, calendarID: event.calendarID, title: event.title, startDate: movedEvent.startDate, endDate: movedEvent.endDate, isAllDay: event.isAllDay)
        }
    }

    private func replaceCalendarEventLocally(_ movedEvent: CalendarEvent) {
        let before = calendarEvents.count
        calendarEvents.removeAll { $0.id == movedEvent.id }
        calendarEvents.append(movedEvent)
        let todoEventIds = Set(todos.compactMap { $0.googleEventId })
        calendarEvents = Self.deduplicatedCalendarEvents(calendarEvents, todoGoogleEventIDs: todoEventIds)
        applyEventCategoryMappings()
        cacheEvents(calendarEvents)
        PlanitLoggers.sync.info(
            "Replaced local moved event id=\(movedEvent.id, privacy: .public) before=\(before, privacy: .public) after=\(self.calendarEvents.count, privacy: .public)"
        )
    }

    private nonisolated static func logDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // MARK: - Category CRUD

    func addCategory(name: String, colorHex: String) {
        let cat = TodoCategory(name: name, colorHex: colorHex)
        categories.append(cat)
        saveCategories()
    }

    func deleteCategory(id: UUID) {
        if let fallback = categories.first(where: { $0.id != id }) {
            for i in todos.indices where todos[i].categoryID == id {
                todos[i].categoryID = fallback.id
            }
            saveTodos()
        }
        categories.removeAll { $0.id == id }
        saveCategories()
        // 삭제된 카테고리를 참조하는 캘린더 매핑 제거
        eventCategoryMappings = eventCategoryMappings.filter { $0.value.categoryID != id }
        saveEventCategoryMappings()
        applyEventCategoryMappings()
    }

    func updateCategory(id: UUID, name: String, colorHex: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
        categories[index].colorHex = colorHex
        saveCategories()
    }

    // MARK: - Event Category Mappings (이벤트별 독립 매핑)

    /// 이벤트의 카테고리를 반환 (매핑 없으면 nil)
    func categoryForEvent(_ event: CalendarEvent) -> TodoCategory? {
        guard let catID = event.categoryID else { return nil }
        return categories.first { $0.id == catID }
    }

    /// 이벤트에 카테고리 매핑 설정 (categoryID == nil이면 매핑 제거)
    /// Google 이벤트는 extendedProperties로 서버에도 저장 — 재설치 후 자동 복원.
    func setEventCategory(eventID: String, eventTitle: String, categoryID: UUID?) {
        if let catID = categoryID {
            eventCategoryMappings[eventID] = EventCategoryMapping(
                eventID: eventID,
                eventTitle: eventTitle,
                categoryID: catID
            )
        } else {
            eventCategoryMappings.removeValue(forKey: eventID)
        }
        saveEventCategoryMappings()
        applyEventCategoryMappings()

        // Google 이벤트라면 서버에도 카테고리 태그 저장 (재설치 후 복원 가능하게)
        if let ev = calendarEvents.first(where: { $0.id == eventID }),
           ev.source == .google {
            Task {
                _ = try? await googleService.patchEventCategory(
                    eventID: eventID,
                    calendarID: ev.calendarID,
                    categoryID: categoryID
                )
            }
        }
    }

    /// 일괄 카테고리 분류 적용 — Google PATCH는 순차 실행 (rate-limit 보호).
    /// 로컬 매핑은 optimistic하게 바로 반영 후 Google에 점진 적용.
    /// Returns: (applied, failed) 개수 튜플.
    func applyBulkCategories(_ mappings: [(eventID: String, categoryID: UUID)]) async -> (applied: Int, failed: Int) {
        var applied = 0
        var failed = 0

        // Google 이벤트별 매핑 필터
        let googleMappings = mappings.compactMap { m -> (CalendarEvent, UUID)? in
            guard let ev = calendarEvents.first(where: { $0.id == m.eventID }),
                  ev.source == .google,
                  ev.categoryID == nil,                        // 여전히 미분류인지 재검증
                  eventCategoryMappings[m.eventID] == nil else { return nil }
            return (ev, m.categoryID)
        }

        // 로컬 매핑을 일괄 적용 (optimistic)
        for (ev, catID) in googleMappings {
            eventCategoryMappings[ev.id] = EventCategoryMapping(
                eventID: ev.id,
                eventTitle: ev.title,
                categoryID: catID
            )
        }
        saveEventCategoryMappings()
        applyEventCategoryMappings()

        // Google에 순차적으로 PATCH — rate limit 보호
        for (ev, catID) in googleMappings {
            do {
                let ok = try await googleService.patchEventCategory(
                    eventID: ev.id,
                    calendarID: ev.calendarID,
                    categoryID: catID
                )
                if ok {
                    applied += 1
                } else {
                    failed += 1
                }
            } catch {
                failed += 1
                PlanitLoggers.sync.error(
                    "Bulk categorize PATCH failed id=\(ev.id, privacy: .public) error=\(Self.sanitizedErrorSummary(error), privacy: .public)"
                )
            }
            // API 부담 경감 — 연속 PATCH 사이 100ms
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return (applied, failed)
    }

    /// Google fetch 후 extendedProperties로부터 카테고리 자동 복원.
    /// 로컬에 매핑 없지만 Google 이벤트에 planit_category가 있으면 매핑 자동 생성.
    fileprivate func restoreCategoryMappingsFromGoogle() {
        let validCategoryIDs = Set(categories.map { $0.id })
        var changed = false
        for event in calendarEvents where event.source == .google {
            guard let catID = event.categoryID,
                  validCategoryIDs.contains(catID),
                  eventCategoryMappings[event.id] == nil else { continue }
            eventCategoryMappings[event.id] = EventCategoryMapping(
                eventID: event.id,
                eventTitle: event.title,
                categoryID: catID
            )
            changed = true
        }
        if changed {
            saveEventCategoryMappings()
        }
    }

    /// 현재 로드된 이벤트에 매핑 적용 (존재하지 않는 카테고리는 무시)
    func applyEventCategoryMappings() {
        let validCategoryIDs = Set(categories.map { $0.id })
        for i in calendarEvents.indices {
            let eid = calendarEvents[i].id
            if let mapping = eventCategoryMappings[eid],
               validCategoryIDs.contains(mapping.categoryID) {
                calendarEvents[i].categoryID = mapping.categoryID
            } else {
                calendarEvents[i].categoryID = nil
            }
        }
    }

    private func saveEventCategoryMappings() {
        let store = EventCategoryMappingsStore(
            version: 1,
            mappings: Array(eventCategoryMappings.values)
        )
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: eventCategoryMappingsPath, options: .atomic)
        } catch { print("[Calen] Failed to save event category mappings: \(error)") }
    }

    func loadEventCategoryMappings() {
        guard let data = try? Data(contentsOf: eventCategoryMappingsPath),
              let store = try? JSONDecoder().decode(EventCategoryMappingsStore.self, from: data) else { return }
        eventCategoryMappings = store.mappings.reduce(into: [:]) { $0[$1.eventID] = $1 }
    }

    // MARK: - Event Completion

    func isEventCompleted(_ eventID: String) -> Bool {
        completedEventIDs.contains(eventID)
    }

    func toggleEventCompleted(_ eventID: String, title: String? = nil) {
        if completedEventIDs.contains(eventID) {
            completedEventIDs.remove(eventID)
            goalService?.removeCompletion(eventId: eventID)
        } else {
            completedEventIDs.insert(eventID)
            goalService?.markCompletion(eventId: eventID, eventTitle: title, goalId: nil, status: .done, plannedMinutes: 60)
        }
        saveCompletedEvents()
    }

    // MARK: - Persistence

    func saveTodos() {
        do {
            let data = try JSONEncoder().encode(todos)
            try data.write(to: todosPath, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: todosPath.path)
        } catch { print("[Calen] Failed to save todos: \(error)") }
    }

    func loadTodos() {
        guard fileManager.fileExists(atPath: todosPath.path) else { return }
        do {
            let data = try Data(contentsOf: todosPath)
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch { print("[Calen] Failed to load todos: \(error)") }
    }

    private func saveCompletedEvents() {
        do {
            let data = try JSONEncoder().encode(Array(completedEventIDs))
            try data.write(to: completedEventsPath, options: .atomic)
        } catch { print("[Calen] Failed to save completed events: \(error)") }
    }

    private func loadCompletedEvents() {
        guard fileManager.fileExists(atPath: completedEventsPath.path) else { return }
        do {
            let data = try Data(contentsOf: completedEventsPath)
            let ids = try JSONDecoder().decode([String].self, from: data)
            completedEventIDs = Set(ids)
        } catch { print("[Calen] Failed to load completed events: \(error)") }
    }

    func saveCategories() {
        do {
            let data = try JSONEncoder().encode(categories)
            try data.write(to: categoriesPath, options: .atomic)
        } catch { print("[Calen] Failed to save categories: \(error)") }
    }

    func loadCategories() {
        if fileManager.fileExists(atPath: categoriesPath.path) {
            do {
                let data = try Data(contentsOf: categoriesPath)
                categories = try JSONDecoder().decode([TodoCategory].self, from: data)
                return
            } catch { print("[Calen] Failed to load categories: \(error)") }
        }
        categories = TodoCategory.defaults
        saveCategories()
    }

    var writableCalendars: [(name: String, identifier: String)] {
        eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { ($0.title, $0.calendarIdentifier) }
    }

    // MARK: - Event Cache (Offline Support)

    private func cacheEvents(_ events: [CalendarEvent]) {
        let cached = Self.eventsExcludingAppleCalendar(events).map { CachedCalendarEvent.from($0) }
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: eventCachePath, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: eventCachePath.path)
        } catch { print("[Calen] Failed to cache events") }
    }

    private func loadCachedEvents() {
        guard fileManager.fileExists(atPath: eventCachePath.path) else { return }
        do {
            let data = try Data(contentsOf: eventCachePath)
            let cached = try JSONDecoder().decode([CachedCalendarEvent].self, from: data)
            // Only use cache if we don't already have live data
            if calendarEvents.isEmpty {
                calendarEvents = cached.map { $0.toCalendarEvent() }
                applyEventCategoryMappings()
            }
        } catch { print("[Calen] Failed to load cached events") }
    }

    // MARK: - History Event Cache

    func loadHistory() {
        loadHistoryCache()

        guard authManager.isAuthenticated else { return }
        Task { [weak self] in
            await self?.syncHistory()
        }
    }

    private func syncHistory() async {
        guard !isOffline, authManager.isAuthenticated else { return }

        let calendars: [GoogleCalendarService.GoogleCalendarInfo]
        do {
            calendars = try await googleService.fetchCalendarList()
        } catch {
            PlanitLoggers.sync.error("Google history calendar list failed error=\(Self.sanitizedErrorSummary(error), privacy: .public)")
            return
        }
        guard !calendars.isEmpty else { return }

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        var syncStates = loadHistorySyncStates()
        var updatedByCalendar = Dictionary(grouping: historyEvents, by: Self.historyCalendarKey)

        let today = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -364, to: today),
              let to = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        for calInfo in calendars {
            if let state = syncStates[calInfo.id] {
                do {
                    let result = try await googleService.fetchDeltaForCalendar(
                        calInfo: calInfo,
                        syncToken: state.syncToken
                    )

                    if result.fullSyncRequired {
                        let full = try await fetchFullHistoryCalendar(calInfo, from: from, to: to)
                        updatedByCalendar[calInfo.id] = full.events
                        if let state = full.syncState {
                            syncStates[calInfo.id] = state
                        } else {
                            syncStates.removeValue(forKey: calInfo.id)
                        }
                    } else {
                        var existing = updatedByCalendar[calInfo.id] ?? []
                        let deletedIDs = Set(result.deletedIDs)
                        existing.removeAll { deletedIDs.contains($0.id) }

                        var eventByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
                        for event in result.upserts where event.startDate >= from && event.startDate < to {
                            eventByID[event.id] = event
                        }
                        updatedByCalendar[calInfo.id] = Array(eventByID.values)

                        if let nextSyncToken = result.nextSyncToken {
                            var updatedState = state
                            updatedState.syncToken = nextSyncToken
                            syncStates[calInfo.id] = updatedState
                        }
                    }
                } catch {
                    PlanitLoggers.sync.error("Google history delta failed calendarID=\(calInfo.id, privacy: .public) error=\(Self.sanitizedErrorSummary(error), privacy: .public)")
                }
            } else {
                do {
                    let full = try await fetchFullHistoryCalendar(calInfo, from: from, to: to)
                    updatedByCalendar[calInfo.id] = full.events
                    if let state = full.syncState {
                        syncStates[calInfo.id] = state
                    } else {
                        syncStates.removeValue(forKey: calInfo.id)
                    }
                } catch {
                    PlanitLoggers.sync.error("Google history full sync failed calendarID=\(calInfo.id, privacy: .public) error=\(Self.sanitizedErrorSummary(error), privacy: .public)")
                }
            }
        }

        historyEvents = updatedByCalendar.values
            .flatMap { $0 }
            .sorted { $0.startDate < $1.startDate }
        saveHistorySyncStates(syncStates)
        saveHistoryCache()
    }

    private func fetchFullHistoryCalendar(
        _ calInfo: GoogleCalendarService.GoogleCalendarInfo,
        from: Date,
        to: Date
    ) async throws -> (events: [CalendarEvent], syncState: HistoryCalendarSyncState?) {
        let full = try await googleService.fetchHistoryForCalendar(
            calInfo: calInfo,
            from: from,
            to: to
        )
        if let syncToken = full.syncToken {
            return (
                full.events,
                HistoryCalendarSyncState(
                    syncToken: syncToken,
                    lastFullSyncAt: Date()
                )
            )
        }
        return (full.events, nil)
    }

    private func saveHistoryCache() {
        let cached = Self.eventsExcludingAppleCalendar(historyEvents).map { CachedCalendarEvent.from($0) }
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: historyEventsCachePath, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyEventsCachePath.path)
        } catch { print("[Calen] Failed to cache history events") }
    }

    private func loadHistoryCache() {
        guard fileManager.fileExists(atPath: historyEventsCachePath.path) else { return }
        do {
            let data = try Data(contentsOf: historyEventsCachePath)
            let cached = try JSONDecoder().decode([CachedCalendarEvent].self, from: data)
            historyEvents = cached.map { $0.toCalendarEvent() }
        } catch { print("[Calen] Failed to load history event cache") }
    }

    private func loadHistorySyncStates() -> [String: HistoryCalendarSyncState] {
        guard let data = UserDefaults.standard.data(forKey: historySyncStatesKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: HistoryCalendarSyncState].self, from: data)
        } catch {
            print("[Calen] Failed to load history sync states")
            return [:]
        }
    }

    private func saveHistorySyncStates(_ states: [String: HistoryCalendarSyncState]) {
        do {
            let data = try JSONEncoder().encode(states)
            UserDefaults.standard.set(data, forKey: historySyncStatesKey)
        } catch { print("[Calen] Failed to save history sync states") }
    }

    private nonisolated static func historyCalendarKey(for event: CalendarEvent) -> String {
        if event.calendarID.hasPrefix("google:") {
            return String(event.calendarID.dropFirst("google:".count))
        }
        return event.calendarID
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = self.isOffline
                let nowOnline = path.status == .satisfied
                if wasOffline && nowOnline && !self.pendingEdits.isEmpty {
                    PlanitLoggers.sync.info("Network restored — flushing \(self.pendingEdits.count) pending edits")
                    await self.syncPendingEdits()
                    if self.authManager.isAuthenticated {
                        self.fetchEventsFromGoogle(for: self.currentMonth, force: true)
                    }
                }
            }
        }
        monitor.start(queue: pathMonitorQueue)
    }

    // MARK: - Pending Edits Queue (Offline Sync)

    private var pendingEdits: [PendingCalendarEdit] = []

    private func queuePendingEdit(_ edit: PendingCalendarEdit) {
        pendingEdits.append(edit)
        pendingEditsCount = pendingEdits.count
        savePendingEdits()
    }

    private func savePendingEdits() {
        do {
            let data = try JSONEncoder().encode(pendingEdits)
            if let key = KeychainHelper.loadOrCreateFileIntegrityKey() {
                try SignedFileStore.write(data, to: pendingEditsPath, key: key)
                UserDefaults.standard.set(true, forKey: pendingEditsIntegrityMigratedKey)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: SignedFileStore.signatureURL(for: pendingEditsPath).path)
            } else {
                try data.write(to: pendingEditsPath, options: .atomic)
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pendingEditsPath.path)
        } catch { print("[Calen] Failed to save pending edits") }
    }

    private func loadPendingEdits() {
        guard fileManager.fileExists(atPath: pendingEditsPath.path) else { return }
        do {
            let key = KeychainHelper.loadOrCreateFileIntegrityKey()
            let data: Data
            if let key {
                if let verified = try SignedFileStore.readVerified(from: pendingEditsPath, key: key) {
                    data = verified
                } else {
                    guard !UserDefaults.standard.bool(forKey: pendingEditsIntegrityMigratedKey) else {
                        print("[Calen] Rejected unsigned or tampered pending edits")
                        pendingEdits = []
                        pendingEditsCount = 0
                        return
                    }
                    let legacyData = try Data(contentsOf: pendingEditsPath)
                    let legacyEdits = try JSONDecoder().decode([PendingCalendarEdit].self, from: legacyData)
                    guard PendingCalendarEdit.isSafeQueue(legacyEdits) else {
                        print("[Calen] Rejected unsafe pending edits")
                        pendingEdits = []
                        pendingEditsCount = 0
                        return
                    }
                    pendingEdits = legacyEdits
                    pendingEditsCount = pendingEdits.count
                    savePendingEdits()
                    return
                }
            } else {
                data = try Data(contentsOf: pendingEditsPath)
            }
            let decoded = try JSONDecoder().decode([PendingCalendarEdit].self, from: data)
            guard PendingCalendarEdit.isSafeQueue(decoded) else {
                print("[Calen] Rejected unsafe pending edits")
                pendingEdits = []
                pendingEditsCount = 0
                return
            }
            pendingEdits = decoded
            pendingEditsCount = pendingEdits.count
        } catch { print("[Calen] Failed to load pending edits") }
    }

    /// Sync all pending offline edits to Google Calendar
    func syncPendingEdits() async {
        guard !pendingEdits.isEmpty, authManager.isAuthenticated else { return }
        guard !isSyncingPendingEdits else { return }  // 재진입 방지
        isSyncingPendingEdits = true
        defer { isSyncingPendingEdits = false }

        // 처리할 배치를 스냅샷하고 pendingEdits를 즉시 비움
        // → await 구간에 새로 추가된 편집이 remaining 덮어쓰기로 유실되는 문제 방지
        let batch = pendingEdits
        guard PendingCalendarEdit.isSafeQueue(batch) else {
            print("[Calen] Rejected unsafe pending edits before sync")
            pendingEdits = []
            pendingEditsCount = 0
            savePendingEdits()
            return
        }
        pendingEdits = []
        savePendingEdits()

        var remaining: [PendingCalendarEdit] = []

        for edit in batch {
            do {
                switch edit.action {
                case "create":
                    if let realEvent = try await googleService.createEvent(
                        title: edit.title, startDate: edit.startDate,
                        endDate: edit.endDate, isAllDay: edit.isAllDay) {
                        // temp ID("pending-...")를 Google이 발급한 실제 이벤트 ID로 교체
                        let editTitle = edit.title
                        let editStart = edit.startDate
                        if let idx = self.calendarEvents.firstIndex(where: {
                            $0.id.hasPrefix("pending-") &&
                            $0.title == editTitle &&
                            abs($0.startDate.timeIntervalSince(editStart)) < 60
                        }) {
                            self.calendarEvents[idx] = realEvent
                            self.cacheEvents(self.calendarEvents)
                        }
                    } else {
                        recordCRUDFailure(operation: .create, source: .google, userVisible: false)
                    }
                case "update":
                    if let eventId = edit.eventId {
                        if try await googleService.updateEvent(
                            eventID: eventId,
                            calendarID: edit.calendarID ?? "primary",
                            title: edit.title,
                            startDate: edit.startDate, endDate: edit.endDate,
                            isAllDay: edit.isAllDay) == false {
                            recordCRUDFailure(operation: .update, source: .google, eventID: eventId, userVisible: false)
                        }
                    }
                case "delete":
                    if let eventId = edit.eventId {
                        if try await googleService.deleteEvent(
                            eventID: eventId,
                            calendarID: edit.calendarID ?? "primary") == false {
                            recordCRUDFailure(operation: .delete, source: .google, eventID: eventId, userVisible: false)
                        }
                    }
                default: break
                }
            } catch {
                // Keep failed edits for next sync attempt
                let operation = CRUDOperation(rawValue: edit.action)
                recordCRUDFailure(
                    operation: operation ?? .update,
                    source: .google,
                    eventID: edit.eventId,
                    error: error,
                    userVisible: false
                )
                if Self.shouldQueueGoogleMutation(after: error) {
                    PlanitLoggers.sync.info("Keeping pending edit for retry action=\(edit.action, privacy: .public) eventID=\(edit.eventId ?? "none", privacy: .public)")
                    remaining.append(edit)
                } else {
                    PlanitLoggers.sync.warning("Dropping permanent pending edit failure action=\(edit.action, privacy: .public) eventID=\(edit.eventId ?? "none", privacy: .public)")
                }
            }
        }

        // 실패한 편집 + sync 도중 새로 추가된 편집을 합산
        pendingEdits = remaining + pendingEdits
        pendingEditsCount = pendingEdits.count
        savePendingEdits()
    }
}
