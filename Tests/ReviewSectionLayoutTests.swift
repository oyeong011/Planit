import CoreGraphics
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
}
