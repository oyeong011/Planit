#if os(iOS)
import SwiftUI

// MARK: - Brand & Semantic Colors
//
// M2 UI v4 (TimeBlocks 스타일 월간+주확장)에서 카테고리 소프트 변형 및 크림 배경 추가.
// 기본 `cardXxx` 컬러 6개는 v3 타임라인/리스트 카드에서 계속 사용되지만,
// 월 그리드의 이벤트 막대(bar)는 더 흐린 톤(`*Soft`)을 사용해 시각적 노이즈를 줄인다.

extension Color {
    /// Primary brand blue used across buttons, accents, and the app identity.
    static let calenBlue = Color(red: 0.23, green: 0.51, blue: 0.96)

    // MARK: - Category Cards (솔리드 — 타임라인/리스트 카드 배경용)

    /// Schedule card color for `.work` items (pink).
    static let cardWork = Color(red: 0.96, green: 0.40, blue: 0.57)

    /// Schedule card color for `.meeting` items (Calen blue).
    static let cardMeeting = Color.calenBlue

    /// Schedule card color for `.meal` items (yellow).
    static let cardMeal = Color(red: 0.98, green: 0.77, blue: 0.19)

    /// Schedule card color for `.exercise` items (green).
    static let cardExercise = Color(red: 0.25, green: 0.78, blue: 0.52)

    /// Schedule card color for `.personal` items (purple).
    static let cardPersonal = Color(red: 0.60, green: 0.36, blue: 0.91)

    /// Schedule card color for `.general` items (neutral gray).
    static let cardGeneral = Color(red: 0.56, green: 0.56, blue: 0.58)

    // MARK: - Soft Variants (v4 월 그리드 이벤트 bar용 — 파스텔톤)

    /// Soft pink — `.work` 막대용 (saturation ↓)
    static let cardWorkSoft     = Color(red: 0.97, green: 0.60, blue: 0.72)
    /// Soft blue — `.meeting` 막대용
    static let cardMeetingSoft  = Color(red: 0.49, green: 0.70, blue: 0.99)
    /// Soft yellow — `.meal` 막대용
    static let cardMealSoft     = Color(red: 0.99, green: 0.85, blue: 0.40)
    /// Soft green — `.exercise` 막대용
    static let cardExerciseSoft = Color(red: 0.48, green: 0.85, blue: 0.66)
    /// Soft purple — `.personal` 막대용
    static let cardPersonalSoft = Color(red: 0.73, green: 0.57, blue: 0.96)
    /// Soft gray — `.general` 막대용
    static let cardGeneralSoft  = Color(red: 0.74, green: 0.74, blue: 0.76)

    // MARK: - Planit-style category fills (v9 — 옅은 파스텔 background)

    /// Planit 톤 핑크 fill — `.work` (Dinner/Important 패턴)
    static let categoryFillWork     = Color(
        light: Color(red: 1.00, green: 0.87, blue: 0.90),
        dark:  Color(red: 0.36, green: 0.18, blue: 0.24)
    )
    /// Planit 톤 옅은 파랑 fill — `.meeting` (Family/Meeting 패턴)
    static let categoryFillMeeting  = Color(
        light: Color(red: 0.86, green: 0.90, blue: 1.00),
        dark:  Color(red: 0.18, green: 0.24, blue: 0.40)
    )
    /// Planit 톤 옅은 노랑 fill — `.meal` (Bank/Daily 패턴)
    static let categoryFillMeal     = Color(
        light: Color(red: 1.00, green: 0.93, blue: 0.78),
        dark:  Color(red: 0.36, green: 0.30, blue: 0.16)
    )
    /// Planit 톤 옅은 녹색 fill — `.exercise`
    static let categoryFillExercise = Color(
        light: Color(red: 0.84, green: 0.94, blue: 0.88),
        dark:  Color(red: 0.16, green: 0.32, blue: 0.24)
    )
    /// Planit 톤 옅은 보라 fill — `.personal` (Work/Friends 패턴)
    static let categoryFillPersonal = Color(
        light: Color(red: 0.88, green: 0.85, blue: 0.97),
        dark:  Color(red: 0.24, green: 0.20, blue: 0.40)
    )
    /// Planit 톤 옅은 베이지/회색 fill — `.general` (Cafe 패턴)
    static let categoryFillGeneral  = Color(
        light: Color(red: 0.92, green: 0.91, blue: 0.92),
        dark:  Color(red: 0.24, green: 0.24, blue: 0.26)
    )

    // MARK: - Backgrounds (v9 라벤더 톤)

    /// Planit 톤 옅은 라벤더-블루 배경 (#EFF1FB). 다크모드에선 시스템 배경 유지.
    static let calenCream = Color(
        light: Color(red: 0.94, green: 0.95, blue: 0.98),
        dark:  Color(red: 0.07, green: 0.07, blue: 0.08)
    )

    /// 셀/카드 표면 배경 (month grid 셀 기본). 순백.
    static let calenCardSurface = Color(
        light: Color.white,
        dark:  Color(red: 0.12, green: 0.12, blue: 0.14)
    )
}

// MARK: - Light/Dark Color helper

extension Color {
    /// light/dark 분기 Color 헬퍼. `UIColor(dynamicProvider:)` 기반.
    init(light: Color, dark: Color) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
#endif
