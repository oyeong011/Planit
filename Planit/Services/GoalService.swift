import Foundation
import Combine

@MainActor
final class GoalService: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var profile: UserProfile = UserProfile()
    @Published var completions: [String: CompletionRecord] = [:]  // eventId → record
    @Published var dailyMetrics: [String: DailyMetrics] = [:]     // "yyyy-MM-dd" → metrics

    private let dataDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dataDir = support.appendingPathComponent("Planit/goals", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        loadAll()
    }

    // MARK: - Persistence

    private func loadAll() {
        goals = load("goals.json") ?? []
        profile = load("profile.json") ?? UserProfile()
        completions = load("completions.json") ?? [:]
        dailyMetrics = load("metrics.json") ?? [:]
    }

    private func load<T: Decodable>(_ filename: String) -> T? {
        let url = dataDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.planitDecoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = dataDir.appendingPathComponent(filename)
        guard let data = try? JSONEncoder.planitEncoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func saveGoals() { save(goals, to: "goals.json") }
    func saveProfile() { save(profile, to: "profile.json") }
    func saveCompletions() { save(completions, to: "completions.json") }
    func saveMetrics() { save(dailyMetrics, to: "metrics.json") }

    // MARK: - Goal CRUD

    func addGoal(_ goal: Goal) {
        goals.append(goal)
        saveGoals()
    }

    func updateGoal(_ goal: Goal) {
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
            saveGoals()
        }
    }

    func deleteGoal(_ id: String) {
        goals.removeAll { $0.id == id || $0.parentId == id }
        saveGoals()
    }

    func activeGoals(level: GoalLevel? = nil) -> [Goal] {
        goals.filter { $0.status == .active && (level == nil || $0.level == level) }
    }

    func childGoals(of parentId: String) -> [Goal] {
        goals.filter { $0.parentId == parentId && $0.status == .active }
    }

    // MARK: - Completion Tracking

    func markCompletion(eventId: String, eventTitle: String? = nil, goalId: String?, status: CompletionStatus, plannedMinutes: Int) {
        let record = CompletionRecord(eventId: eventId, eventTitle: eventTitle, goalId: goalId, date: Date(),
                                       status: status, plannedMinutes: plannedMinutes)
        completions[eventId] = record
        saveCompletions()
        updateDailyMetrics(for: Date())
    }

    func completionFor(eventId: String) -> CompletionRecord? {
        completions[eventId]
    }

    func removeCompletion(eventId: String) {
        guard let record = completions.removeValue(forKey: eventId) else { return }
        saveCompletions()
        updateDailyMetrics(for: record.date)
    }

    // MARK: - Daily Metrics

    private func updateDailyMetrics(for date: Date) {
        let key = Self.dateKey(date)
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }

        let dayRecords = completions.values.filter {
            $0.date >= dayStart && $0.date < dayEnd
        }

        let metrics = DailyMetrics(
            date: dayStart,
            plannedCount: dayRecords.count,
            completedCount: dayRecords.filter { $0.status == .done }.count,
            movedCount: dayRecords.filter { $0.status == .moved }.count,
            skippedCount: dayRecords.filter { $0.status == .skipped }.count,
            totalPlannedMinutes: dayRecords.reduce(0) { $0 + $1.plannedMinutes },
            totalActualMinutes: dayRecords.compactMap(\.actualMinutes).reduce(0, +)
        )
        dailyMetrics[key] = metrics
        saveMetrics()
    }

    static func dateKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return fmt.string(from: date)
    }

    // MARK: - Progress

    enum CompletionPeriod { case day, week, month, year }

    func completionRate(for period: CompletionPeriod) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from: Date
        switch period {
        case .day:   from = today
        case .week:  from = cal.date(byAdding: .day, value: -7, to: today) ?? today
        case .month: from = cal.date(byAdding: .month, value: -1, to: today) ?? today
        case .year:  from = cal.date(byAdding: .year, value: -1, to: today) ?? today
        }
        let records = completions.values.filter { $0.date >= from }
        guard !records.isEmpty else { return 0 }
        let done = records.filter { $0.status == .done }.count
        return Double(done) / Double(records.count)
    }

    func weeklyCompletionRate() -> Double { completionRate(for: .week) }

    func goalProgress(_ goalId: String) -> (hoursPlanned: Double, hoursActual: Double) {
        let records = completions.values.filter { $0.goalId == goalId }
        let planned = records.reduce(0) { $0 + Double($1.plannedMinutes) } / 60.0
        let actual = records.compactMap(\.actualMinutes).reduce(0) { $0 + Double($1) } / 60.0
        return (planned, actual)
    }

    func daysUntilDeadline(_ goal: Goal) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: goal.dueDate).day ?? 0
    }

    func weeklyDeficit(for goal: Goal) -> Int {
        guard let rec = goal.recurrence else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return 0 }
        let done = completions.values
            .filter { $0.goalId == goal.id && $0.date >= weekStart && $0.status == .done }
            .count
        return max(0, rec.weeklyTargetSessions - done)
    }
}

// MARK: - JSON Coders

extension JSONEncoder {
    static let planitEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let planitDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
