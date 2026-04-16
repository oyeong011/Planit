import Foundation

// MARK: - UserContextService
// 사용자의 행동 패턴, 목표, 배경 정보를 마크다운 파일로 관리합니다.
// AI가 이 파일을 읽어 초개인화 일정 추천에 활용합니다.

/// 현재 앱 표시 언어의 BCP-47 코드 (예: "ko", "en", "zh-Hant")
private func userDisplayLanguage() -> String {
    Locale.current.language.languageCode?.identifier ?? "en"
}

/// AI 프롬프트에 붙일 "이 언어로 응답하세요" 지시문
private func languageInstruction() -> String {
    let lang = Locale.current.localizedString(forLanguageCode: userDisplayLanguage()) ?? "English"
    return "Respond entirely in \(lang) (\(userDisplayLanguage()))."
}

@MainActor
final class UserContextService: ObservableObject {

    @Published private(set) var contextSummary: String = ""  // UI 표시용 요약

    private let contextFileURL: URL
    private let fm = FileManager.default

    // 섹션 헤더 상수
    private enum Section {
        static let profile    = "## 👤 사용자 프로필"
        static let focus      = "## 🎯 현재 집중 영역"
        static let style      = "## 📋 계획 스타일"
        static let external   = "## 🌐 외부 정보 캐시"
        static let log        = "## 📝 관찰 기록"
    }

    init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("Planit", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        contextFileURL = dir.appendingPathComponent("user_context.md")
        ensureFileExists()
        loadSummary()
    }

    // MARK: - 공개 읽기 API

    /// AI 시스템 프롬프트에 주입할 컨텍스트 블록 반환
    func contextForAI() -> String {
        let content = (try? String(contentsOf: contextFileURL, encoding: .utf8)) ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        // 전체 파일에서 최근 관찰 기록은 최대 10줄만 포함 (토큰 절약)
        let lines = content.components(separatedBy: "\n")
        var trimmed: [String] = []
        var logCount = 0
        var inLog = false

        for line in lines {
            if line.hasPrefix("## 📝") { inLog = true }
            if inLog {
                if line.hasPrefix("- ") { logCount += 1 }
                if logCount > 10 { continue }  // 오래된 로그 생략
            }
            trimmed.append(line)
        }

        // 전체 컨텍스트 최대 8000자 제한 (토큰 스터핑 방지)
        let body = String(trimmed.joined(separator: "\n").prefix(8000))
        return """
        ## 🧠 사용자 개인 컨텍스트 (초개인화)
        > 아래는 이 사용자에 대해 누적된 개인 정보입니다. 일정 추천 시 반드시 참고하세요.

        \(body)
        ---
        """
    }

    /// 특정 섹션 내용 반환
    func sectionContent(_ header: String) -> String {
        let content = (try? String(contentsOf: contextFileURL, encoding: .utf8)) ?? ""
        return extractSection(header, from: content)
    }

    // MARK: - 섹션별 업데이트

    func updateProfile(role: String? = nil, situation: String? = nil, goal: String? = nil) {
        var lines: [String] = []
        let existing = sectionContent(Section.profile)
        var updated: [String: String] = parseKeyValues(existing)

        if let r = role, !r.isEmpty { updated["역할"] = r }
        if let s = situation, !s.isEmpty { updated["현재 상황"] = s }
        if let g = goal, !g.isEmpty { updated["주요 목표"] = g }

        for (k, v) in updated.sorted(by: { $0.key < $1.key }) {
            lines.append("- **\(k)**: \(v)")
        }
        updateSection(Section.profile, body: lines.joined(separator: "\n"))
        loadSummary()
    }

    func updatePlanningStyle(granularity: String? = nil, preferredTime: String? = nil, extra: String? = nil) {
        var updated = parseKeyValues(sectionContent(Section.style))
        if let g = granularity, !g.isEmpty { updated["계획 세분도"] = g }
        if let t = preferredTime, !t.isEmpty { updated["선호 집중 시간대"] = t }
        if let e = extra, !e.isEmpty { updated["기타"] = e }

        let lines = updated.sorted(by: { $0.key < $1.key }).map { "- **\($0.key)**: \($0.value)" }
        updateSection(Section.style, body: lines.joined(separator: "\n"))
    }

    func setFocusArea(topic: String, detail: String) {
        var existing = sectionContent(Section.focus)
        // topic이 이미 있으면 교체, 없으면 추가
        let marker = "### \(topic)"
        if existing.contains(marker) {
            let parts = existing.components(separatedBy: marker)
            var rest = parts.dropFirst().first ?? ""
            // 다음 ### 이전까지 잘라내기
            if let nextHeader = rest.range(of: "\n###") {
                rest = String(rest[nextHeader.lowerBound...])
            } else {
                rest = ""
            }
            existing = (existing.components(separatedBy: marker).first ?? "") + marker + "\n\(detail)\n" + rest
        } else {
            existing += "\n\(marker)\n\(detail)\n"
        }
        updateSection(Section.focus, body: existing.trimmingCharacters(in: .whitespacesAndNewlines))
        loadSummary()
    }

    func setExternalInfo(topic: String, info: String) {
        let existing = sectionContent(Section.external)
        let marker = "### \(topic)"
        var updated: String
        if existing.contains(marker) {
            // 기존 항목 교체
            let parts = existing.components(separatedBy: marker)
            var rest = parts.dropFirst().first ?? ""
            if let nextHeader = rest.range(of: "\n###") {
                rest = String(rest[nextHeader.lowerBound...])
            } else {
                rest = ""
            }
            updated = (parts.first ?? "") + marker + "\n\(info)\n" + rest
        } else {
            updated = existing + "\n\(marker)\n\(info)\n"
        }
        updateSection(Section.external, body: updated.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func addObservation(_ text: String) {
        let now = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        var current = sectionContent(Section.log)
        let entry = "- [\(now)] \(text)"
        current = entry + (current.isEmpty ? "" : "\n" + current)
        // 최대 30개 로그 유지
        let logLines = current.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        let trimmedLog = Array(logLines.prefix(30)).joined(separator: "\n")
        updateSection(Section.log, body: trimmedLog)
    }

    // MARK: - AI 기반 컨텍스트 추출

    /// 대화 내용을 분석해 프로필 정보를 자동으로 추출/업데이트합니다.
    func extractAndUpdate(from messages: [String], claudePath: String) async {
        guard !messages.isEmpty else { return }

        let conversation = Self.sanitizeForPrompt(messages.suffix(10).joined(separator: "\n"))
        let existingContext = Self.sanitizeForPrompt(
            sectionContent(Section.profile) + "\n" + sectionContent(Section.style)
        )

        let langNote = languageInstruction()
        let prompt = """
        \(langNote)
        You are analyzing a calendar app user's conversation to extract profile information.
        Respond with pure JSON only — no markdown, no explanation.

        Conversation:
        \(conversation)

        Previously known info:
        \(existingContext)

        JSON format (use null for fields with no new information):
        {
          "role": "job/role in user's language (e.g. student, developer, job seeker)",
          "situation": "current situation in user's language",
          "primaryGoal": "main goal in user's language",
          "planningGranularity": "detailed / big-picture / mixed",
          "preferredFocusTime": "morning / afternoon / evening / late-night or null",
          "focusTopic": "current focus topic name (exam, project, etc.)",
          "observations": ["observations from this conversation (max 2)"],
          "needsExternalInfo": "topic needing web search or null"
        }
        """

        let result = await Task.detached(priority: .background) {
            UserContextService.runClaude(prompt: prompt, claudePath: claudePath)
        }.value

        await applyExtraction(result)
    }

    private func applyExtraction(_ jsonString: String) async {
        // JSON 추출
        var raw = jsonString
        if let start = jsonString.range(of: "{"), let end = jsonString.range(of: "}", options: .backwards) {
            raw = String(jsonString[start.lowerBound...end.upperBound])
        }

        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let role      = json["role"]      as? String
        let situation = json["situation"] as? String
        let goal      = json["primaryGoal"] as? String
        let gran      = json["planningGranularity"] as? String
        let prefTime  = json["preferredFocusTime"] as? String
        let focus     = json["focusTopic"] as? String
        let obs       = json["observations"] as? [String] ?? []
        let needsWeb  = json["needsExternalInfo"] as? String

        if role != nil || situation != nil || goal != nil {
            updateProfile(role: role, situation: situation, goal: goal)
        }
        if gran != nil || prefTime != nil {
            updatePlanningStyle(granularity: gran, preferredTime: prefTime)
        }
        if let f = focus, !f.isEmpty {
            setFocusArea(topic: f, detail: "- in progress")
        }
        for ob in obs where !ob.isEmpty {
            addObservation(ob)
        }
        // 외부 정보 검색 필요한 경우 → 별도 enrichment 트리거
        if let topic = needsWeb, !topic.isEmpty {
            Task { await self.enrichExternalInfo(topic: topic, claudePath: nil) }
        }
    }

    // MARK: - 외부 정보 보강

    /// 시험 일정, 공부 커리큘럼 등 외부 정보를 검색해 캐싱합니다.
    func enrichExternalInfo(topic: String, claudePath: String?) async {
        // 이미 최근에 검색된 정보면 스킵 (1주일 캐시)
        let existing = sectionContent(Section.external)
        let topicKey = "### \(topic)"
        if existing.contains(topicKey) {
            let idx = existing.components(separatedBy: topicKey).first?.count ?? 0
            let afterTopic = String(existing.dropFirst(idx + topicKey.count))
            if afterTopic.contains("_검색일:") {
                // 캐시된 정보가 있음 → 1주일 이내면 스킵
                // (간단화: 항목 존재 자체를 캐시 유효로 처리)
                return
            }
        }

        // 1. DuckDuckGo Instant Answer로 빠른 검색 시도
        let ddgResult = await fetchDuckDuckGo(query: topic)

        // 2. Claude로 구조화된 정보 생성
        let claudeResult: String
        if let path = claudePath {
            let langNote = languageInstruction()
            claudeResult = await Task.detached(priority: .background) {
                let prompt = """
                \(langNote)
                Summarize the following topic concisely in markdown list format:
                Topic: \(topic)

                Include:
                - If exam/certification: annual schedule, subjects/modules, pass criteria
                - If study topic: learning sequence, key chapters, estimated time
                - If project: major phases, checkpoints

                DuckDuckGo search result for reference:
                \(ddgResult.isEmpty ? "(none)" : Self.sanitizeForPrompt(ddgResult, maxLength: 1500))

                Keep it to 5-10 lines. Mark uncertain dates as "TBD".
                """
                return UserContextService.runClaude(prompt: prompt, claudePath: path)
            }.value
        } else {
            claudeResult = ddgResult
        }

        guard !claudeResult.isEmpty else { return }

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let info = claudeResult + "\n_검색일: \(dateStr)_"
        setExternalInfo(topic: topic, info: info)

        // 집중 영역에도 외부 정보 요약 연결
        let shortSummary = claudeResult.components(separatedBy: "\n").prefix(3).joined(separator: "\n")
        setFocusArea(topic: topic, detail: shortSummary + "\n→ see: 📌 External Info Cache section")
    }

    // MARK: - 계획 스타일 분석

    /// 사용자의 할일/이벤트 패턴을 분석해 계획 스타일을 추론합니다.
    func analyzePlanningStyle(todos: [String], events: [String]) {
        guard !todos.isEmpty || !events.isEmpty else { return }

        let allItems = todos + events
        let avgLength = allItems.map { $0.count }.reduce(0, +) / max(allItems.count, 1)
        let hasDetailedItems = allItems.contains { $0.count > 15 || $0.contains(":") || $0.contains("-") }
        let hasVagueItems = allItems.contains { $0.count < 8 }

        // 로케일 무관한 영어 값 사용 (AI가 읽는 내부 데이터)
        let granularity: String
        if hasDetailedItems && !hasVagueItems {
            granularity = "detailed (step-by-step planning)"
        } else if hasVagueItems && !hasDetailedItems {
            granularity = "big-picture (brief planning)"
        } else {
            granularity = "mixed (varies by situation)"
        }

        if allItems.count >= 5 {
            updatePlanningStyle(granularity: granularity,
                                extra: "avg todo title length: \(avgLength) chars")
        }
    }

    // MARK: - 파일 파싱 유틸

    private func ensureFileExists() {
        guard !fm.fileExists(atPath: contextFileURL.path) else { return }

        // 파일 초기 내용은 언어 무관 — 섹션 헤더는 파싱 키이므로 고정
        let initial = """
        # 🧠 Calen User Context
        > This file is automatically managed by the app. You can also edit it directly.
        > AI reads this file to provide hyper-personalized schedule recommendations.

        \(Section.profile)
        _[auto-filled from conversations]_

        \(Section.focus)
        _[current focus area — exams, projects, topics]_

        \(Section.style)
        _[auto-detected from your todo/event patterns]_

        \(Section.external)
        _[external info cached from web searches]_

        \(Section.log)
        _[observations noted from your conversations]_
        """
        try? initial.write(to: contextFileURL, atomically: true, encoding: .utf8)
    }

    private func loadSummary() {
        let content = (try? String(contentsOf: contextFileURL, encoding: .utf8)) ?? ""
        let profile = extractSection(Section.profile, from: content)
        let focus = extractSection(Section.focus, from: content)
        // placeholder 줄 제거: 언더스코어 italics(_[...]_) 또는 괄호로만 이루어진 줄
        let isPlaceholder: (String) -> Bool = { text in
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t.hasPrefix("_[") || (t.hasPrefix("(") && t.hasSuffix(")"))
        }
        let cleaned = [profile, focus].filter { !isPlaceholder($0) }
        contextSummary = cleaned.joined(separator: "\n")
    }

    private func updateSection(_ header: String, body: String) {
        var content = (try? String(contentsOf: contextFileURL, encoding: .utf8)) ?? ""
        let allHeaders = [Section.profile, Section.focus, Section.style, Section.external, Section.log]

        if content.contains(header) {
            // 섹션 찾아서 교체
            guard let range = content.range(of: header) else { return }
            var endIdx = content.endIndex

            // 다음 섹션 헤더 찾기
            for h in allHeaders where h != header {
                if let r = content.range(of: "\n\(h)", range: range.upperBound..<content.endIndex) {
                    if r.lowerBound < endIdx { endIdx = r.lowerBound }
                }
            }

            let sectionContent = "\n" + header + "\n" + body + "\n"
            content.replaceSubrange(range.lowerBound..<endIdx, with: sectionContent)
        } else {
            content += "\n\(header)\n\(body)\n"
        }

        try? content.write(to: contextFileURL, atomically: true, encoding: .utf8)
    }

    private func extractSection(_ header: String, from content: String) -> String {
        guard let start = content.range(of: header + "\n") else { return "" }
        let allHeaders = [Section.profile, Section.focus, Section.style, Section.external, Section.log]
        var endIdx = content.endIndex

        for h in allHeaders where h != header {
            if let r = content.range(of: "\n" + h, range: start.upperBound..<content.endIndex) {
                if r.lowerBound < endIdx { endIdx = r.lowerBound }
            }
        }

        return String(content[start.upperBound..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseKeyValues(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            // "- **key**: value" 또는 "- key: value" 패턴
            if line.hasPrefix("- ") {
                let stripped = String(line.dropFirst(2))
                    .replacingOccurrences(of: "**", with: "")
                if let colon = stripped.firstIndex(of: ":") {
                    let key = String(stripped[stripped.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                    let value = String(stripped[stripped.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty && !value.isEmpty {
                        result[key] = value
                    }
                }
            }
        }
        return result
    }

    // MARK: - DuckDuckGo 검색

    private func fetchDuckDuckGo(query: String) async -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return ""
        }

        let result: String = await withCheckedContinuation { cont in
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    cont.resume(returning: "")
                    return
                }
                var parts: [String] = []
                if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
                    parts.append(abstract)
                }
                if let answer = json["Answer"] as? String, !answer.isEmpty {
                    parts.append(answer)
                }
                if let topics = json["RelatedTopics"] as? [[String: Any]] {
                    let summaries = topics.prefix(3).compactMap { $0["Text"] as? String }
                    parts.append(contentsOf: summaries)
                }
                cont.resume(returning: parts.joined(separator: "\n"))
            }.resume()
        }
        return result
    }

    // MARK: - Sanitization (프롬프트 인젝션 방지)

    /// 사용자/외부 데이터를 프롬프트에 삽입하기 전 sanitize
    nonisolated private static func sanitizeForPrompt(_ text: String, maxLength: Int = 2000) -> String {
        String(text
            .replacingOccurrences(of: "\r", with: " ")
            .components(separatedBy: "\n")
            .map { line -> String in
                // 프롬프트 구조를 깨는 패턴 제거 (role 마커, JSON 탈출 시도)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("사용자:") || trimmed.hasPrefix("어시스턴트:") ||
                   trimmed.hasPrefix("Human:") || trimmed.hasPrefix("Assistant:") ||
                   trimmed.hasPrefix("System:") || trimmed.hasPrefix("SYSTEM:") {
                    return "[filtered]"
                }
                return line
            }
            .joined(separator: "\n")
            .prefix(maxLength))
    }

    // MARK: - Claude One-shot (nonisolated helper)

    nonisolated static func runClaude(prompt: String, claudePath: String) -> String {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", "--output-format", "text",
                             "--no-session-persistence",
                             "--model", "claude-haiku-4-5-20251001",
                             "--system-prompt", "한국어로 간결하게 답변하는 AI 비서입니다."]

        let input = Pipe()
        let output = Pipe()
        let errPipe = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errPipe

        do {
            try process.run()
            let data = prompt.data(using: .utf8) ?? Data()
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            let outData = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
        #else
        return ""
        #endif
    }

    // MARK: - 컨텍스트 파일 경로 (디버그/설정용)

    var contextFilePath: String { contextFileURL.path }
}

// MARK: - 알려진 한국 자격증/시험 키워드

extension UserContextService {
    /// 메시지에서 알려진 시험/자격증 키워드를 감지합니다.
    static func detectExamKeywords(in text: String) -> [String] {
        let keywords: [String: String] = [
            "정보처리기사": "정보처리기사",
            "정처기": "정보처리기사",
            "정보처리산업기사": "정보처리산업기사",
            "토익": "TOEIC",
            "토플": "TOEFL",
            "수능": "대학수학능력시험",
            "공무원": "공무원 시험",
            "행정고시": "행정고시",
            "사법고시": "사법시험",
            "변호사시험": "변호사시험",
            "SQLD": "SQLD (SQL 개발자)",
            "정보보안기사": "정보보안기사",
            "AWS": "AWS 자격증",
            "리눅스마스터": "리눅스마스터",
            "네트워크관리사": "네트워크관리사",
            "CPA": "공인회계사(CPA)",
            "세무사": "세무사",
            "IELTS": "IELTS",
            "한국사능력검정": "한국사능력검정",
        ]

        var found: [String] = []
        for (keyword, canonical) in keywords {
            if text.contains(keyword) && !found.contains(canonical) {
                found.append(canonical)
            }
        }
        return found
    }

    /// 알려진 시험의 기본 정보를 반환합니다 (캐시 없을 때 즉시 사용).
    static func builtinExamInfo(_ examName: String) -> String? {
        let info: [String: String] = [
            "정보처리기사": """
            - 주관: 한국산업인력공단 (Q-NET)
            - 시험: 연 3회 (1회: 3월, 2회: 6월, 3회: 9월 — 매년 일정 변경되므로 Q-NET 확인 필요)
            - 과목: ①소프트웨어설계 ②소프트웨어개발 ③데이터베이스구축 ④프로그래밍언어활용 ⑤정보시스템구축관리
            - 합격기준: 각 과목 40점 이상 + 평균 60점 이상 (필기), 실기 60점 이상
            - 공부 순서: 필기(2~3개월) → 실기(1~2개월), 수험서 + 기출문제 위주
            """,
            "TOEIC": """
            - 주관: YBM/ETS
            - 시험: 매월 2~3회 (YBM 사이트에서 일정 확인)
            - 구성: LC(듣기 495점) + RC(읽기 495점) = 총 990점
            - 합격기준: 기관/기업마다 상이 (취업: 보통 700~850점 이상)
            - 공부 순서: LC (파트1~4) → RC (파트5~7), 실전모의고사 반복
            """,
        ]
        return info[examName]
    }
}
