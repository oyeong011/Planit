#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Color(hex:)
//
// `CalendarEvent.colorHex` (예: "#3366CC") → `SwiftUI.Color` 변환 헬퍼.
// macOS `Planit/PlatformShims.swift`의 `Color.toHex()`와 **정확한 역방향**이다.
// (저쪽은 sRGB 성분 → "#RRGGBB", 이쪽은 "#RRGGBB" → sRGB `Color`.)
//
// 지원 포맷: "#RGB", "#RRGGBB", "#AARRGGBB", 그리고 '#' 없는 동일 형식.
// 파싱에 실패하면 기본값(`#6699FF` — macOS 쪽과 동일한 fallback)을 사용한다.
extension Color {
    init(hex: String) {
        let fallback: (r: Double, g: Double, b: Double, a: Double) = (
            0x66 / 255.0,
            0x99 / 255.0,
            0xFF / 255.0,
            1.0
        )

        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        cleaned = cleaned.uppercased()

        // "RGB" → "RRGGBB"
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else {
            self.init(.sRGB, red: fallback.r, green: fallback.g, blue: fallback.b, opacity: fallback.a)
            return
        }

        let r, g, b, a: Double
        switch cleaned.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
            a = 1.0
        case 8:
            a = Double((value >> 24) & 0xFF) / 255.0
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        default:
            r = fallback.r; g = fallback.g; b = fallback.b; a = fallback.a
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
#endif
