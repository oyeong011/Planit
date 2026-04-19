import SwiftUI

struct CalendarTheme: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let primaryHex: String
    let secondaryHex: String
    let accentHex: String
    let eventTintHex: String
    let backgroundOverlayHex: String

    var primary: Color { Color(hex: primaryHex) ?? .blue }
    var secondary: Color { Color(hex: secondaryHex) ?? .secondary }
    var accent: Color { Color(hex: accentHex) ?? .purple }
    var eventTint: Color { Color(hex: eventTintHex) ?? primary }
    var backgroundOverlay: Color { Color(hex: backgroundOverlayHex) ?? primary }

    var swatchHexes: [String] {
        [primaryHex, secondaryHex, accentHex, eventTintHex, backgroundOverlayHex]
    }

    /// 테마의 대표 그라데이션 (primary → accent).
    /// 버튼, 오늘 날짜 원형 하이라이트, 배너 등 강조 요소에 사용.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 전체 앱 배경에 얹는 옅은 틴트.
    /// 다크/라이트 모드를 해치지 않도록 opacity를 낮춰서 사용한다.
    var subtleBackgroundTint: Color { backgroundOverlay.opacity(0.16) }

    /// 패널(일정 리스트, 월간 그리드) 배경에 얹는 아주 옅은 accent 틴트.
    /// 시스템 기본 배경 위에 추가로 오버레이하는 용도 — opacity 0.035로 가독성 보존.
    var paneTint: Color { accent.opacity(0.04) }

    /// 카드(설정, 리뷰 카드) 배경에 얹는 옅은 테마 틴트.
    var cardTint: Color { accent.opacity(0.03) }

    static let builtIn: [CalendarTheme] = [
        CalendarTheme(
            id: "classic",
            name: "Classic",
            primaryHex: "#3F5EFB",
            secondaryHex: "#6D7A99",
            accentHex: "#7C3AED",
            eventTintHex: "#3366CC",
            backgroundOverlayHex: "#EAF0FF"
        ),
        CalendarTheme(
            id: "ocean",
            name: "Ocean",
            primaryHex: "#006D77",
            secondaryHex: "#4B7F86",
            accentHex: "#00818A",
            eventTintHex: "#0077B6",
            backgroundOverlayHex: "#DDF5F7"
        ),
        CalendarTheme(
            id: "sunset",
            name: "Sunset",
            primaryHex: "#B54708",
            secondaryHex: "#8A5A44",
            accentHex: "#C2410C",
            eventTintHex: "#D97706",
            backgroundOverlayHex: "#FFF1E6"
        ),
        CalendarTheme(
            id: "forest",
            name: "Forest",
            primaryHex: "#207A4D",
            secondaryHex: "#52665A",
            accentHex: "#2F855A",
            eventTintHex: "#3A7D44",
            backgroundOverlayHex: "#E7F5EC"
        ),
        CalendarTheme(
            id: "mono",
            name: "Mono",
            primaryHex: "#404040",
            secondaryHex: "#737373",
            accentHex: "#525252",
            eventTintHex: "#595959",
            backgroundOverlayHex: "#F0F0F0"
        ),
        CalendarTheme(
            id: "sakura",
            name: "Sakura",
            primaryHex: "#A7355E",
            secondaryHex: "#8A6473",
            accentHex: "#BE185D",
            eventTintHex: "#DB2777",
            backgroundOverlayHex: "#FCE7F3"
        ),
        CalendarTheme(
            id: "pantone-classic-blue",
            name: "Pantone Classic Blue",
            primaryHex: "#0F4C81",
            secondaryHex: "#496982",
            accentHex: "#1D5F95",
            eventTintHex: "#0D5C9B",
            backgroundOverlayHex: "#E3EEF7"
        ),
        CalendarTheme(
            id: "pantone-illuminating",
            name: "Pantone Illuminating",
            primaryHex: "#F5DF4D",
            secondaryHex: "#8A7A28",
            accentHex: "#7A5F00",
            eventTintHex: "#9A6B00",
            backgroundOverlayHex: "#FFF7C2"
        ),
        CalendarTheme(
            id: "pantone-ultimate-gray",
            name: "Pantone Ultimate Gray",
            primaryHex: "#939597",
            secondaryHex: "#62666A",
            accentHex: "#555A60",
            eventTintHex: "#6A6D70",
            backgroundOverlayHex: "#EFEFEF"
        ),
        CalendarTheme(
            id: "pantone-very-peri",
            name: "Pantone Very Peri",
            primaryHex: "#6667AB",
            secondaryHex: "#4D4C7D",
            accentHex: "#5454A6",
            eventTintHex: "#5A5BC4",
            backgroundOverlayHex: "#ECECFA"
        ),
        CalendarTheme(
            id: "pantone-viva-magenta",
            name: "Pantone Viva Magenta",
            primaryHex: "#BB2649",
            secondaryHex: "#7B3044",
            accentHex: "#A2143A",
            eventTintHex: "#C32148",
            backgroundOverlayHex: "#FBE7ED"
        ),
        CalendarTheme(
            id: "pantone-peach-fuzz",
            name: "Pantone Peach Fuzz",
            primaryHex: "#FFBE98",
            secondaryHex: "#A65F3B",
            accentHex: "#B85C38",
            eventTintHex: "#C65D2E",
            backgroundOverlayHex: "#FFF0E8"
        ),
        CalendarTheme(
            id: "pantone-mocha-mousse",
            name: "Pantone Mocha Mousse",
            primaryHex: "#A47864",
            secondaryHex: "#6E5248",
            accentHex: "#7B4B3B",
            eventTintHex: "#8A5B4A",
            backgroundOverlayHex: "#F3E8E1"
        ),
        CalendarTheme(
            id: "pantone-cloud-dancer",
            name: "Pantone Cloud Dancer",
            primaryHex: "#F0EEE9",
            secondaryHex: "#8B8378",
            accentHex: "#5F5A52",
            eventTintHex: "#7D756B",
            backgroundOverlayHex: "#F8F6F0"
        )
    ]

    static let fallback = builtIn[0]
}
