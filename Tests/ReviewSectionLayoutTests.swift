import CoreGraphics
import Foundation
import Testing
@testable import Calen

@Suite("ReviewSectionLayout")
struct ReviewSectionLayoutTests {
    @Test("uses compact metrics when width is tight")
    func compactLayoutForTightWidth() {
        let layout = ReviewSectionLayout.forContainerSize(CGSize(width: 430, height: 820))

        #expect(layout.sectionSpacing == 10)
        #expect(layout.cardHorizontalInset == 10)
        #expect(layout.containerHorizontalInset == 12)
        #expect(layout.actionHorizontalInset == 12)
        #expect(layout.actionVerticalInset == 8)
    }

    @Test("uses compact metrics when height is tight")
    func compactLayoutForTightHeight() {
        let layout = ReviewSectionLayout.forContainerSize(CGSize(width: 540, height: 700))

        #expect(layout.sectionSpacing == 10)
        #expect(layout.cardHorizontalInset == 10)
        #expect(layout.contentVerticalInset == 10)
    }

    @Test("uses regular metrics only when both dimensions have room")
    func regularLayoutForLargeContainer() {
        let layout = ReviewSectionLayout.forContainerSize(CGSize(width: 560, height: 820))

        #expect(layout.sectionSpacing == 12)
        #expect(layout.cardHorizontalInset == 12)
        #expect(layout.containerHorizontalInset == 14)
        #expect(layout.actionHorizontalInset == 14)
        #expect(layout.actionVerticalInset == 10)
    }

    @Test("layout decisions are pure for equal inputs")
    func layoutIsPure() {
        let first = ReviewSectionLayout.forContainerSize(CGSize(width: 560, height: 820))
        let second = ReviewSectionLayout.forContainerSize(CGSize(width: 560, height: 820))

        #expect(first == second)
    }

    @Test("review tab excludes statistics-owned sections")
    func reviewTabExcludesStatisticsOwnedSections() throws {
        let source = try projectFile("Planit/Views/ReviewView.swift")
        let enumStart = try #require(source.range(of: "enum ReviewSectionID"))
        let enumEnd = try #require(source.range(of: "private enum ReviewSheetRoute"))
        let enumSource = String(source[enumStart.lowerBound..<enumEnd.lowerBound])

        #expect(!enumSource.contains("habit_graph"))
        #expect(!enumSource.contains("weekly_chart"))
        #expect(!enumSource.contains("todo_grass"))
        #expect(!enumSource.contains("\"progress\""))
        #expect(!enumSource.contains("\"category\""))
        #expect(enumSource.contains("my_habits"))
        #expect(enumSource.contains("long_term_goals"))
        #expect(source.contains("static let defaultOrder: [ReviewSectionID] = [\n        .myHabits, .longTermGoals\n    ]"))
    }

    @Test("legacy review section order drops removed statistics and keeps surviving order")
    func legacyReviewSectionOrderDropsRemovedStatisticsAndKeepsSurvivingOrder() {
        let migrated = ReviewSectionID.normalizedOrder(fromStoredRawValues: [
            "long_term_goals",
            "habit_graph",
            "progress",
            "my_habits",
            "todo_grass"
        ])

        #expect(migrated == [.longTermGoals, .myHabits])
    }

    @Test("legacy review section order falls back when only removed statistics remain")
    func legacyReviewSectionOrderFallsBackWhenOnlyRemovedStatisticsRemain() {
        let migrated = ReviewSectionID.normalizedOrder(fromStoredRawValues: [
            "habit_graph",
            "weekly_chart",
            "progress"
        ])

        #expect(migrated == ReviewSectionID.defaultOrder)
    }
}

private func projectFile(_ path: String) throws -> String {
    try String(
        contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path),
        encoding: .utf8
    )
}
