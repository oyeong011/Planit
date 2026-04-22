import AppKit
import SwiftUI

struct WalkingCatView: View {
    static let laneHeight: CGFloat = 36

    @State private var xPos: CGFloat = 6
    @State private var isMovingRight = true
    @State private var frameIndex = 0
    @State private var frames: [Image] = WalkingCatView.loadFrames()
    @ObservedObject private var catSettings = CatSettings.shared

    private static let frameCount = 8
    private static let catSize: CGFloat = 44
    private static let speed: CGFloat = 50
    private static let boundaryInset: CGFloat = 6

    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    @ViewBuilder
    var body: some View {
        if !catSettings.catEnabled {
            EmptyView()
        } else {
            GeometryReader { geo in
                currentFrame
                    .resizable()
                    .colorMultiply(catTintColor ?? .white)
                    .frame(width: Self.catSize, height: Self.catSize)
                    .scaleEffect(x: isMovingRight ? 1 : -1, y: 1)
                    .offset(x: xPos, y: Self.laneHeight - Self.catSize)
                    .frame(width: geo.size.width, height: Self.laneHeight, alignment: .topLeading)
                    .clipped()
                    .onReceive(tick) { _ in
                        advance(totalWidth: geo.size.width)
                    }
            }
            .frame(height: Self.laneHeight)
        }
    }

    private var currentFrame: Image {
        frames[frameIndex]
    }

    private var catTintColor: Color? {
        guard !catSettings.catTint.isEmpty else { return nil }
        return Color(hex: catSettings.catTint)
    }

    private func advance(totalWidth: CGFloat) {
        frameIndex = (frameIndex + 1) % Self.frameCount

        guard totalWidth > 0 else {
            return
        }

        let dx = Self.speed / 30.0
        let minX = Self.boundaryInset
        let maxX = max(minX, totalWidth - Self.catSize - Self.boundaryInset)
        var next = xPos + (isMovingRight ? dx : -dx)

        if next >= maxX {
            next = maxX
            isMovingRight = false
        } else if next <= minX {
            next = minX
            isMovingRight = true
        }

        xPos = next
    }

    private static func loadFrames() -> [Image] {
        let prefersRetina = (NSScreen.main?.backingScaleFactor ?? 1.0) >= 2.0

        return (1...frameCount).map { frameNumber in
            let baseName = "frame_R\(frameNumber)"

            if prefersRetina, let image = loadImage(named: "\(baseName)@2x") {
                return image
            }

            if let image = loadImage(named: baseName) {
                return image
            }

            if !prefersRetina, let image = loadImage(named: "\(baseName)@2x") {
                return image
            }

            return Image(nsImage: NSImage(size: NSSize(width: catSize, height: catSize)))
        }
    }

    private static func loadImage(named name: String) -> Image? {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        return Image(nsImage: image)
    }
}
