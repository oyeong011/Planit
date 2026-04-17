import Foundation

/// 활동(캘린더 이벤트/할일)이 어떤 장기 목표와 관련 있는지 분류한다.
///
/// 2단계 파이프라인:
///   1) 키워드 매칭 — 빠름·결정적. goal.keywords / goal.targets 가 제목에 포함되면 즉시 매칭.
///   2) AI 분류   — 키워드 누락 활동에 한해 Claude/Codex CLI로 판정.
///
/// 같은 활동을 반복 분류하지 않도록 UserDefaults에 결과를 캐시한다.
/// 목표 목록이 바뀌면(hash 변경) 캐시는 자동 무효화.
@MainActor
final class GoalActivityClassifier {

    // MARK: - Types

    struct Activity: Hashable, Sendable {
        let id: String
        let title: String
        let date: Date
        let kind: Kind
        let isCompleted: Bool

        enum Kind: String, Sendable { case event, todo }
    }

    struct Match: Sendable, Codable {
        let activityID: String
        let goalID: UUID?
        let source: Source

        enum Source: String, Sendable, Codable { case keyword, ai, none }
    }

    // MARK: - Cache

    private let cacheKey = "planit.goalActivity.cache"
    private let cacheHashKey = "planit.goalActivity.goalsHash"

    /// 목표 목록의 내용 기반 해시 (순서 무관).
    /// targets/keywords/title 중 하나라도 바뀌면 다른 해시.
    private func goalsHash(_ goals: [ChatGoal]) -> String {
        let parts = goals.map { goal -> String in
            let targets = goal.targets.sorted().joined(separator: ",")
            let kws = goal.keywords.sorted().joined(separator: ",")
            return "\(goal.id.uuidString):\(goal.title):\(targets):\(kws)"
        }.sorted().joined(separator: "|")
        return String(parts.hashValue)
    }

    private func loadCache(for goals: [ChatGoal]) -> [String: Match] {
        let defaults = UserDefaults.standard
        let currentHash = goalsHash(goals)
        let storedHash = defaults.string(forKey: cacheHashKey)
        guard storedHash == currentHash,
              let data = defaults.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: Match].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveCache(_ cache: [String: Match], for goals: [ChatGoal]) {
        let defaults = UserDefaults.standard
        defaults.set(goalsHash(goals), forKey: cacheHashKey)
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    /// 캐시를 강제로 비운다 (목표 리스트 변경 등).
    func invalidateCache() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: cacheKey)
        defaults.removeObject(forKey: cacheHashKey)
    }

    // MARK: - 키워드 매칭 (동기)

    /// keywords / targets 중 하나라도 활동 제목에 포함되면 해당 목표로 매칭.
    /// 여러 목표가 매칭될 경우 첫 번째 — 나중에 점수화로 개선 가능.
    nonisolated func classifyByKeyword(_ activity: Activity, against goals: [ChatGoal]) -> Match {
        for goal in goals {
            let hit = goal.keywords.contains { kw in
                activity.title.localizedCaseInsensitiveContains(kw)
            } || goal.targets.contains { t in
                activity.title.localizedCaseInsensitiveContains(t)
            }
            if hit {
                return Match(activityID: activity.id, goalID: goal.id, source: .keyword)
            }
        }
        return Match(activityID: activity.id, goalID: nil, source: .none)
    }

    // MARK: - 통합 분류 (키워드 → AI fallback)

    /// 활동들을 일괄 분류한다.
    /// - 캐시 적중: 바로 반환 (AI 호출 없음)
    /// - 키워드 매칭: 즉시 결과에 추가
    /// - 미매칭: 5개씩 묶어 Claude로 배치 분류
    /// 결과는 캐시에 저장되어 다음 호출 시 재사용된다.
    func classify(_ activities: [Activity], against goals: [ChatGoal]) async -> [Match] {
        guard !goals.isEmpty, !activities.isEmpty else {
            return activities.map { Match(activityID: $0.id, goalID: nil, source: .none) }
        }

        var cache = loadCache(for: goals)
        var results: [Match] = []
        var pendingAI: [Activity] = []

        for activity in activities {
            if let cached = cache[activity.id] {
                results.append(cached)
                continue
            }
            let quick = classifyByKeyword(activity, against: goals)
            if quick.goalID != nil {
                cache[activity.id] = quick
                results.append(quick)
            } else {
                pendingAI.append(activity)
            }
        }

        if !pendingAI.isEmpty {
            let aiMatches = await classifyByAI(pendingAI, against: goals)
            for match in aiMatches {
                cache[match.activityID] = match
            }
            results.append(contentsOf: aiMatches)
        }

        saveCache(cache, for: goals)
        return results
    }

    // MARK: - AI 분류 (Claude CLI)

    private func classifyByAI(_ activities: [Activity], against goals: [ChatGoal]) async -> [Match] {
        guard let claudePath = AIService.findClaudePath() else {
            return activities.map { Match(activityID: $0.id, goalID: nil, source: .none) }
        }

        let batchSize = 5
        var results: [Match] = []
        for batch in activities.chunked(into: batchSize) {
            let batchResults = await classifyBatch(batch, against: goals, claudePath: claudePath)
            results.append(contentsOf: batchResults)
        }
        return results
    }

    private func classifyBatch(
        _ activities: [Activity],
        against goals: [ChatGoal],
        claudePath: String
    ) async -> [Match] {
        let prompt = buildPrompt(activities: activities, goals: goals)
        let raw = await Task.detached {
            AIService.runClaudeOneShot(prompt: prompt, claudePath: claudePath)
        }.value
        return parseResponse(raw, activities: activities, goals: goals)
    }

    // MARK: - 프롬프트 / 응답 파싱

    private func buildPrompt(activities: [Activity], goals: [ChatGoal]) -> String {
        var lines: [String] = []
        lines.append("아래 활동들이 어떤 장기 목표와 관련있는지 분류하세요.")
        lines.append("관련 없으면 goal_id를 null로 두세요. 추측하지 마세요 — 명확히 관련 있어야만 매칭.")
        lines.append("")
        lines.append("목표 목록:")
        for goal in goals {
            let targets = goal.targets.joined(separator: ", ")
            let kws = goal.keywords.prefix(8).joined(separator: ", ")
            lines.append("- id=\(goal.id.uuidString) / title=\"\(goal.title)\" / targets=[\(targets)] / keywords=[\(kws)]")
        }
        lines.append("")
        lines.append("활동 목록:")
        for a in activities {
            lines.append("- id=\"\(a.id)\" / kind=\(a.kind.rawValue) / title=\"\(a.title)\"")
        }
        lines.append("")
        lines.append("JSON 배열만 출력. 예:")
        lines.append(#"[{"activity_id":"...","goal_id":"..."}, {"activity_id":"...","goal_id":null}]"#)
        return lines.joined(separator: "\n")
    }

    private func parseResponse(_ raw: String, activities: [Activity], goals: [ChatGoal]) -> [Match] {
        // 응답에서 첫 JSON 배열 블록 추출
        let fallback = activities.map { Match(activityID: $0.id, goalID: nil, source: .none) }
        guard let jsonText = extractJSONArray(from: raw) else { return fallback }

        struct Entry: Decodable {
            let activity_id: String
            let goal_id: String?
        }
        guard let data = jsonText.data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return fallback
        }

        let goalIDs = Set(goals.map(\.id))
        let byActivity = Dictionary(uniqueKeysWithValues: entries.map { ($0.activity_id, $0) })

        return activities.map { activity -> Match in
            guard let entry = byActivity[activity.id],
                  let raw = entry.goal_id,
                  let uuid = UUID(uuidString: raw),
                  goalIDs.contains(uuid) else {
                return Match(activityID: activity.id, goalID: nil, source: .none)
            }
            return Match(activityID: activity.id, goalID: uuid, source: .ai)
        }
    }

    private func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "[") else { return nil }
        var depth = 0
        var idx = start
        while idx < text.endIndex {
            let c = text[idx]
            if c == "[" { depth += 1 }
            if c == "]" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...idx])
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
