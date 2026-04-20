import Foundation

// MARK: - WeekEventLayout
//
// 월 그리드의 한 **주(week)**에 속한 이벤트들을 가로 막대(multi-day bar)로 배치하기 위한
// 순수 계산 helper. UI 레이어는 이 결과를 받아 ZStack에 absolute-positioned bar로 렌더한다.
//
// 핵심 개념:
// - 한 주는 7칸(columns 0...6). weekStart(일요일 또는 월요일 — caller 결정)에서 시작.
// - 이벤트가 주 범위 밖으로 걸치면 해당 경계에서 clip. continuesFromPrev/continuesToNext 플래그로
//   UI가 ◀/▶ 표시를 결정할 수 있게 한다.
// - 같은 주의 여러 이벤트는 lane(세로 슬롯)으로 쌓인다. lane 할당은 greedy: 시작 column 오름차순,
//   동점이면 긴 span 먼저(시각적 안정성).
// - maxVisibleLanes를 초과하는 이벤트는 hidden으로 분류. 각 column의 hidden count가 "+N" 뱃지 계산에 사용.
//
// Input 타입은 Schedule/CalendarEvent에 의존하지 않아 macOS 테스트 타깃에서도 검증 가능.

public enum WeekEventLayout {

    // MARK: - Input

    public struct Input: Sendable, Equatable {
        public let id: String
        public let startDate: Date
        public let endDate: Date
        public init(id: String, startDate: Date, endDate: Date) {
            self.id = id
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    // MARK: - Output

    public struct Placement: Sendable, Equatable {
        public let id: String
        public let lane: Int
        public let startColumn: Int          // 0...6
        public let spanColumns: Int          // 1...7 - startColumn
        public let continuesFromPrev: Bool
        public let continuesToNext: Bool
        public init(
            id: String,
            lane: Int,
            startColumn: Int,
            spanColumns: Int,
            continuesFromPrev: Bool,
            continuesToNext: Bool
        ) {
            self.id = id
            self.lane = lane
            self.startColumn = startColumn
            self.spanColumns = spanColumns
            self.continuesFromPrev = continuesFromPrev
            self.continuesToNext = continuesToNext
        }
    }

    public struct Result: Sendable, Equatable {
        public let placements: [Placement]
        /// column index(0...6) → hidden 이벤트 개수 (lane >= maxVisibleLanes).
        public let hiddenByColumn: [Int: Int]
        public init(placements: [Placement], hiddenByColumn: [Int: Int]) {
            self.placements = placements
            self.hiddenByColumn = hiddenByColumn
        }
    }

    // MARK: - Main API

    /// 주어진 이벤트들을 주 범위(weekStart 기준 7일)로 clip + lane 할당.
    ///
    /// - Parameters:
    ///   - events: 후보 이벤트들. 이 주와 무관한 이벤트는 내부에서 필터링된다.
    ///   - weekStart: 주의 첫 날 00:00.
    ///   - maxVisibleLanes: 렌더 가능한 lane 수(초과는 hidden).
    ///   - calendar: date 연산용 calendar.
    public static func layout(
        events: [Input],
        weekStart: Date,
        maxVisibleLanes: Int = 4,
        calendar: Calendar = .current
    ) -> Result {
        let weekStartOfDay = calendar.startOfDay(for: weekStart)
        guard let weekEndExclusive = calendar.date(byAdding: .day, value: 7, to: weekStartOfDay) else {
            return Result(placements: [], hiddenByColumn: [:])
        }

        // 1) 주 범위와 겹치는 이벤트만 필터 + column 계산
        struct Candidate {
            let id: String
            let startColumn: Int
            let endColumn: Int      // inclusive
            let continuesFromPrev: Bool
            let continuesToNext: Bool
        }

        let candidates: [Candidate] = events.compactMap { event in
            // 주와 전혀 겹치지 않으면 제외
            guard event.endDate > weekStartOfDay, event.startDate < weekEndExclusive else {
                return nil
            }
            // startColumn
            let startInWeek = max(event.startDate, weekStartOfDay)
            let continuesFromPrev = event.startDate < weekStartOfDay
            let startColumn = calendar.dateComponents([.day], from: weekStartOfDay,
                                                     to: calendar.startOfDay(for: startInWeek)).day ?? 0

            // endColumn (inclusive day index)
            // endDate가 exclusive 의미일 수도 있으나(Google all-day 관례), 여기서는 endDate 직전 날까지.
            // endDate == startDate 인 경우(1분 단위 이벤트) 같은 날짜로 처리.
            let effectiveEnd = min(event.endDate, weekEndExclusive)
            let continuesToNext = event.endDate > weekEndExclusive
            // effectiveEnd 가 정각(00:00)인 경우 그 날은 포함 안 되도록 1초 뺌
            let endAdjusted = calendar.date(byAdding: .second, value: -1, to: effectiveEnd) ?? effectiveEnd
            let endColumnRaw = calendar.dateComponents([.day], from: weekStartOfDay,
                                                      to: calendar.startOfDay(for: endAdjusted)).day ?? startColumn
            let endColumn = max(startColumn, min(6, endColumnRaw))

            return Candidate(
                id: event.id,
                startColumn: max(0, min(6, startColumn)),
                endColumn: endColumn,
                continuesFromPrev: continuesFromPrev,
                continuesToNext: continuesToNext
            )
        }

        // 2) 정렬: startColumn asc → span desc(긴 bar 먼저) → id asc(안정성)
        let sorted = candidates.sorted { a, b in
            if a.startColumn != b.startColumn { return a.startColumn < b.startColumn }
            let spanA = a.endColumn - a.startColumn
            let spanB = b.endColumn - b.startColumn
            if spanA != spanB { return spanA > spanB }
            return a.id < b.id
        }

        // 3) lane 할당: greedy
        // lanes[l]: 이 lane에 이미 배치된 column 범위들. 간단하게 lane의 "마지막 endColumn + 1" 추적 가능,
        // 하지만 gap 채우기를 지원하려면 range 집합을 관리해야 한다. TimeBlocks 레퍼런스도 gap 재사용을
        // 적극적으로 하지 않으므로 "lane의 next available startColumn"만 추적해도 시각적 품질 충분.
        var laneNextAvailable: [Int] = []  // lane index → next available column
        var allPlacements: [Placement] = []

        for c in sorted {
            // 가장 낮은 lane 중 해당 lane의 nextAvailable <= c.startColumn 인 첫 lane
            var chosenLane = -1
            for (idx, next) in laneNextAvailable.enumerated() {
                if next <= c.startColumn {
                    chosenLane = idx
                    break
                }
            }
            if chosenLane == -1 {
                chosenLane = laneNextAvailable.count
                laneNextAvailable.append(0)
            }
            laneNextAvailable[chosenLane] = c.endColumn + 1

            allPlacements.append(Placement(
                id: c.id,
                lane: chosenLane,
                startColumn: c.startColumn,
                spanColumns: c.endColumn - c.startColumn + 1,
                continuesFromPrev: c.continuesFromPrev,
                continuesToNext: c.continuesToNext
            ))
        }

        // 4) visible / hidden 분리
        let visible = allPlacements.filter { $0.lane < maxVisibleLanes }
        let hidden = allPlacements.filter { $0.lane >= maxVisibleLanes }

        // 5) hiddenByColumn: 각 column 에 hidden으로 분류된 이벤트 수
        var hiddenByColumn: [Int: Int] = [:]
        for p in hidden {
            for col in p.startColumn...(p.startColumn + p.spanColumns - 1) {
                hiddenByColumn[col, default: 0] += 1
            }
        }

        return Result(placements: visible, hiddenByColumn: hiddenByColumn)
    }
}
