import CoreGraphics

struct ReviewSectionLayout: Equatable {
    let sectionSpacing: CGFloat
    let cardHorizontalInset: CGFloat
    let containerHorizontalInset: CGFloat
    let contentVerticalInset: CGFloat
    let actionHorizontalInset: CGFloat
    let actionVerticalInset: CGFloat

    static func forContainerSize(_ size: CGSize) -> ReviewSectionLayout {
        if size.width < 440 || size.height < 760 {
            return ReviewSectionLayout(
                sectionSpacing: 10,
                cardHorizontalInset: 10,
                containerHorizontalInset: 12,
                contentVerticalInset: 10,
                actionHorizontalInset: 12,
                actionVerticalInset: 8
            )
        }

        return ReviewSectionLayout(
            sectionSpacing: 12,
            cardHorizontalInset: 12,
            containerHorizontalInset: 14,
            contentVerticalInset: 12,
            actionHorizontalInset: 14,
            actionVerticalInset: 10
        )
    }
}
