#if os(iOS)
import SwiftUI

// MARK: - Brand Colors (extended)
//
// 레퍼런스: `Calen-iOS/Calen/Components/Theme.swift` 그대로 이식.
// `Color.calenBlue`는 `Color+Calen.swift`에 정의됨 — 여기는 파생 세만틱 토큰 + 타이포 + 라디우스 + 그림자.

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
    /// Soft card shadow used throughout the app.
    func calenCardShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    /// Stronger shadow for floating action elements.
    func calenFloatingShadow() -> some View {
        self.shadow(color: Color.calenBlue.opacity(0.30), radius: 20, x: 0, y: 8)
    }
}
#endif
