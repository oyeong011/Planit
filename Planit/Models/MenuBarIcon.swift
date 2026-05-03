import AppKit

enum MenuBarIcon {
    static func makeImage(updateAvailable: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            drawStatusIcon(in: bounds)

            if updateAvailable {
                NSColor.systemPink.setFill()
                NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 5.2, y: bounds.maxY - 5.4, width: 4.8, height: 4.8))
                    .fill()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawStatusIcon(in bounds: NSRect) {
        guard let icon = statusIcon else {
            fallbackIcon?.draw(
                in: bounds.insetBy(dx: 1, dy: 1),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return
        }

        icon.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private static let statusIcon: NSImage? = {
        let image = NSImage(size: NSSize(width: 18, height: 18))

        for name in ["StatusBarIcon", "StatusBarIcon@2x"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let source = NSImage(contentsOf: url) else {
                continue
            }
            for representation in source.representations {
                representation.size = NSSize(width: 18, height: 18)
                image.addRepresentation(representation)
            }
        }

        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }()

    private static let fallbackIcon = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar")
}
