import SwiftUI

// MARK: - Platform Color Shims
//
// 모든 View에서 `Color(nsColor: ...)` 대신 플랫폼 독립적인 색상을 사용합니다.
// macOS → NSColor semantics, iOS → UIColor semantics

extension Color {
    /// 컨트롤 배경 (macOS: controlBackgroundColor, iOS: secondarySystemBackground)
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    /// 윈도우/화면 배경 (macOS: windowBackgroundColor, iOS: systemBackground)
    static var platformWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    /// 일반 컨트롤 색상 (macOS: controlColor, iOS: systemFill)
    static var platformControl: Color {
        #if os(macOS)
        Color(nsColor: .controlColor)
        #else
        Color(.systemFill)
        #endif
    }

    /// 텍스트 입력 배경 (macOS: textBackgroundColor, iOS: secondarySystemBackground)
    static var platformTextBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

// MARK: - Platform URL Opening

/// 외부 URL을 시스템 기본 브라우저/앱으로 엽니다.
func openURL(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}

// MARK: - Color Hex Conversion

extension Color {
    /// Color → HEX 문자열 (#RRGGBB)
    func toHex() -> String {
        #if os(macOS)
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#6699FF" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return "#6699FF" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #endif
    }
}
