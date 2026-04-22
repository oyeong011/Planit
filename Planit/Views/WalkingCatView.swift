import SwiftUI

// MARK: - Lane Container

struct WalkingCatView: View {
    @State private var xPos: CGFloat = 20
    @State private var goRight = true
    @State private var phase: Double = 0

    static let laneHeight: CGFloat = 34
    private let catW: CGFloat = 44
    private let catH: CGFloat = 30
    private let speed: CGFloat = 48
    private let walkHz: Double = 2.4

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
        if next > totalWidth - catW - 6 { next = totalWidth - catW - 6; goRight = false }
        else if next < 6 { next = 6; goRight = true }
        xPos = next
    }
}

// MARK: - Cat Canvas

private struct CatCanvas: View {
    var phase: Double
    var facingRight: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            let w = size.width, h = size.height

            // Mirror for left-facing
            if !facingRight {
                c.translateBy(x: w, y: 0)
                c.scaleBy(x: -1, y: 1)
            }

            let isDark   = scheme == .dark
            // Cat fur colour
            let fur      = isDark ? Color(white: 0.93) : Color(red: 0.26, green: 0.22, blue: 0.20)
            // Inner ear / markings
            let innerEar = isDark ? Color(red: 1.0, green: 0.72, blue: 0.72)
                                  : Color(red: 0.85, green: 0.55, blue: 0.55)
            // Eye colours
            let eyeWhite = isDark ? Color(white: 0.10) : Color(white: 0.97)
            let pupil    = isDark ? Color(white: 0.88) : Color(white: 0.08)

            // Animation
            let s    = CGFloat(sin(phase.truncatingRemainder(dividingBy: 1) * .pi * 2))
            let bob  = abs(s) * 1.4               // body bobs up each step
            let swing = s * 0.32                  // ±18° primary leg swing

            // ── Tail ──────────────────────────────────────────────────
            var tail = Path()
            tail.move(to:    p(7,  h*0.64 - bob))
            tail.addCurve(
                to:          p(10, h*0.11 - bob),
                control1:    p(0,  h*0.38 - bob),
                control2:    p(0,  h*0.11 - bob))
            tail.addQuadCurve(
                to:          p(15, h*0.15 - bob),
                control:     p(13, h*0.00 - bob))
            c.stroke(tail, with: .color(fur),
                     style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))

            // ── Back legs (far, behind body) ──────────────────────────
            let bHip = p(13, h*0.77 - bob)
            drawLeg(&c, hip: bHip, swing:  swing*0.7, fur: fur.opacity(0.40))
            drawLeg(&c, hip: p(bHip.x + 2.5, bHip.y), swing: -swing*0.7, fur: fur.opacity(0.75))

            // ── Body ──────────────────────────────────────────────────
            c.fill(Path(ellipseIn: CGRect(x: 5,  y: h*0.42 - bob,
                                          width: 26, height: 13)), with: .color(fur))

            // ── Front legs (near, in front of body) ───────────────────
            let fHip = p(25, h*0.77 - bob)
            drawLeg(&c, hip: fHip,              swing: -swing,     fur: fur.opacity(0.40))
            drawLeg(&c, hip: p(fHip.x + 2.5, fHip.y), swing: swing, fur: fur)

            // ── Head ──────────────────────────────────────────────────
            let hx: CGFloat = 31, hy = h*0.30 - bob, hr: CGFloat = 8.5
            c.fill(Path(ellipseIn: CGRect(x: hx-hr, y: hy-hr,
                                           width: hr*2, height: hr*2)), with: .color(fur))

            // ── Ears (outer) ──────────────────────────────────────────
            drawTri(&c,
                p1: p(hx-7,    hy-5 - bob),
                p2: p(hx-3.5,  hy-hr-3.5 - bob),
                p3: p(hx+0.5,  hy-5 - bob),
                col: fur)
            drawTri(&c,
                p1: p(hx+0.5,  hy-5 - bob),
                p2: p(hx+5,    hy-hr-4 - bob),
                p3: p(hx+hr-0.5, hy-4.5 - bob),
                col: fur)

            // ── Ears (inner pink) ─────────────────────────────────────
            drawTri(&c,
                p1: p(hx-5.5,  hy-5.5 - bob),
                p2: p(hx-3,    hy-hr-1 - bob),
                p3: p(hx-0.5,  hy-5.5 - bob),
                col: innerEar)
            drawTri(&c,
                p1: p(hx+1,    hy-5.5 - bob),
                p2: p(hx+4.5,  hy-hr-1.5 - bob),
                p3: p(hx+hr-2, hy-5 - bob),
                col: innerEar)

            // ── Eye ───────────────────────────────────────────────────
            // Outer eye (white/dark)
            let ex = hx + 3.5, ey = hy - 0.5 - bob
            c.fill(Path(ellipseIn: CGRect(x: ex-3, y: ey-2.5, width: 6, height: 5)),
                   with: .color(eyeWhite))
            // Pupil
            c.fill(Path(ellipseIn: CGRect(x: ex-1.5, y: ey-2, width: 3, height: 4)),
                   with: .color(pupil))
            // Highlight dot
            c.fill(Path(ellipseIn: CGRect(x: ex+0.5, y: ey-1.5, width: 1.2, height: 1.2)),
                   with: .color(eyeWhite.opacity(0.9)))

            // ── Nose ──────────────────────────────────────────────────
            drawTri(&c,
                p1: p(hx+hr-1.5, hy+1 - bob),
                p2: p(hx+hr+0.5, hy-0.5 - bob),
                p3: p(hx+hr+0.5, hy+2 - bob),
                col: innerEar)

            // ── Whiskers ──────────────────────────────────────────────
            let wx = hx + hr - 1, wy = hy + 1.5 - bob
            for (dx, dy, angle) in [(CGFloat(5), CGFloat(-2.5), CGFloat(-0.2)),
                                     (5.5, 0, 0),
                                     (5, 2.5, 0.2)] {
                var wh = Path()
                wh.move(to: p(wx, wy))
                wh.addLine(to: p(wx + dx * cos(angle) - dy * sin(angle),
                                  wy + dx * sin(angle) + dy * cos(angle)))
                c.stroke(wh, with: .color(fur.opacity(0.55)),
                         style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            }
        }
    }

    // Two-segment leg: thigh + shin + rounded paw
    private func drawLeg(_ c: inout GraphicsContext, hip: CGPoint, swing: CGFloat, fur: Color) {
        let thighLen: CGFloat = 4.5
        let shinLen:  CGFloat = 4.5
        let pawR:     CGFloat = 2.2

        // Thigh
        let knee = CGPoint(x: hip.x + sin(swing) * thighLen,
                           y: hip.y + cos(swing) * thighLen)
        // Shin hangs roughly vertical, slight counter-swing for knee-bend look
        let shinSwing = -swing * 0.45
        let ankle = CGPoint(x: knee.x + sin(shinSwing) * shinLen,
                            y: knee.y + cos(shinSwing) * shinLen)

        var leg = Path()
        leg.move(to: hip)
        leg.addLine(to: knee)
        leg.addLine(to: ankle)
        c.stroke(leg, with: .color(fur),
                 style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

        // Paw (small filled oval at ankle)
        c.fill(Path(ellipseIn: CGRect(x: ankle.x - pawR,    y: ankle.y - pawR * 0.7,
                                       width: pawR * 2,      height: pawR * 1.4)),
               with: .color(fur))
    }

    private func drawTri(_ c: inout GraphicsContext,
                          p1: CGPoint, p2: CGPoint, p3: CGPoint, col: Color) {
        var t = Path()
        t.move(to: p1); t.addLine(to: p2); t.addLine(to: p3); t.closeSubpath()
        c.fill(t, with: .color(col))
    }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}
