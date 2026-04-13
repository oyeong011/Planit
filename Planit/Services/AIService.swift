import Foundation

// MARK: - Provider

enum AIProvider: String, CaseIterable, Codable {
    case gemini = "Gemini"
    case claude = "Claude Code"
    case codex = "Codex"

    var icon: String {
        switch self {
        case .gemini: return "g.circle.fill"
        case .claude: return "c.circle.fill"
        case .codex: return "o.circle.fill"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.0-flash"
        case .claude: return "claude-sonnet-4-20250514"
        case .codex: return "gpt-5.4"
        }
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    let timestamp: Date

    enum Role {
        case user, assistant, system, toolCall
    }

    init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Calendar Action

struct CalendarAction: Codable {
    let action: String
    let title: String?
    let startDate: String?
    let endDate: String?
    let eventId: String?
    let isAllDay: Bool?
}

struct AIResponseWithActions: Codable {
    let message: String
    let actions: [CalendarAction]?
}

// MARK: - AI Service

@MainActor
final class AIService: ObservableObject {
    @Published var provider: AIProvider = .gemini
    @Published var isLoading: Bool = false
    @Published var claudeAvailable: Bool = false
    @Published var codexAvailable: Bool = false
    /// Pending actions awaiting user approval before execution
    @Published var pendingActions: [CalendarAction] = []
    @Published var pendingMessage: String?

    private let authManager: GoogleAuthManager
    private let calendarService: GoogleCalendarService?

    /// Cached absolute paths for CLI tools (resolved once)
    private var claudePath: String?
    private var codexPath: String?

    /// Known valid event IDs from the last calendar context fetch
    private var knownEventIds: Set<String> = []

    nonisolated(unsafe) private static let cliTimeout: TimeInterval = 90
    nonisolated(unsafe) private static let maxOutputBytes = 1_048_576  // 1 MB

    var isConfigured: Bool {
        switch provider {
        case .gemini: return authManager.isAuthenticated
        case .claude: return claudeAvailable
        case .codex: return codexAvailable
        }
    }

    init(authManager: GoogleAuthManager, calendarService: GoogleCalendarService?) {
        self.authManager = authManager
        self.calendarService = calendarService
        loadSettings()
        checkCLIAvailability()
    }

    // MARK: - CLI Detection (resolve absolute paths, no login shell)

    private func checkCLIAvailability() {
        Task.detached { [weak self] in
            let claudeResolved = Self.resolvePath("claude")
            let codexResolved = Self.resolvePath("codex")
            await MainActor.run {
                self?.claudePath = claudeResolved
                self?.claudeAvailable = claudeResolved != nil
                self?.codexPath = codexResolved
                self?.codexAvailable = codexResolved != nil
            }
        }
    }

    /// Resolve absolute path for a command without login shell (uses /usr/bin/which + common paths)
    nonisolated private static func resolvePath(_ cmd: String) -> String? {
        // Check common paths directly — no shell involved
        let searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/.npm-global/bin",
            NSHomeDirectory() + "/.nvm/current/bin",
        ]
        for dir in searchPaths {
            let full = "\(dir)/\(cmd)"
            if FileManager.default.isExecutableFile(atPath: full) {
                return full
            }
        }

        // Fallback: use /usr/bin/which with minimal environment and timeout
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [cmd]
        proc.environment = [
            "PATH": searchPaths.joined(separator: ":") + ":/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            // 2-second timeout for which
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + 2)
            timer.setEventHandler { if proc.isRunning { proc.terminate() } }
            timer.resume()
            proc.waitUntilExit()
            timer.cancel()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}

        // No login shell fallback — avoids executing arbitrary RC files
        return nil
    }

    // MARK: - Settings

    private var settingsDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Planit/ai", isDirectory: true)
    }

    private func loadSettings() {
        let dir = settingsDir
        if let data = try? Data(contentsOf: dir.appendingPathComponent("provider")),
           let raw = String(data: data, encoding: .utf8),
           let p = AIProvider(rawValue: raw) {
            provider = p
        }
    }

    func saveSettings() {
        let dir = settingsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        try? provider.rawValue.data(using: .utf8)?.write(to: dir.appendingPathComponent("provider"), options: .atomic)
    }

    // MARK: - Calendar Context

    private func buildCalendarContext() async -> (context: String, eventIds: Set<String>) {
        guard let service = calendarService else { return ("캘린더 미연결", []) }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var context = "=== 이번 주 캘린더 일정 ===\n"
        var ids = Set<String>()

        do {
            var allEvents: [CalendarEvent] = []
            for dayOffset in 0..<7 {
                let date = cal.date(byAdding: .day, value: dayOffset, to: today)!
                let events = try await service.fetchEvents(for: date)
                allEvents.append(contentsOf: events)
            }

            var seen = Set<String>()
            let unique = allEvents.filter { seen.insert($0.id).inserted }
            let sorted = unique.sorted { $0.startDate < $1.startDate }

            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
            fmt.timeZone = TimeZone(identifier: "Asia/Seoul")

            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "yyyy-MM-dd (E)"
            dayFmt.locale = Locale(identifier: "ko_KR")
            dayFmt.timeZone = TimeZone(identifier: "Asia/Seoul")

            if sorted.isEmpty {
                context += "일정 없음\n"
            } else {
                for event in sorted {
                    ids.insert(event.id)
                    context += "- [\(event.id)] \(fmt.string(from: event.startDate)) ~ \(fmt.string(from: event.endDate)) | \(event.title)\n"
                }
            }
            context += "\n오늘: \(dayFmt.string(from: Date()))\n"
        } catch {
            context += "일정 로드 실패: \(error.localizedDescription)\n"
        }

        return (context, ids)
    }

    private func buildSystemPrompt(calendarContext: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        let now = dateFormatter.string(from: Date())

        return """
        너는 Planit 캘린더 앱의 AI 어시스턴트야. 한국어로 답변해.
        현재 시각: \(now), 타임존: Asia/Seoul

        \(calendarContext)

        캘린더 작업이 필요하면 반드시 아래 JSON 형식으로 응답해:
        ```json
        {
          "message": "사용자에게 보여줄 메시지",
          "actions": [
            {
              "action": "create",
              "title": "일정 제목",
              "startDate": "2026-04-14T15:00:00+09:00",
              "endDate": "2026-04-14T16:00:00+09:00",
              "isAllDay": false
            }
          ]
        }
        ```

        action 종류: "create" (생성), "delete" (삭제, eventId 필수), "update" (수정, eventId 필수)
        날짜 형식: ISO8601 with timezone (예: 2026-04-14T15:00:00+09:00)

        캘린더 작업이 없는 일반 대화면 그냥 텍스트로 응답해.
        일정 삭제/수정 시 위 일정 목록의 [eventId]를 사용해.
        """
    }

    // MARK: - User Confirmation for Actions

    /// Call this when user confirms pending actions (types "확인", "실행", etc.)
    func confirmPendingActions() async -> [ChatMessage] {
        let actions = pendingActions
        pendingActions = []
        pendingMessage = nil
        guard !actions.isEmpty else { return [] }
        return await executeActions(actions)
    }

    /// Call this when user declines pending actions
    func declinePendingActions() -> ChatMessage {
        pendingActions = []
        pendingMessage = nil
        return ChatMessage(role: .assistant, content: "작업이 취소되었습니다.")
    }

    var hasPendingActions: Bool { !pendingActions.isEmpty }

    // MARK: - Execute Actions (with eventId validation)

    private func executeActions(_ actions: [CalendarAction]) async -> [ChatMessage] {
        guard let service = calendarService else { return [] }
        var results: [ChatMessage] = []
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let fmtFrac = ISO8601DateFormatter()
        fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ str: String) -> Date? {
            fmtFrac.date(from: str) ?? fmt.date(from: str)
        }

        for action in actions {
            // Validate eventId for delete/update against known IDs
            if action.action == "delete" || action.action == "update" {
                guard let eventId = action.eventId, knownEventIds.contains(eventId) else {
                    results.append(ChatMessage(role: .toolCall, content: "⚠️ \(action.action) 실패: 유효하지 않은 eventId"))
                    continue
                }
            }

            switch action.action {
            case "create":
                guard let title = action.title,
                      let startStr = action.startDate,
                      let endStr = action.endDate,
                      let start = parseDate(startStr),
                      let end = parseDate(endStr) else {
                    results.append(ChatMessage(role: .toolCall, content: "⚠️ 생성 실패: 잘못된 파라미터"))
                    continue
                }
                do {
                    _ = try await service.createEvent(title: title, startDate: start, endDate: end, isAllDay: action.isAllDay ?? false)
                    results.append(ChatMessage(role: .toolCall, content: "✅ 생성: \(title)"))
                } catch {
                    results.append(ChatMessage(role: .toolCall, content: "⚠️ 생성 실패: \(error.localizedDescription)"))
                }

            case "delete":
                let eventId = action.eventId!
                do {
                    let ok = try await service.deleteEvent(eventID: eventId)
                    results.append(ChatMessage(role: .toolCall, content: ok ? "✅ 삭제 완료" : "⚠️ 삭제 실패"))
                } catch {
                    results.append(ChatMessage(role: .toolCall, content: "⚠️ 삭제 실패: \(error.localizedDescription)"))
                }

            case "update":
                let eventId = action.eventId!
                // Title is required; dates default to existing event times if not provided
                let title = action.title ?? "제목 없음"
                let startDate: Date
                let endDate: Date
                if let startStr = action.startDate, let s = parseDate(startStr) {
                    startDate = s
                    if let endStr = action.endDate, let e = parseDate(endStr) {
                        endDate = e
                    } else {
                        endDate = s.addingTimeInterval(3600)  // Default 1 hour
                    }
                } else {
                    // No dates provided — need both for API, skip with error
                    results.append(ChatMessage(role: .toolCall, content: "⚠️ 수정 실패: 날짜 정보 없음"))
                    continue
                }
                do {
                    let ok = try await service.updateEvent(eventID: eventId, title: title, startDate: startDate, endDate: endDate, isAllDay: action.isAllDay ?? false)
                    results.append(ChatMessage(role: .toolCall, content: ok ? "✅ 수정: \(title)" : "⚠️ 수정 실패"))
                } catch {
                    results.append(ChatMessage(role: .toolCall, content: "⚠️ 수정 실패: \(error.localizedDescription)"))
                }

            default:
                break
            }
        }
        return results
    }

    // MARK: - Parse AI Response

    private func parseAIResponse(_ raw: String) -> (message: String, actions: [CalendarAction]?) {
        let cleaned = Self.stripANSI(raw).trimmingCharacters(in: .whitespacesAndNewlines)

        // Try all JSON blocks in the response (there might be multiple ```json blocks)
        var searchStart = cleaned.startIndex
        while let jsonRange = cleaned.range(of: "```json", options: .caseInsensitive, range: searchStart..<cleaned.endIndex) {
            // Find the newline after ```json
            let contentStart = cleaned.index(after: cleaned[jsonRange.upperBound...].firstIndex(of: "\n") ?? jsonRange.upperBound)
            if let endRange = cleaned.range(of: "\n```", range: contentStart..<cleaned.endIndex) {
                let jsonStr = String(cleaned[contentStart..<endRange.lowerBound])
                if let result = Self.tryParseJSON(jsonStr) {
                    return result
                }
            }
            searchStart = jsonRange.upperBound
        }

        // Try parsing entire response as JSON (with leading/trailing text stripped)
        if let braceStart = cleaned.firstIndex(of: "{"),
           let braceEnd = cleaned.lastIndex(of: "}") {
            let jsonCandidate = String(cleaned[braceStart...braceEnd])
            if let result = Self.tryParseJSON(jsonCandidate) {
                return result
            }
        }

        return (cleaned, nil)
    }

    nonisolated private static func tryParseJSON(_ jsonStr: String) -> (message: String, actions: [CalendarAction]?)? {
        guard let data = jsonStr.data(using: .utf8) else { return nil }

        // Try strict decode first
        if let parsed = try? JSONDecoder().decode(AIResponseWithActions.self, from: data) {
            return (parsed.message, parsed.actions)
        }

        // Try lenient: parse as dictionary and extract what we can
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let message = dict["message"] as? String ?? ""
        guard let actionsArray = dict["actions"] as? [[String: Any]], !actionsArray.isEmpty else {
            if !message.isEmpty { return (message, nil) }
            return nil
        }

        let actions = actionsArray.compactMap { obj -> CalendarAction? in
            guard let action = obj["action"] as? String else { return nil }
            return CalendarAction(
                action: action,
                title: obj["title"] as? String,
                startDate: obj["startDate"] as? String ?? obj["start_date"] as? String ?? obj["start"] as? String,
                endDate: obj["endDate"] as? String ?? obj["end_date"] as? String ?? obj["end"] as? String,
                eventId: obj["eventId"] as? String ?? obj["event_id"] as? String ?? obj["id"] as? String,
                isAllDay: obj["isAllDay"] as? Bool ?? obj["is_all_day"] as? Bool ?? obj["allDay"] as? Bool
            )
        }

        return (message, actions.isEmpty ? nil : actions)
    }

    /// Strip ANSI escape sequences (CSI, OSC, DCS, C0, C1) and normalize CR
    nonisolated private static func stripANSI(_ str: String) -> String {
        // CSI sequences: ESC[ or 0x9B ... final byte
        var result = str.replacingOccurrences(of: "(?:\\x1B\\[|\\x{9B})[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        // OSC sequences: ESC] or 0x9D ... (BEL or ST)
        result = result.replacingOccurrences(of: "(?:\\x1B\\]|\\x{9D})[^\\x07\\x{9C}]*(?:\\x07|\\x1B\\\\|\\x{9C})", with: "", options: .regularExpression)
        // DCS sequences: ESC P or 0x90 ... ST
        result = result.replacingOccurrences(of: "(?:\\x1BP|\\x{90})[^\\x{9C}]*(?:\\x1B\\\\|\\x{9C})", with: "", options: .regularExpression)
        // Remaining C0 controls except \t \n, and all C1 controls (0x80-0x9F)
        result = result.replacingOccurrences(of: "[\\x00-\\x08\\x0B-\\x0C\\x0E-\\x1F\\x7F\\x{80}-\\x{9F}]", with: "", options: .regularExpression)
        // Normalize \r\n → \n and standalone \r → \n
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    // MARK: - Send Message

    func sendMessage(_ userMessage: String, history: [ChatMessage]) async -> [ChatMessage] {
        isLoading = true
        defer { isLoading = false }

        let (calContext, eventIds) = await buildCalendarContext()
        knownEventIds = eventIds
        let systemPrompt = buildSystemPrompt(calendarContext: calContext)

        let rawResponse: String
        switch provider {
        case .gemini:
            rawResponse = await sendGemini(system: systemPrompt, userMessage: userMessage, history: history)
        case .claude:
            guard let path = claudePath else { return [ChatMessage(role: .assistant, content: "Claude Code가 설치되지 않았습니다.")] }
            rawResponse = await sendCLI(executablePath: path, args: ["-p", "--output-format", "text"],
                                         system: systemPrompt, userMessage: userMessage, history: history)
        case .codex:
            guard let path = codexPath else { return [ChatMessage(role: .assistant, content: "Codex CLI가 설치되지 않았습니다.")] }
            rawResponse = await sendCLI(executablePath: path, args: ["exec", "--sandbox", "read-only", "--skip-git-repo-check"],
                                         system: systemPrompt, userMessage: userMessage, history: history,
                                         isCodex: true)
        }

        let (message, actions) = parseAIResponse(rawResponse)
        var results: [ChatMessage] = []

        if let actions = actions, !actions.isEmpty {
            // Queue actions for user approval instead of executing immediately
            pendingActions = actions
            pendingMessage = message
            let summary = actions.map { "\($0.action): \($0.title ?? "?")" }.joined(separator: "\n")
            results.append(ChatMessage(role: .assistant, content: message))
            results.append(ChatMessage(role: .toolCall, content: "⚠️ 아래 작업을 실행할까요?\n\(summary)\n\n확인하려면 '확인' 또는 '실행'을 입력하세요."))
        } else if !message.isEmpty {
            results.append(ChatMessage(role: .assistant, content: message))
        }

        if results.isEmpty {
            results.append(ChatMessage(role: .assistant, content: rawResponse.isEmpty ? "응답을 받지 못했습니다." : rawResponse))
        }

        return results
    }

    // MARK: - CLI Execution (Direct Process — no shell)

    private func sendCLI(executablePath: String, args: [String], system: String, userMessage: String,
                         history: [ChatMessage], isCodex: Bool = false) async -> String {
        var fullPrompt = system + "\n\n"

        let recentHistory = history.suffix(10)
        for msg in recentHistory {
            switch msg.role {
            case .user: fullPrompt += "사용자: \(msg.content)\n"
            case .assistant: fullPrompt += "어시스턴트: \(msg.content)\n"
            default: break
            }
        }
        fullPrompt += "\n사용자: \(userMessage)"

        return await withCheckedContinuation { continuation in
            Task.detached {
                let result = Self.runCLIDirect(executablePath: executablePath, args: args,
                                                input: fullPrompt, isCodex: isCodex)
                continuation.resume(returning: result)
            }
        }
    }

    /// Run CLI tool directly without shell — stdin pipe for input, timeout enforced, streamed output cap
    nonisolated private static func runCLIDirect(executablePath: String, args: [String],
                                                  input: String, isCodex: Bool) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = args

        // Minimal environment — only what CLIs need
        let homeDir = NSHomeDirectory()
        proc.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(homeDir)/.local/bin",
            "HOME": homeDir,
            "NO_COLOR": "1",
            "TERM": "dumb",
            "LANG": "en_US.UTF-8",
        ]

        if isCodex {
            proc.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        }

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return "CLI 실행 실패: \(error.localizedDescription)"
        }

        // Write input to stdin, then close
        if let inputData = input.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(inputData)
        }
        inPipe.fileHandleForWriting.closeFile()

        // Streamed output collection with cap
        var outBuffer = Data()
        var errBuffer = Data()
        let outputCapReached = DispatchSemaphore(value: 0)
        var capHit = false

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if outBuffer.count + chunk.count > maxOutputBytes {
                outBuffer.append(chunk.prefix(maxOutputBytes - outBuffer.count))
                capHit = true
                handle.readabilityHandler = nil
                // Terminate process to avoid pipe backpressure blocking
                if proc.isRunning { proc.terminate() }
                outputCapReached.signal()
            } else {
                outBuffer.append(chunk)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            // Cap stderr at 64KB
            if errBuffer.count < 65536 {
                errBuffer.append(chunk.prefix(65536 - errBuffer.count))
            }
        }

        // Timeout: SIGTERM after timeout, SIGKILL after grace period
        let killQueue = DispatchQueue(label: "planit.cli.timeout")
        let termTimer = DispatchSource.makeTimerSource(queue: killQueue)
        termTimer.schedule(deadline: .now() + cliTimeout)
        termTimer.setEventHandler {
            if proc.isRunning { proc.terminate() }
        }
        termTimer.resume()

        let killTimer = DispatchSource.makeTimerSource(queue: killQueue)
        killTimer.schedule(deadline: .now() + cliTimeout + 5)
        killTimer.setEventHandler {
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        killTimer.resume()

        proc.waitUntilExit()
        termTimer.cancel()
        killTimer.cancel()

        // Ensure all buffered data is read
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        var output = String(data: outBuffer, encoding: .utf8) ?? ""
        if capHit {
            output += "\n... (출력이 잘렸습니다)"
        }

        if proc.terminationStatus != 0 {
            let errStr = String(data: errBuffer, encoding: .utf8) ?? ""
            return output.isEmpty ? "오류: \(errStr)" : output
        }

        if isCodex {
            return cleanCodexOutput(output)
        }

        return output
    }

    nonisolated private static func cleanCodexOutput(_ raw: String) -> String {
        let lines = raw.components(separatedBy: "\n")
        var started = false
        var resultLines: [String] = []

        for line in lines {
            if line.starts(with: "Reading prompt") || line.starts(with: "OpenAI Codex") ||
               line.starts(with: "--------") || line.starts(with: "workdir:") ||
               line.starts(with: "model:") || line.starts(with: "provider:") ||
               line.starts(with: "approval:") || line.starts(with: "sandbox:") ||
               line.starts(with: "reasoning") || line.starts(with: "session id:") ||
               line.starts(with: "user") || line.starts(with: "tokens used") {
                if line.starts(with: "tokens used") { break }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == "codex" {
                started = true
                continue
            }
            if started || !line.trimmingCharacters(in: .whitespaces).isEmpty {
                started = true
                resultLines.append(line)
            }
        }

        return resultLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini (Google OAuth token)

    private func sendGemini(system: String, userMessage: String, history: [ChatMessage]) async -> String {
        guard let token = try? await authManager.getValidToken() else {
            return "Google 로그인이 필요합니다."
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(provider.defaultModel):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var contents: [[String: Any]] = []
        for msg in history {
            switch msg.role {
            case .user: contents.append(["role": "user", "parts": [["text": msg.content]]])
            case .assistant: contents.append(["role": "model", "parts": [["text": msg.content]]])
            default: break
            }
        }
        contents.append(["role": "user", "parts": [["text": userMessage]]])

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errMsg = (errJson?["error"] as? [String: Any])?["message"] as? String ?? "알 수 없는 오류"
                return "오류: \(errMsg)"
            }

            let texts = parts.compactMap { $0["text"] as? String }
            return texts.joined(separator: "\n")
        } catch {
            return "오류: \(error.localizedDescription)"
        }
    }
}
