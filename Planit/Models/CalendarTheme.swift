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
        )
    ]

    static let fallback = builtIn[0]
}
