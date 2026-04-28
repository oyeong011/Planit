#if os(iOS)
import SwiftUI

// MARK: - CalenTheme (v0.2 — 14 테마 5색, Sprint A)
//
// 사용자 등록 시안의 14 테마 × 5색 (primary / secondary / accent / eventTint / bgOverlay).
// 이전 v0.1.2 의 3색 모델(primary/accent/surface)을 5색으로 확장하면서, 기존 호출처
// (`.surface`)는 `bgOverlay` 로 alias 처리해 호환을 유지한다.

struct CalenTheme: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let primaryHex: String
    let secondaryHex: String
    let accentHex: String
    let eventTintHex: String
    let bgOverlayHex: String

    var primary:    Color { Color(hex: primaryHex) }
    var secondary:  Color { Color(hex: secondaryHex) }
    var accent:     Color { Color(hex: accentHex) }
    var eventTint:  Color { Color(hex: eventTintHex) }
    var bgOverlay:  Color { Color(hex: bgOverlayHex) }

    /// v0.1.2 호환 — 기존 `.surface` 호출처를 위한 alias.
    var surface: Color { bgOverlay }

    /// 카드/패널 tint — light 모드는 bgOverlay 35%, dark 모드는 accent 10%.
    var cardTint: Color {
        Color(
            light: Color(hex: bgOverlayHex).opacity(0.35),
            dark:  Color(hex: accentHex).opacity(0.10)
        )
    }

    /// primary → accent 그라데이션 — FAB / 강조 요소용.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - 14 등록 테마

    static let builtIn: [CalenTheme] = [
        CalenTheme(id: "classic",                name: "Classic",
                   primaryHex: "#3F5EFB", secondaryHex: "#6D7A99",
                   accentHex:  "#7C3AED", eventTintHex: "#3366CC",
                   bgOverlayHex: "#EAF0FF"),
        CalenTheme(id: "ocean",                  name: "Ocean",
                   primaryHex: "#006D77", secondaryHex: "#4B7F86",
                   accentHex:  "#00818A", eventTintHex: "#0077B6",
                   bgOverlayHex: "#DDF5F7"),
        CalenTheme(id: "sunset",                 name: "Sunset",
                   primaryHex: "#B54708", secondaryHex: "#8A5A44",
                   accentHex:  "#C2410C", eventTintHex: "#D97706",
                   bgOverlayHex: "#FFF1E6"),
        CalenTheme(id: "forest",                 name: "Forest",
                   primaryHex: "#207A4D", secondaryHex: "#52665A",
                   accentHex:  "#2F855A", eventTintHex: "#3A7D44",
                   bgOverlayHex: "#E7F5EC"),
        CalenTheme(id: "mono",                   name: "Mono",
                   primaryHex: "#404040", secondaryHex: "#737373",
                   accentHex:  "#525252", eventTintHex: "#595959",
                   bgOverlayHex: "#F0F0F0"),
        CalenTheme(id: "sakura",                 name: "Sakura",
                   primaryHex: "#A7355E", secondaryHex: "#8A6473",
                   accentHex:  "#BE185D", eventTintHex: "#DB2777",
                   bgOverlayHex: "#FCE7F3"),
        CalenTheme(id: "pantone-classic-blue",   name: "Pantone Classic Blue",
                   primaryHex: "#0F4C81", secondaryHex: "#496982",
                   accentHex:  "#1D5F95", eventTintHex: "#0D5C9B",
                   bgOverlayHex: "#E3EEF7"),
        CalenTheme(id: "pantone-illuminating",   name: "Pantone Illuminating",
                   primaryHex: "#F5DF4D", secondaryHex: "#8A7A28",
                   accentHex:  "#7A5F00", eventTintHex: "#9A6B00",
                   bgOverlayHex: "#FFF7C2"),
        CalenTheme(id: "pantone-ultimate-gray",  name: "Pantone Ultimate Gray",
                   primaryHex: "#939597", secondaryHex: "#62666A",
                   accentHex:  "#555A60", eventTintHex: "#6A6D70",
                   bgOverlayHex: "#EFEFEF"),
        CalenTheme(id: "pantone-very-peri",      name: "Pantone Very Peri",
                   primaryHex: "#6667AB", secondaryHex: "#4D4C7D",
                   accentHex:  "#5454A6", eventTintHex: "#5A5BC4",
                   bgOverlayHex: "#ECECFA"),
        CalenTheme(id: "pantone-viva-magenta",   name: "Pantone Viva Magenta",
                   primaryHex: "#BB2649", secondaryHex: "#7B3044",
                   accentHex:  "#A2143A", eventTintHex: "#C32148",
                   bgOverlayHex: "#FBE7ED"),
        CalenTheme(id: "pantone-peach-fuzz",     name: "Pantone Peach Fuzz",
                   primaryHex: "#FFBE98", secondaryHex: "#A65F3B",
                   accentHex:  "#B85C38", eventTintHex: "#C65D2E",
                   bgOverlayHex: "#FFF0E8"),
        CalenTheme(id: "pantone-mocha-mousse",   name: "Pantone Mocha Mousse",
                   primaryHex: "#A47864", secondaryHex: "#6E5248",
                   accentHex:  "#7B4B3B", eventTintHex: "#8A5B4A",
                   bgOverlayHex: "#F3E8E1"),
        CalenTheme(id: "pantone-cloud-dancer",   name: "Pantone Cloud Dancer",
                   primaryHex: "#F0EEE9", secondaryHex: "#8B8378",
                   accentHex:  "#5F5A52", eventTintHex: "#7D756B",
                   bgOverlayHex: "#F8F6F0"),
    ]

    static let fallback = builtIn[0]

    // MARK: - 시안 카드 톤 (Figma Section 1 / Home.png 정확 추출, v0.6)
    //
    // 일정 카드는 모두 라이트 블루 계열로 통일하고, 카테고리는 좌측 라인 아이콘과
    // 카드 안 라벨로 구분한다. 저녁식사만 따뜻한 톤(연한 핑크/크림)으로 살짝 변주.
    enum CardTone {
        /// 기상(Wake) — 카드 미사용 inline 텍스트, 안내 색
        static let morning  = Color(light: Color(hex: "#F0F6FF"), dark: Color(hex: "#1A2545"))
        /// 직장(업무) — 진한 라이트 블루
        static let work     = Color(light: Color(hex: "#DBE7F7"), dark: Color(hex: "#1F2A3F"))
        /// 거래처 회의 — 연한 라이트 블루
        static let meeting  = Color(light: Color(hex: "#EBF2FB"), dark: Color(hex: "#212A3D"))
        /// 저녁식사 — 매우 연한 핑크 (카테고리 변주용)
        static let dinner   = Color(light: Color(hex: "#F8E7E7"), dark: Color(hex: "#3A2828"))
    }

    /// SAT 파랑 / SUN 빨강 (한국식 캘린더 컨벤션).
    enum WeekdayColor {
        static let saturday = Color(hex: "#2B8BDA")
        static let sunday   = Color(hex: "#E94B4B")
    }
}
#endif
