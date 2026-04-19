import Foundation

// MARK: - PlanningSummaryMath
//
// PlanningMemoryService 요약 생성에서 쓰이는 플랫폼 중립 pure math helper.
// Goal/Habit/CalendarEvent 같은 도메인 타입을 직접 import하지 않기 위해,
// 호출부에서 숫자만 추려 넘긴다.
//
// M1 Step 5 — 순수 함수만 Shared로 승격 (파일 I/O는 macOS에 유지).
public enum PlanningSummaryMath {

    /// 주간 계획 완료/이동/건너뜀 경향 비율.
    public struct WeeklyTendency: Equatable, Sendable {
        public let completionRate: Double   // 0...1
        public let moveFraction: Double     // 0...1
        public let skipFraction: Double     // 0...1

        public init(completionRate: Double, moveFraction: Double, skipFraction: Double) {
            self.completionRate = completionRate
            self.moveFraction = moveFraction
            self.skipFraction = skipFraction
        }

        public static let empty = WeeklyTendency(completionRate: 0, moveFraction: 0, skipFraction: 0)
    }

    /// 주간 플래닝 경향 계산 — plannedCount 합이 0이면 전부 0으로 반환.
    public static func weeklyTendency(
        totalPlanned: Int,
        totalDone: Int,
        totalMoved: Int,
        totalSkipped: Int
    ) -> WeeklyTendency {
        guard totalPlanned > 0 else { return .empty }
        return WeeklyTendency(
            completionRate: Double(totalDone)    / Double(totalPlanned),
            moveFraction:   Double(totalMoved)   / Double(totalPlanned),
            skipFraction:   Double(totalSkipped) / Double(totalPlanned)
        )
    }

    /// 활성 목표의 주간 목표 시간 합이 주간 용량(분) 대비 몇 % 쓰는지.
    /// capacity가 0 이하면 0을 반환.
    public static func weeklyLoadPercent(
        activeGoalMinutes: Double,
        weeklyCapacityMinutes: Double
    ) -> Double {
        guard weeklyCapacityMinutes > 0 else { return 0 }
        return activeGoalMinutes / weeklyCapacityMinutes
    }

    /// 긴 제목을 max자 이하로 ellipsis 처리 (요약 줄에서 공통 사용).
    public static func shortened(_ title: String, max: Int) -> String {
        guard title.count > max else { return title }
        return String(title.prefix(max)) + "…"
    }
}
