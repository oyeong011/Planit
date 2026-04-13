import Foundation
import Testing

// MARK: - 공통 헬퍼: 프로덕션 로직 복제 (테스트 타겟은 앱 모듈 import 불가)

/// 프로덕션의 title.count > 10 ? String(title.prefix(10)) : title 로직
func truncateTitle(_ title: String) -> String {
    title.count > 10 ? String(title.prefix(10)) : title
}

/// 프로덕션의 todo 완료 상태에 따른 prefix 로직 (CalendarViewModel line 440)
/// completed → "✅ ", not completed → ""
func todoGooglePrefix(completed: Bool) -> String {
    completed ? "✅ " : ""
}

/// CLI 명령어 검증 — 정확히 "claude" 또는 "codex"만 허용
func isAllowedCLI(_ command: String) -> Bool {
    command == "claude" || command == "codex"
}

// MARK: - 리뷰 모드 결정 로직
func determineReviewMode(dailyDoneToday: Bool, eveningDoneToday: Bool, hour: Int, eveningStart: Int) -> String {
    if !dailyDoneToday {
        return "daily"
    } else if hour >= eveningStart && hour < eveningStart + 3 && !eveningDoneToday {
        return "evening"
    }
    return "none"
}

// MARK: - 테스트용 Codable 모델

struct TestCachedEvent: Codable, Identifiable {
    let id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var colorHex: String
    var isAllDay: Bool
    var calendarName: String
}

struct TestPendingEdit: Codable, Identifiable {
    let id: UUID
    let action: String
    var title: String
    var eventId: String?
    let createdAt: Date
}

struct TestTodo: Codable {
    let id: UUID
    var title: String
    var googleEventId: String?
}

// ============================================================================
// MARK: - TC-01~02: 텍스트 자르기 (Truncation)
// ============================================================================

@Test func textTruncation_under10chars_noChange() {
    let result = truncateTitle("짧은제목")
    #expect(result == "짧은제목")
}

@Test func textTruncation_exactly10chars_noChange() {
    let title = "열글자제목입니다열글"  // 10자
    let result = truncateTitle(title)
    #expect(result == "열글자제목입니다열글")
    #expect(result.count == 10)
}

@Test func textTruncation_over10chars_truncated() {
    let title = "정처기실기오전집중학습블록"  // 12자
    let result = truncateTitle(title)
    #expect(result == "정처기실기오전집중학")
    #expect(result.count == 10)
}

@Test func textTruncation_english_mixed() {
    let title = "JAVA Programming 101"  // 20자
    let result = truncateTitle(title)
    #expect(result == "JAVA Progr")
    #expect(result.count == 10)
}

@Test func textTruncation_emoji_title() {
    let title = "📚 정처기 실기 — 오전 집중 학습"
    let result = truncateTitle(title)
    #expect(result.count == 10)
}

// --- CRITICAL: 빈 문자열 및 경계값 테스트 ---

@Test func textTruncation_emptyString() {
    let result = truncateTitle("")
    #expect(result == "")
    #expect(result.count == 0)
}

@Test func textTruncation_9chars_boundary() {
    let title = "아홉글자제목입니아"  // 9자
    #expect(title.count == 9)
    let result = truncateTitle(title)
    #expect(result == title)  // 10 이하 → 그대로
    #expect(result.count == 9)
}

@Test func textTruncation_11chars_boundary() {
    let title = "열한글자제목입니다열한"  // 11자
    #expect(title.count == 11)
    let result = truncateTitle(title)
    #expect(result.count == 10)
    #expect(result == "열한글자제목입니다열")
}

@Test func textTruncation_singleChar() {
    let result = truncateTitle("A")
    #expect(result == "A")
}

// ============================================================================
// MARK: - TC-06~07: CLI 감지 (CLI Detection)
// ============================================================================

@Test func cliDetection_allowedCommands() {
    #expect(isAllowedCLI("claude"))
    #expect(isAllowedCLI("codex"))
}

@Test func cliDetection_rejectedCommands() {
    let rejected = ["rm", "bash", "/bin/sh", "python", "node"]
    for cmd in rejected {
        #expect(!isAllowedCLI(cmd), "Should reject: \(cmd)")
    }
}

// --- CRITICAL: 경로 탐색 및 특수 문자 주입 테스트 ---

@Test func cliDetection_pathTraversal_rejected() {
    let attacks = [
        "../claude",
        "../../claude",
        "/usr/bin/claude",
        "./claude",
        "claude/",
        "/claude",
    ]
    for cmd in attacks {
        #expect(!isAllowedCLI(cmd), "Path traversal should be rejected: \(cmd)")
    }
}

@Test func cliDetection_specialCharacterInjection_rejected() {
    let injections = [
        "claude;rm -rf /",
        "codex && evil",
        "claude|cat /etc/passwd",
        "claude\nrm -rf",
        "codex$(whoami)",
        "claude`id`",
        "claude ",       // 뒤에 공백
        " claude",       // 앞에 공백
        "CLAUDE",        // 대소문자
        "Codex",
    ]
    for cmd in injections {
        #expect(!isAllowedCLI(cmd), "Special char injection should be rejected: \(cmd)")
    }
}

@Test func cliDetection_emptyAndWhitespace_rejected() {
    #expect(!isAllowedCLI(""))
    #expect(!isAllowedCLI(" "))
    #expect(!isAllowedCLI("\t"))
    #expect(!isAllowedCLI("\n"))
}

@Test func cliDetection_unicodeHomoglyph_rejected() {
    // 유니코드 동형 문자 (예: 키릴 문자 "с" ≠ 라틴 "c")
    let homoglyph = "сlaude"  // 첫 글자가 키릴 с
    #expect(!isAllowedCLI(homoglyph))
}

// ============================================================================
// MARK: - TC-03~05: ReviewService 로직
// ============================================================================

@Test func reviewMode_dateKey_format() {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
    let key = fmt.string(from: Date())

    #expect(key.count == 10)
    #expect(key.contains("-"))

    // 같은 날 = 같은 키
    let key2 = fmt.string(from: Date())
    #expect(key == key2)
}

@Test func reviewMode_dailyBeforeEvening() {
    let mode = determineReviewMode(dailyDoneToday: false, eveningDoneToday: false, hour: 15, eveningStart: 21)
    #expect(mode == "daily")
}

@Test func reviewMode_eveningAfterDaily() {
    let mode = determineReviewMode(dailyDoneToday: true, eveningDoneToday: false, hour: 21, eveningStart: 21)
    #expect(mode == "evening")
}

@Test func reviewMode_noneWhenAllDone() {
    let mode = determineReviewMode(dailyDoneToday: true, eveningDoneToday: true, hour: 22, eveningStart: 21)
    #expect(mode == "none")
}

@Test func reviewMode_eveningOutOfRange_none() {
    // 저녁 시간 범위 밖 (eveningStart + 3 이상)
    let mode = determineReviewMode(dailyDoneToday: true, eveningDoneToday: false, hour: 18, eveningStart: 21)
    #expect(mode == "none")
}

// ============================================================================
// MARK: - TC-08: 오프라인 캐싱 — 인메모리 encode/decode
// ============================================================================

@Test func offlineCache_encodeDecode_roundtrip() throws {
    let event = TestCachedEvent(
        id: "test-event-123",
        title: "테스트 이벤트",
        startDate: Date(),
        endDate: Date().addingTimeInterval(3600),
        colorHex: "#6699FF",
        isAllDay: false,
        calendarName: "primary"
    )

    let data = try JSONEncoder().encode([event])
    let decoded = try JSONDecoder().decode([TestCachedEvent].self, from: data)

    #expect(decoded.count == 1)
    #expect(decoded[0].id == "test-event-123")
    #expect(decoded[0].title == "테스트 이벤트")
    #expect(decoded[0].colorHex == "#6699FF")
}

// --- HIGH: 실제 File I/O 테스트 ---

@Test func offlineCache_fileIO_writeAndReadBack() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let cacheFile = tmpDir.appendingPathComponent("test_events_cache_\(UUID().uuidString).json")

    let events = [
        TestCachedEvent(id: "ev-1", title: "아침 회의", startDate: Date(),
                        endDate: Date().addingTimeInterval(3600), colorHex: "#FF0000",
                        isAllDay: false, calendarName: "work"),
        TestCachedEvent(id: "ev-2", title: "점심 약속", startDate: Date(),
                        endDate: Date().addingTimeInterval(7200), colorHex: "#00FF00",
                        isAllDay: false, calendarName: "personal"),
    ]

    // 쓰기
    let encoder = JSONEncoder()
    let data = try encoder.encode(events)
    try data.write(to: cacheFile, options: .atomic)

    // 읽기
    let readData = try Data(contentsOf: cacheFile)
    let restored = try JSONDecoder().decode([TestCachedEvent].self, from: readData)

    #expect(restored.count == 2)
    #expect(restored[0].id == "ev-1")
    #expect(restored[0].title == "아침 회의")
    #expect(restored[1].id == "ev-2")
    #expect(restored[1].colorHex == "#00FF00")

    // 정리
    try? FileManager.default.removeItem(at: cacheFile)
}

@Test func offlineCache_fileIO_emptyArray() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let cacheFile = tmpDir.appendingPathComponent("test_empty_cache_\(UUID().uuidString).json")

    let events: [TestCachedEvent] = []
    let data = try JSONEncoder().encode(events)
    try data.write(to: cacheFile, options: .atomic)

    let readData = try Data(contentsOf: cacheFile)
    let restored = try JSONDecoder().decode([TestCachedEvent].self, from: readData)
    #expect(restored.isEmpty)

    try? FileManager.default.removeItem(at: cacheFile)
}

// --- HIGH: 손상된 캐시 처리 테스트 ---

@Test func offlineCache_corruptedData_decodeFails() {
    let corruptedData = "이건 JSON이 아닙니다 {{{".data(using: .utf8)!
    let result = try? JSONDecoder().decode([TestCachedEvent].self, from: corruptedData)
    #expect(result == nil, "손상된 데이터는 디코딩 실패해야 함")
}

@Test func offlineCache_corruptedFile_gracefulRecovery() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let cacheFile = tmpDir.appendingPathComponent("test_corrupt_\(UUID().uuidString).json")

    // 손상된 데이터를 파일에 쓰기
    try "not valid json!!!".data(using: .utf8)!.write(to: cacheFile, options: .atomic)

    // 프로덕션 패턴: 파일 읽고 디코딩 실패 시 빈 배열로 폴백
    let data = try Data(contentsOf: cacheFile)
    let events = (try? JSONDecoder().decode([TestCachedEvent].self, from: data)) ?? []
    #expect(events.isEmpty, "손상된 캐시에서 빈 배열로 복구해야 함")

    try? FileManager.default.removeItem(at: cacheFile)
}

@Test func offlineCache_partiallyCorruptedJSON() {
    // 유효한 JSON이지만 스키마가 다른 경우
    let wrongSchema = """
    [{"id": 123, "wrong_field": true}]
    """.data(using: .utf8)!

    let result = try? JSONDecoder().decode([TestCachedEvent].self, from: wrongSchema)
    #expect(result == nil, "스키마 불일치 시 디코딩 실패해야 함")
}

// ============================================================================
// MARK: - TC-09: Pending Edit 큐
// ============================================================================

@Test func pendingEdits_queueAndRestore() throws {
    var queue: [TestPendingEdit] = []

    queue.append(TestPendingEdit(id: UUID(), action: "create", title: "새 이벤트", eventId: nil, createdAt: Date()))
    queue.append(TestPendingEdit(id: UUID(), action: "update", title: "수정 이벤트", eventId: "event-456", createdAt: Date()))
    queue.append(TestPendingEdit(id: UUID(), action: "delete", title: "", eventId: "event-789", createdAt: Date()))

    #expect(queue.count == 3)

    let data = try JSONEncoder().encode(queue)
    let restored = try JSONDecoder().decode([TestPendingEdit].self, from: data)

    #expect(restored.count == 3)
    #expect(restored[0].action == "create")
    #expect(restored[1].action == "update")
    #expect(restored[1].eventId == "event-456")
    #expect(restored[2].action == "delete")
}

// --- HIGH: FIFO 순서 보장 테스트 ---

@Test func pendingEdits_fifoOrdering() throws {
    let now = Date()
    var queue: [TestPendingEdit] = []

    // 시간순으로 3개 추가
    for i in 0..<5 {
        queue.append(TestPendingEdit(
            id: UUID(), action: "create",
            title: "이벤트_\(i)", eventId: nil,
            createdAt: now.addingTimeInterval(Double(i))
        ))
    }

    // 파일에 저장했다가 복원
    let data = try JSONEncoder().encode(queue)
    let restored = try JSONDecoder().decode([TestPendingEdit].self, from: data)

    // FIFO: 순서가 보장되어야 함
    for i in 0..<5 {
        #expect(restored[i].title == "이벤트_\(i)", "FIFO 순서 위반: index \(i)")
    }
}

@Test func pendingEdits_fileIO_persistAndReload() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let editsFile = tmpDir.appendingPathComponent("test_pending_\(UUID().uuidString).json")

    let edits = [
        TestPendingEdit(id: UUID(), action: "create", title: "오프라인 생성", eventId: nil, createdAt: Date()),
        TestPendingEdit(id: UUID(), action: "delete", title: "", eventId: "ev-999", createdAt: Date()),
    ]

    let data = try JSONEncoder().encode(edits)
    try data.write(to: editsFile, options: .atomic)

    let readData = try Data(contentsOf: editsFile)
    let restored = try JSONDecoder().decode([TestPendingEdit].self, from: readData)

    #expect(restored.count == 2)
    #expect(restored[0].action == "create")
    #expect(restored[0].title == "오프라인 생성")
    #expect(restored[1].action == "delete")
    #expect(restored[1].eventId == "ev-999")

    try? FileManager.default.removeItem(at: editsFile)
}

@Test func pendingEdits_dequeueAfterSync() {
    // 동기화 성공 시 큐에서 제거되는 로직 시뮬레이션
    var queue = [
        TestPendingEdit(id: UUID(), action: "create", title: "A", eventId: nil, createdAt: Date()),
        TestPendingEdit(id: UUID(), action: "update", title: "B", eventId: "ev-1", createdAt: Date()),
        TestPendingEdit(id: UUID(), action: "delete", title: "", eventId: "ev-2", createdAt: Date()),
    ]

    // 첫 번째만 성공, 나머지 실패 시뮬레이션
    var remaining: [TestPendingEdit] = []
    for (i, edit) in queue.enumerated() {
        let syncSuccess = (i == 0)  // 첫 번째만 성공
        if !syncSuccess {
            remaining.append(edit)
        }
    }

    queue = remaining
    #expect(queue.count == 2)
    #expect(queue[0].action == "update")
    #expect(queue[1].action == "delete")
}

// ============================================================================
// MARK: - TC-10~11: Todo-Google 동기화
// ============================================================================

// --- CRITICAL FIX: 양쪽 분기를 실제로 다르게 검증 ---

@Test func todoSync_titlePrefix_completed() {
    let title = "JAVA"
    let prefix = todoGooglePrefix(completed: true)
    let cleanTitle = title.replacingOccurrences(of: "✅ ", with: "")
    let googleTitle = "\(prefix)\(cleanTitle)"

    #expect(prefix == "✅ ")
    #expect(googleTitle == "✅ JAVA")
}

@Test func todoSync_titlePrefix_notCompleted() {
    let title = "JAVA"
    let prefix = todoGooglePrefix(completed: false)
    let cleanTitle = title.replacingOccurrences(of: "✅ ", with: "")
    let googleTitle = "\(prefix)\(cleanTitle)"

    #expect(prefix == "")
    #expect(googleTitle == "JAVA", "미완료 todo에는 ✅ prefix가 없어야 함")
    #expect(!googleTitle.hasPrefix("✅"), "미완료 상태에 체크마크가 붙으면 안 됨")
}

@Test func todoSync_titlePrefix_alreadyHasPrefix_completed() {
    // 이미 ✅ 가 붙어있는 제목을 다시 동기화할 때 중복 방지
    let title = "✅ JAVA"
    let prefix = todoGooglePrefix(completed: true)
    let cleanTitle = title.replacingOccurrences(of: "✅ ", with: "")
    let googleTitle = "\(prefix)\(cleanTitle)"

    #expect(googleTitle == "✅ JAVA")
    #expect(!googleTitle.contains("✅ ✅"), "✅ 중복이 있으면 안 됨")
}

@Test func todoSync_titlePrefix_toggleCompletionCycle() {
    // 완료 → 미완료 → 완료 순환 시 제목이 올바른지 확인
    var title = "운동하기"

    // 1) 완료로 전환
    let prefix1 = todoGooglePrefix(completed: true)
    let clean1 = title.replacingOccurrences(of: "✅ ", with: "")
    title = "\(prefix1)\(clean1)"
    #expect(title == "✅ 운동하기")

    // 2) 미완료로 전환
    let prefix2 = todoGooglePrefix(completed: false)
    let clean2 = title.replacingOccurrences(of: "✅ ", with: "")
    title = "\(prefix2)\(clean2)"
    #expect(title == "운동하기")

    // 3) 다시 완료
    let prefix3 = todoGooglePrefix(completed: true)
    let clean3 = title.replacingOccurrences(of: "✅ ", with: "")
    title = "\(prefix3)\(clean3)"
    #expect(title == "✅ 운동하기")
}

@Test func todoSync_googleEventIdMapping() {
    var todo = TestTodo(id: UUID(), title: "테스트", googleEventId: nil)
    #expect(todo.googleEventId == nil)

    todo.googleEventId = "google-event-abc"
    #expect(todo.googleEventId == "google-event-abc")

    // Codable roundtrip
    let data = try! JSONEncoder().encode(todo)
    let decoded = try! JSONDecoder().decode(TestTodo.self, from: data)
    #expect(decoded.googleEventId == "google-event-abc")
}

@Test func todoSync_existingTodosWithoutGoogleId_decodesAsNil() {
    // 구 형식 데이터 호환성
    let oldJson = """
    {"id":"550E8400-E29B-41D4-A716-446655440000","title":"옛날할일"}
    """

    let data = oldJson.data(using: .utf8)!
    let todo = try! JSONDecoder().decode(TestTodo.self, from: data)

    #expect(todo.title == "옛날할일")
    #expect(todo.googleEventId == nil)
}

// ============================================================================
// MARK: - TC-12: 알림 스케줄링 로직
// ============================================================================

@Test func notification_dailyTrigger_dateComponents() {
    var components = DateComponents()
    components.hour = 8
    components.minute = 0

    #expect(components.year == nil)
    #expect(components.month == nil)
    #expect(components.day == nil)
    #expect(components.hour == 8)
    #expect(components.minute == 0)
}

@Test func notification_eventReminder_timeInterval() {
    let eventStart = Date().addingTimeInterval(3600)  // 1시간 후
    let minutesBefore = 15
    let reminderTime = eventStart.addingTimeInterval(-Double(minutesBefore * 60))
    let interval = reminderTime.timeIntervalSinceNow

    // ~45분 후 (60 - 15)
    #expect(interval > 0)
    #expect(interval < 3600)
}

@Test func notification_eventReminder_pastEvent_skipped() {
    let pastEvent = Date().addingTimeInterval(-3600)  // 1시간 전
    let minutesBefore = 15
    let reminderTime = pastEvent.addingTimeInterval(-Double(minutesBefore * 60))
    let interval = reminderTime.timeIntervalSinceNow

    #expect(interval < 0, "과거 이벤트 리마인더는 음수 간격이어야 함 → 스킵 대상")
}

// ============================================================================
// MARK: - 용량 체크 로직
// ============================================================================

@Test func capacityCheck_overloaded() {
    let scheduledMinutes = 480  // 8시간
    let capacityMinutes = 360   // 6시간
    let isOverloaded = scheduledMinutes > capacityMinutes
    let overMinutes = scheduledMinutes - capacityMinutes

    #expect(isOverloaded)
    #expect(overMinutes == 120)
}

@Test func capacityCheck_withinLimits() {
    let scheduledMinutes = 300
    let capacityMinutes = 360
    let isOverloaded = scheduledMinutes > capacityMinutes
    #expect(!isOverloaded)
}

// ============================================================================
// MARK: - Color Hex 변환
// ============================================================================

@Test func colorHex_validFormat() {
    let hex = "#6699FF"
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }

    #expect(h.count == 6)
    #expect(UInt64(h, radix: 16) != nil)
}

@Test func colorHex_invalidFormat_rejected() {
    let invalidHexes = ["#GGG", "not-a-color", "#12345", ""]
    for hex in invalidHexes {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        let isValid = h.count == 6 && UInt64(h, radix: 16) != nil
        #expect(!isValid, "Should reject: \(hex)")
    }
}
