#if os(iOS)
import SwiftUI

// MARK: - CalenTheme (v0.1.2)
//
// iOS 브랜드 테마 모델. macOS `CalendarTheme`의 축소 이식판이다.
// macOS 원본은 primary/secondary/accent/eventTint/backgroundOverlay 5색을 다루고
// `Color.withBrightness` 등 macOS 전용 헬퍼에 의존하는데, iOS 버전은
// 홈/탭바/설정에 필요한 3색(primary, accent, surface)만 유지한다.
//
// 사용처:
//  - CustomTabBar 선택 탭 강조색
//  - HomeView FAB + "오늘 원형" 하이라이트
//  - SettingsView 카드 아이콘 배경
//  - EventEditSheet 선택 외곽선
//
// 테마 전환 시 `@Published` 구독으로 재렌더.

struct CalenTheme: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let primaryHex: String
    let accentHex: String
    let surfaceHex: String   // 카드/배경 tint 용 pastel

    var primary: Color { Color(hex: primaryHex) }
    var accent:  Color { Color(hex: accentHex) }
    var surface: Color { Color(hex: surfaceHex) }

    /// 카드/패널 tint — light 모드는 surface 25%, dark 모드는 시스템 surface 유지.
    var cardTint: Color {
        Color(
            light: Color(hex: surfaceHex).opacity(0.35),
            dark:  Color(hex: accentHex).opacity(0.10)
        )
    }

    /// primary → accent 그라데이션 — FAB/강조 요소용.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let builtIn: [CalenTheme] = [
        CalenTheme(id: "classic",  name: "Classic",   primaryHex: "#3B82F6", accentHex: "#6366F1", surfaceHex: "#EAF0FF"),
        CalenTheme(id: "ocean",    name: "Ocean",     primaryHex: "#006D77", accentHex: "#00818A", surfaceHex: "#DDF5F7"),
        CalenTheme(id: "sunset",   name: "Sunset",    primaryHex: "#EA580C", accentHex: "#DC2626", surfaceHex: "#FFF1E6"),
        CalenTheme(id: "forest",   name: "Forest",    primaryHex: "#2F855A", accentHex: "#3A7D44", surfaceHex: "#E7F5EC"),
        CalenTheme(id: "sakura",   name: "Sakura",    primaryHex: "#DB2777", accentHex: "#BE185D", surfaceHex: "#FCE7F3"),
        CalenTheme(id: "peri",     name: "Very Peri", primaryHex: "#6667AB", accentHex: "#5454A6", surfaceHex: "#ECECFA"),
        CalenTheme(id: "magenta",  name: "Magenta",   primaryHex: "#BB2649", accentHex: "#A2143A", surfaceHex: "#FBE7ED"),
        CalenTheme(id: "mocha",    name: "Mocha",     primaryHex: "#A47864", accentHex: "#7B4B3B", surfaceHex: "#F3E8E1"),
        CalenTheme(id: "mono",     name: "Mono",      primaryHex: "#525252", accentHex: "#404040", surfaceHex: "#F0F0F0")
    ]

    static let fallback = builtIn[0]
}
#endif
