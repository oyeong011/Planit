#if os(iOS)
import SwiftUI

// MARK: - Brand Colors (extended)
//
// M2 UI v4 (TimeBlocks 스타일)에서 월 타이틀/셀 숫자/이벤트 막대 라벨 전용 타이포 토큰 추가.
// v3 토큰(`calenDisplay`, `calenTitle`, `calenBody`, `calenCaption`)은 유지.

extension Color {
    /// Lighter tint for backgrounds / chips
    static let calenBlueTint   = Color.calenBlue.opacity(0.12)

    /// Subtle separator / surface
    static let calenSurface    = Color(red: 0.97, green: 0.97, blue: 0.99)

    /// Primary text (slightly softened)
    static let calenPrimary    = Color(red: 0.10, green: 0.10, blue: 0.12)

    /// Secondary text
    static let calenSecondary  = Color(red: 0.44, green: 0.44, blue: 0.50)
}

// MARK: - Typography

extension Font {
    /// Large display heading (e.g. 34 pt bold rounded)
    static let calenDisplay    = Font.system(size: 34, weight: .bold,   design: .rounded)

    /// Section / card title (e.g. 20 pt semibold)
    static let calenTitle      = Font.system(size: 20, weight: .semibold)

    /// Body text
    static let calenBody       = Font.system(size: 16, weight: .regular)

    /// Small caption / label
    static let calenCaption    = Font.system(size: 12, weight: .medium)

    // MARK: - v4 (TimeBlocks) Tokens

    /// 월간 상단 타이틀 ("2026년 4월"). 24pt bold rounded.
    static let calenMonthTitle = Font.system(size: 24, weight: .bold, design: .rounded)

    /// 월 그리드 셀 내부 날짜 숫자. 13pt medium.
    static let calenDayCellNumber = Font.system(size: 13, weight: .medium)

    /// 이벤트 막대(bar) 내부 라벨. 10pt medium, lineLimit 1 가정.
    static let calenEventBarLabel = Font.system(size: 10, weight: .medium)
}

// MARK: - Corner Radii

enum CalenRadius {
    static let small:  CGFloat = 8
    static let medium: CGFloat = 12
    static let large:  CGFloat = 16
    static let card:   CGFloat = 20
}

// MARK: - Shadows

extension View {
    /// Soft card shadow used throughout the app. v4에서 opacity 0.08 → 0.05로 완화.
    func calenCardShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    /// Stronger shadow for floating action elements.
    func calenFloatingShadow() -> some View {
        self.shadow(color: Color.calenBlue.opacity(0.30), radius: 20, x: 0, y: 8)
    }
}
#endif
