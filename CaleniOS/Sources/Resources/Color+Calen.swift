#if os(iOS)
import SwiftUI

// MARK: - Brand & Semantic Colors
//
// 레퍼런스: `Calen-iOS/Calen/Resources/Color+Calen.swift` 그대로 이식.
// Planit iOS(=CaleniOS)의 브랜드 팔레트 + 카테고리 컬러 6개.
// CalendarEvent.colorHex 디코딩 경로는 `Utilities/Color+Hex.swift`가 별도 제공.

extension Color {
    /// Primary brand blue used across buttons, accents, and the app identity.
    static let calenBlue = Color(red: 0.23, green: 0.51, blue: 0.96)

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
}
#endif
