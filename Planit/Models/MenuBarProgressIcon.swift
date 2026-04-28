import AppKit

enum MenuBarProgressIcon {
    static func makeImage(snapshot: MenuBarProgressSnapshot, updateAvailable: Bool) -> NSImage {
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size, flipped: false, drawingHandler: { bounds in
            draw(snapshot: snapshot, updateAvailable: updateAvailable, in: bounds)
            return true
        })
        image.isTemplate = false
        return image
    }

    private static func draw(snapshot: MenuBarProgressSnapshot, updateAvailable: Bool, in bounds: NSRect) {
        NSColor.clear.setFill()
        NSBezierPath(rect: bounds).fill()

        let bodyRect = NSRect(x: 2.0, y: 3.5, width: 21.0, height: 11.0)
        let capRect = NSRect(x: 24.0, y: 6.5, width: 2.6, height: 5.0)
        let cornerRadius: CGFloat = 3.2

        let strokeColor = NSColor.labelColor.withAlphaComponent(snapshot.state == .active ? 0.88 : 0.48)
        let fillColor = fillColor(for: snapshot)

        NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)
            .stroke(with: strokeColor, lineWidth: 1.4)
        NSBezierPath(roundedRect: capRect, xRadius: 1.0, yRadius: 1.0)
            .fill(with: strokeColor.withAlphaComponent(0.70))

        if let percent = snapshot.percent {
            let fraction = CGFloat(max(0, min(percent, 100))) / 100.0
            let innerRect = bodyRect.insetBy(dx: 2.1, dy: 2.2)
            let fillWidth = max(1.8, innerRect.width * fraction)
            let fillRect = NSRect(x: innerRect.minX, y: innerRect.minY, width: fillWidth, height: innerRect.height)
            NSBezierPath(roundedRect: fillRect, xRadius: 1.8, yRadius: 1.8)
                .fill(with: fillColor)
        } else {
            let center = NSPoint(x: bodyRect.midX, y: bodyRect.midY)
            let dotRadius: CGFloat = 1.25
            NSBezierPath(ovalIn: NSRect(
                x: center.x - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
            .fill(with: strokeColor.withAlphaComponent(0.50))
        }

        if updateAvailable {
            NSBezierPath(ovalIn: NSRect(x: 20.2, y: 11.0, width: 5.0, height: 5.0))
                .fill(with: NSColor.systemPink)
        }
    }

    private static func fillColor(for snapshot: MenuBarProgressSnapshot) -> NSColor {
        guard let percent = snapshot.percent else {
            return NSColor.secondaryLabelColor
        }

        switch percent {
        case 100...:
            return NSColor.systemGreen
        case 67..<100:
            return NSColor.systemMint
        case 34..<67:
            return NSColor.systemBlue
        default:
            return NSColor.systemOrange
        }
    }
}

private extension NSBezierPath {
    func stroke(with color: NSColor, lineWidth: CGFloat) {
        color.setStroke()
        self.lineWidth = lineWidth
        stroke()
    }

    func fill(with color: NSColor) {
        color.setFill()
        fill()
    }
}
