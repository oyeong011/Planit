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
