import Foundation
import SwiftUI

// MARK: - Time Slot

struct ScheduleSlot: Equatable {
    let start: Date
    let end: Date

    var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }
}

// MARK: - Day Schedule Analysis

struct DayScheduleAnalysis {
    let date: Date
    let timedEvents: [CalendarEvent]   // 종일 이벤트 제외
    let freeSlots: [ScheduleSlot]           // 근무 시간 내 빈 슬롯

    var totalBusyMinutes: Int {
        timedEvents.reduce(0) { $0 + Int($1.endDate.timeIntervalSince($1.startDate) / 60) }
    }
    var totalFreeMinutes: Int {
        freeSlots.reduce(0) { $0 + $1.durationMinutes }
    }
    /// 근무 시간(10h) 대비 점유율 (0~100)
    var loadPercent: Int {
        let workdayMinutes = 10 * 60
        return min(100, totalBusyMinutes * 100 / workdayMinutes)
    }
    var loadLabel: String {
        switch loadPercent {
        case 0:       return "여유로움"
        case 1..<30:  return "여유"
        case 30..<60: return "보통"
        case 60..<80: return "빡빡"
        default:      return "꽉 참"
        }
    }
}

// MARK: - Smart Scheduler Service

/// 캘린더 이벤트를 분석해 여유 슬롯 탐색, 충돌 감지, 최적 배치 제안을 담당.
/// UI/ViewModel 의존성 없이 순수 계산만 수행.
final class SmartSchedulerService {

    // 근무 시간 범위 (기본: 09:00 ~ 19:00)
    var workdayStartHour: Int = 9
    var workdayEndHour: Int = 19

    private let calendar = Calendar.current

    // MARK: - Free Slot Analysis

    /// 특정 날짜의 근무 시간 내 빈 슬롯 목록 반환
    /// - Parameters:
    ///   - events: 전체 이벤트 목록
    ///   - date: 분석할 날짜
    ///   - minDurationMinutes: 이 시간 이상의 슬롯만 포함 (기본 15분)
    func findFreeSlots(in events: [CalendarEvent], on date: Date, minDurationMinutes: Int = 15) -> [ScheduleSlot] {
        guard let dayStart = calendar.date(bySettingHour: workdayStartHour, minute: 0, second: 0, of: date),
              let dayEnd   = calendar.date(bySettingHour: workdayEndHour,   minute: 0, second: 0, of: date) else {
            return []
        }

        // 해당 날짜의 시간 지정 이벤트만, 시작 시간순 정렬
        let dayEvents = events
            .filter { !$0.isAllDay && calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }

        var freeSlots: [ScheduleSlot] = []
        var cursor = dayStart

        for event in dayEvents {
            let evStart = max(event.startDate, dayStart)
            let evEnd   = min(event.endDate,   dayEnd)
            guard evEnd > dayStart else { continue }

            if evStart > cursor {
                let dur = Int(evStart.timeIntervalSince(cursor) / 60)
                if dur >= minDurationMinutes {
                    freeSlots.append(ScheduleSlot(start: cursor, end: evStart))
                }
            }
            cursor = max(cursor, evEnd)
        }

        if dayEnd > cursor {
            let dur = Int(dayEnd.timeIntervalSince(cursor) / 60)
            if dur >= minDurationMinutes {
                freeSlots.append(ScheduleSlot(start: cursor, end: dayEnd))
            }
        }

        return freeSlots
    }

    /// 여러 날짜에 대한 일정 밀도 분석
    func analyzeDays(events: [CalendarEvent], for dates: [Date]) -> [DayScheduleAnalysis] {
        dates.map { date in
            let timedEvents = events.filter {
                !$0.isAllDay && calendar.isDate($0.startDate, inSameDayAs: date)
            }
            let freeSlots = findFreeSlots(in: events, on: date)
            return DayScheduleAnalysis(date: date, timedEvents: timedEvents, freeSlots: freeSlots)
        }
    }

    // MARK: - Conflict Detection

    /// 새 이벤트의 시간대가 기존 이벤트와 겹치는지 확인
    func detectConflicts(start: Date, end: Date, in events: [CalendarEvent], excludingID: String? = nil) -> [CalendarEvent] {
        events.filter { event in
            guard !event.isAllDay else { return false }
            if let excludeID = excludingID, event.id == excludeID { return false }
            // 겹침: newStart < existingEnd AND newEnd > existingStart
            return start < event.endDate && end > event.startDate
        }
    }

    // MARK: - Best Slot Suggestion

    /// 주어진 조건에 맞는 최적 여유 슬롯 반환
    /// - Parameters:
    ///   - durationMinutes: 필요한 시간 (분)
    ///   - preferredDate: 선호 날짜 (nil이면 오늘부터 탐색)
    ///   - preferredTime: "morning" | "afternoon" | "evening" | nil
    ///   - searchDays: 탐색할 최대 일 수
    func suggestBestSlot(
        events: [CalendarEvent],
        durationMinutes: Int,
        preferredDate: Date? = nil,
        preferredTime: String? = nil,
        searchDays: Int = 7
    ) -> ScheduleSlot? {
        let startDate = preferredDate ?? Date()
        let duration = TimeInterval(durationMinutes * 60)

        for dayOffset in 0..<searchDays {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            // 오늘이면 현재 시각 이후 슬롯만 탐색
            let slots = findFreeSlots(in: events, on: date, minDurationMinutes: durationMinutes)
            let futureSlots = dayOffset == 0
                ? slots.filter { $0.start > Date() }
                : slots

            if let slot = pickSlot(from: futureSlots, duration: duration, preference: preferredTime) {
                return ScheduleSlot(start: slot.start, end: slot.start.addingTimeInterval(duration))
            }
        }
        return nil
    }

    private func pickSlot(from slots: [ScheduleSlot], duration: TimeInterval, preference: String?) -> ScheduleSlot? {
        let eligible = slots.filter { $0.end.timeIntervalSince($0.start) >= duration }
        guard !eligible.isEmpty else { return nil }

        let range: ClosedRange<Int>
        switch preference {
        case "morning":   range = 9...11
        case "afternoon": range = 13...16
        case "evening":   range = 17...18
        default:          range = 9...18
        }

        let preferred = eligible.filter { slot in
            let h = calendar.component(.hour, from: slot.start)
            return range.contains(h)
        }

        return (preferred.isEmpty ? eligible : preferred).first
    }

    // MARK: - Backlog Distribution (스마트 재배치)

    /// 미완료 todo를 향후 일정 여유에 따라 자동 분산 배치.
    ///
    /// - Parameters:
    ///   - todos: 미완료 + 기한 지난 todo 목록
    ///   - events: 향후 캘린더 이벤트 (밀도 계산용)
    ///   - startDate: 배치 시작일 (보통 내일)
    ///   - maxDays: 탐색 범위 (기본 7일)
    ///   - maxPerDay: 하루 최대 배정 개수 (기본 3개)
    /// - Returns: todo.id → 새 배정 날짜 매핑
    func distributeBacklog(
        todos: [TodoItem],
        events: [CalendarEvent],
        startDate: Date,
        maxDays: Int = 7,
        maxPerDay: Int = 3
    ) -> [UUID: Date] {
        guard !todos.isEmpty else { return [:] }

        let dates = (0..<maxDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: startDate))
        }

        // 날짜별 일정 밀도 분석 (loadPercent 낮을수록 여유)
        let analyses = analyzeDays(events: events, for: dates)

        // 긴급도 기준 todo 정렬: 오래 밀린 것 먼저 (date가 과거일수록 긴급)
        let sorted = todos.sorted { $0.date < $1.date }

        var result: [UUID: Date] = [:]
        var dailyCount: [Date: Int] = [:]

        for todo in sorted {
            // 밀도 낮은 날부터 탐색 → 할당 여유 있으면 배정
            let sortedDays = analyses.sorted { $0.loadPercent < $1.loadPercent }
            for analysis in sortedDays {
                let dayKey = calendar.startOfDay(for: analysis.date)
                let count = dailyCount[dayKey] ?? 0
                guard count < maxPerDay else { continue }

                result[todo.id] = analysis.date
                dailyCount[dayKey] = count + 1
                break
            }
        }

        // 7일 내 배치 못 한 todo → 마지막 날에 몰아넣기 (최악의 경우)
        if let lastDate = dates.last {
            for todo in sorted where result[todo.id] == nil {
                result[todo.id] = lastDate
            }
        }

        return result
    }

    /// distributeBacklog 결과를 사람이 읽기 좋은 요약 문자열로 변환
    func backlogSummary(plan: [UUID: Date], todos: [TodoItem]) -> String {
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "M/d(E)"
        dayFmt.locale = Locale(identifier: "ko_KR")
        dayFmt.timeZone = TimeZone(identifier: "Asia/Seoul")

        // 날짜별로 그룹
        var byDate: [Date: [String]] = [:]
        for (id, date) in plan {
            guard let todo = todos.first(where: { $0.id == id }) else { continue }
            let dayKey = calendar.startOfDay(for: date)
            byDate[dayKey, default: []].append(todo.title)
        }

        let lines = byDate.keys.sorted().map { dayKey -> String in
            let titles = byDate[dayKey]!
            let label = dayFmt.string(from: dayKey)
            if titles.count == 1 {
                return "\(label): \(titles[0])"
            } else {
                return "\(label): \(titles.count)개 할 일"
            }
        }
        return lines.joined(separator: " · ")
    }

    // MARK: - AI Context String

    /// AI 시스템 프롬프트에 삽입할 일정 밀도 + 여유 슬롯 텍스트 생성
    func buildScheduleContext(events: [CalendarEvent], for dates: [Date]) -> String {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.timeZone = TimeZone(identifier: "Asia/Seoul")

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "M/d(E)"
        dayFmt.locale = Locale(identifier: "ko_KR")
        dayFmt.timeZone = TimeZone(identifier: "Asia/Seoul")

        let analyses = analyzeDays(events: events, for: dates)
        var lines = ["=== 일정 밀도 & 여유 시간 ==="]

        for a in analyses {
            let label = dayFmt.string(from: a.date)
            let freeH = a.totalFreeMinutes / 60
            let freeM = a.totalFreeMinutes % 60
            let freeStr = freeM > 0 ? "\(freeH)h\(freeM)m" : "\(freeH)h"
            lines.append("\(label): 일정 \(a.timedEvents.count)개, 여유 \(freeStr) [\(a.loadLabel)]")

            for slot in a.freeSlots.prefix(4) {
                let dur = slot.durationMinutes
                let durStr = dur >= 60
                    ? "\(dur/60)h\(dur%60 > 0 ? "\(dur%60)m" : "")"
                    : "\(dur)m"
                lines.append("  └ \(timeFmt.string(from: slot.start))~\(timeFmt.string(from: slot.end)) (\(durStr))")
            }
        }

        return lines.joined(separator: "\n")
    }
}
