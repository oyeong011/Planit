import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Platform Color Shims
//
// 모든 View에서 `Color(nsColor: ...)` 대신 플랫폼 독립적인 색상을 사용합니다.
// macOS → NSColor semantics, iOS → UIColor semantics

extension Color {
    /// 컨트롤 배경 (macOS: controlBackgroundColor, iOS: secondarySystemBackground)
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }

    /// 윈도우/화면 배경 (macOS: windowBackgroundColor, iOS: systemBackground)
    static var platformWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(.systemBackground)
        #else
        Color.clear
        #endif
    }

    /// 일반 컨트롤 색상 (macOS: controlColor, iOS: systemFill)
    static var platformControl: Color {
        #if os(macOS)
        Color(nsColor: .controlColor)
        #elseif os(iOS)
        Color(.systemFill)
        #else
        Color.secondary.opacity(0.16)
        #endif
    }

    /// 텍스트 입력 배경 (macOS: textBackgroundColor, iOS: secondarySystemBackground)
    static var platformTextBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #elseif os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }
}

// MARK: - Platform Font Shims

extension Font {
    static func platformSystem(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    static var platformSmallLabel: Font {
        .platformSystem(size: 11, weight: .medium)
    }

    static var platformMonospacedCaption: Font {
        .platformSystem(size: 10, design: .monospaced)
    }
}

// MARK: - Platform Keyboard Shims

enum PlatformShortcut {
    static var primaryModifier: EventModifiers {
        .command
    }

    static var primaryModifierSymbol: String {
        #if os(macOS)
        "⌘"
        #else
        "Command"
        #endif
    }

    static var submitKey: KeyEquivalent {
        .return
    }
}

// MARK: - Platform URL Opening

/// 외부 URL을 시스템 기본 브라우저/앱으로 엽니다.
func openURL(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.open(url)
    #elseif os(iOS)
    UIApplication.shared.open(url)
    #else
    _ = url
    #endif
}

// MARK: - Platform File and Pasteboard Helpers

func showInFileManager(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    #elseif os(iOS)
    UIApplication.shared.open(url)
    #else
    _ = url
    #endif
}

func copyTextToPasteboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #elseif os(iOS)
    UIPasteboard.general.string = text
    #else
    _ = text
    #endif
}

// MARK: - Platform Notifications

extension Notification.Name {
    static let calenPopoverDidClose = Notification.Name("calenPopoverDidClose")
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
        #elseif os(iOS)
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return "#6699FF" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return "#6699FF"
        #endif
    }
}
