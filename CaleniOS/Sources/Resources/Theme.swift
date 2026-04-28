#if os(iOS)
import SwiftUI

// MARK: - Brand Colors (extended)
//
// Sprint A — 14 테마 5색은 `CalenTheme.swift` 참고. 여기는 테마 무관 토큰.

extension Color {
    /// Lighter tint for backgrounds / chips (calenBlue 의존)
    static let calenBlueTint   = Color.calenBlue.opacity(0.12)

    /// Subtle separator / surface
    static let calenSurface    = Color(red: 0.97, green: 0.97, blue: 0.99)

    /// Primary text (slightly softened)
    static let calenPrimary    = Color(red: 0.10, green: 0.10, blue: 0.12)

    /// Secondary text
    static let calenSecondary  = Color(red: 0.44, green: 0.44, blue: 0.50)

    /// Tertiary / hint
    static let calenTertiary   = Color(red: 0.63, green: 0.65, blue: 0.68)

    /// Divider (1px line)
    static let calenDivider    = Color(light: Color(hex: "#E5E7EB"),
                                       dark:  Color(hex: "#2A2D33"))
}

// MARK: - Typography (Dynamic Type)
//
// Sprint A: 모든 폰트 토큰은 `Font.TextStyle` 기반으로 전환 — 사용자의 Dynamic Type
// 설정(xS / L / AX1 / AX3)에 자동 스케일링된다. 기존 `.system(size: N)` 호출처는
// 단계적으로 이 토큰들로 마이그레이션한다.

extension Font {

    // ── Display
    /// 라지 헤더 (예: 캘린더 화면 "Today's Schedule"). `.largeTitle.bold()`.
    static let calenDisplay     = Font.system(.largeTitle, design: .rounded).weight(.bold)

    // ── Title
    /// 카드 제목 / 화면 타이틀. `.title2.semibold`.
    static let calenTitle       = Font.system(.title2).weight(.semibold)

    /// 월간 헤더 ("2026년 4월"). `.title3.bold` rounded.
    static let calenMonthTitle  = Font.system(.title3, design: .rounded).weight(.bold)

    // ── Headline / Section
    /// 섹션 헤더. `.headline.semibold` (semibold는 headline 기본).
    static let calenSectionHeader = Font.headline

    // ── Body
    /// 일반 본문. `.body.regular`.
    static let calenBody        = Font.body

    /// 강조 본문. `.body.medium`.
    static let calenBodyEmph    = Font.body.weight(.medium)

    // ── Caption / Mono
    /// 시간 라벨 (8:00, 15:00). 숫자 정렬 위해 `.callout` + monospacedDigit.
    static let calenTimeMono    = Font.callout.weight(.medium).monospacedDigit()

    /// 작은 메타 텍스트. `.caption.medium`.
    static let calenCaption     = Font.caption.weight(.medium)

    // ── 호환 (v0.1.x)
    /// 월 그리드 셀 내부 날짜 숫자.
    static let calenDayCellNumber = Font.system(.footnote).weight(.medium)
    /// 이벤트 막대 라벨 — 작은 1줄.
    static let calenEventBarLabel = Font.system(.caption2).weight(.medium)
}

// MARK: - Corner Radii

enum CalenRadius {
    static let chip:    CGFloat = 6
    static let small:   CGFloat = 8
    static let medium:  CGFloat = 12
    static let large:   CGFloat = 16
    static let card:    CGFloat = 20
    static let tabbar:  CGFloat = 32
}

// MARK: - Spacing tokens

enum CalenSpacing {
    static let xs:  CGFloat = 4
    static let s:   CGFloat = 8
    static let m:   CGFloat = 12
    static let l:   CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    /// Custom TabBar 의 화면 하단 reserved 영역. iPhone safe area + 12pt margin.
    static let tabBarBottomReserved: CGFloat = 90
}

// MARK: - Shadows

extension View {
    /// Soft card shadow used throughout the app.
    func calenCardShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    /// Stronger shadow for floating action elements.
    func calenFloatingShadow() -> some View {
        self.shadow(color: Color.calenBlue.opacity(0.30), radius: 20, x: 0, y: 8)
    }
}

// MARK: - Iconography

enum CalenSymbol {
    // Tabbar
    static let home     = "house"
    static let calendar = "calendar"
    static let mic      = "mic.fill"
    static let chat     = "bubble.left"
    static let profile  = "person"

    // Schedule cards
    static let wakeUp   = "sun.max"
    static let work     = "building.2"
    static let meeting  = "person.crop.circle"
    static let dinner   = "fork.knife"
    static let drive    = "car"

    // Settings rows
    static let google   = "globe"
    static let cloud    = "icloud"
    static let theme    = "paintpalette"
    static let language = "character.bubble"
    static let bell     = "bell"
    static let info     = "info.circle"
}
#endif
