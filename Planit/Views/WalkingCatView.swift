import SwiftUI

// MARK: - Lane Container

struct WalkingCatView: View {
    @State private var xPos: CGFloat = 20
    @State private var goRight = true
    @State private var phase: Double = 0

    static let laneHeight: CGFloat = 32
    private let catW: CGFloat = 38
    private let catH: CGFloat = 24
    private let speed: CGFloat = 52    // pt/sec
    private let walkHz: Double = 2.6   // walk cycle frequency

    private let tick = Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            CatCanvas(phase: phase, facingRight: goRight)
                .frame(width: catW, height: catH)
                .offset(x: xPos, y: Self.laneHeight - catH)
                .frame(width: geo.size.width, height: Self.laneHeight, alignment: .topLeading)
                .clipped()
                .onReceive(tick) { _ in
                    advance(totalWidth: geo.size.width)
                }
        }
        .frame(height: Self.laneHeight)
    }

    private func advance(totalWidth: CGFloat) {
        phase += walkHz / 30
        let dx = speed / 30
        var next = xPos + (goRight ? dx : -dx)
        let maxX = totalWidth - catW - 6
        if next > maxX { next = maxX; goRight = false }
        else if next < 6 { next = 6; goRight = true }
        xPos = next
    }
}

// MARK: - Cat Canvas (pure SwiftUI, no images)

private struct CatCanvas: View {
    var phase: Double
    var facingRight: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // Mirror horizontally for left-facing direction
            var c = ctx
            if !facingRight {
                c.translateBy(x: w, y: 0)
                c.scaleBy(x: -1, y: 1)
            }

            let isDark = scheme == .dark
            let body  = isDark ? Color(white: 0.92) : Color(red: 0.28, green: 0.23, blue: 0.21)
            let pupil = isDark ? Color(white: 0.10) : Color(white: 0.98)

            let step = CGFloat(phase.truncatingRemainder(dividingBy: 1.0))
            let s      = CGFloat(sin(Double(step) * .pi * 2))
            let bob    = abs(s) * 1.3          // 0..1.3 pt upward on each step
            let swing  = s * 0.30              // ±17° leg swing (rad)

            // ── Tail ──────────────────────────────────────────────
            var tail = Path()
            tail.move(to:    pt(5,  h*0.67 - bob))
            tail.addCurve(
                to:          pt(9,  h*0.13 - bob),
                control1:    pt(0,  h*0.42 - bob),
                control2:    pt(0,  h*0.13 - bob)
            )
            tail.addQuadCurve(
                to:          pt(14, h*0.16 - bob),
                control:     pt(12, h*0.02 - bob)
            )
            c.stroke(tail, with: .color(body),
                     style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

            // ── Back legs (behind body) ───────────────────────────
            let bHip = pt(11, h*0.79 - bob)
            drawLeg(&c, hip: bHip, swing: swing * 0.75,  len: 5, col: body.opacity(0.45), lw: 3.1)
            drawLeg(&c, hip: pt(bHip.x + 2, bHip.y), swing: -swing * 0.75, len: 5, col: body, lw: 3.1)

            // ── Body ─────────────────────────────────────────────
            c.fill(Path(ellipseIn: CGRect(x: 4, y: h*0.43 - bob, width: 22, height: 10)),
                   with: .color(body))

            // ── Front legs (in front of body) ────────────────────
            let fHip = pt(21, h*0.79 - bob)
            drawLeg(&c, hip: fHip, swing: -swing, len: 5, col: body.opacity(0.45), lw: 3.1)
            drawLeg(&c, hip: pt(fHip.x + 2, fHip.y), swing: swing, len: 5, col: body, lw: 3.1)

            // ── Head ─────────────────────────────────────────────
            let hx: CGFloat = 26, hy = h*0.33 - bob, hr: CGFloat = 5.5
            c.fill(Path(ellipseIn: CGRect(x: hx-hr, y: hy-hr, width: hr*2, height: hr*2)),
                   with: .color(body))

            // ── Ears ─────────────────────────────────────────────
            drawTri(&c,
                p1: pt(hx-5,   hy-3.5-bob), p2: pt(hx-2,   hy-hr-3-bob), p3: pt(hx+1, hy-3.5-bob),
                col: body)
            drawTri(&c,
                p1: pt(hx+0.5, hy-3.5-bob), p2: pt(hx+4.5, hy-hr-3-bob), p3: pt(hx+hr, hy-3-bob),
                col: body)

            // ── Eye (pupil dot) ───────────────────────────────────
            c.fill(Path(ellipseIn: CGRect(x: hx+1.5, y: hy-0.5-bob, width: 2.6, height: 2.6)),
                   with: .color(pupil))
        }
    }

    // Helpers (inout required: GraphicsContext is a mutating value type)
    private func drawLeg(_ c: inout GraphicsContext,
                         hip: CGPoint, swing: CGFloat, len: CGFloat,
                         col: Color, lw: CGFloat) {
        var p = Path()
        p.move(to: hip)
        p.addLine(to: CGPoint(x: hip.x + sin(swing) * len,
                              y: hip.y + cos(swing) * len))
        c.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: lw, lineCap: .round))
    }

    private func drawTri(_ c: inout GraphicsContext,
                         p1: CGPoint, p2: CGPoint, p3: CGPoint, col: Color) {
        var t = Path()
        t.move(to: p1); t.addLine(to: p2); t.addLine(to: p3); t.closeSubpath()
        c.fill(t, with: .color(col))
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}
