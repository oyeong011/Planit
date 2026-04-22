import AppKit
import SwiftUI

struct WalkingCatView: View {
    static let laneHeight: CGFloat = 36

    @State private var xPos: CGFloat = 6
    @State private var isMovingRight = true
    @State private var frameIndex = 0
    @State private var frameElapsed: TimeInterval = 0
    @State private var frames: [Image] = WalkingCatView.loadFrames()
    @ObservedObject private var catSettings = CatSettings.shared

    private static let frameCount = 8
    private static let catSize: CGFloat = 44
    private static let speed: CGFloat = 50
    private static let boundaryInset: CGFloat = 6
    private static let tickDuration: TimeInterval = 1.0 / 30.0
    private static let frameDuration: TimeInterval = 1.0 / 12.0

    private let tick = Timer.publish(every: Self.tickDuration, on: .main, in: .common).autoconnect()

    @ViewBuilder
    var body: some View {
        if !catSettings.catEnabled {
            EmptyView()
        } else {
            GeometryReader { geo in
                renderedFrame
                    .frame(width: Self.catSize, height: Self.catSize)
                    .scaleEffect(x: isMovingRight ? 1 : -1, y: 1)
                    .offset(x: xPos, y: Self.laneHeight - Self.catSize)
                    .animation(.linear(duration: Self.tickDuration), value: xPos)
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

    @ViewBuilder
    private var renderedFrame: some View {
        if let tint = catTintColor {
            currentFrame
                .resizable()
                .colorMultiply(tint)
        } else {
            currentFrame
                .resizable()
        }
    }

    private var catTintColor: Color? {
        guard !catSettings.catTint.isEmpty else { return nil }
        return Color(hex: catSettings.catTint)
    }

    private func advance(totalWidth: CGFloat) {
        let next = Self.advancedState(
            from: MotionState(
                xPos: xPos,
                isMovingRight: isMovingRight,
                frameIndex: frameIndex,
                frameElapsed: frameElapsed
            ),
            totalWidth: totalWidth
        )

        xPos = next.xPos
        isMovingRight = next.isMovingRight
        frameIndex = next.frameIndex
        frameElapsed = next.frameElapsed
    }

    struct MotionState {
        var xPos: CGFloat
        var isMovingRight: Bool
        var frameIndex: Int
        var frameElapsed: TimeInterval
    }

    static func advancedState(
        from state: MotionState,
        totalWidth: CGFloat,
        tickDuration: TimeInterval = Self.tickDuration
    ) -> MotionState {
        var nextState = state
        nextState.frameElapsed += tickDuration

        while nextState.frameElapsed >= Self.frameDuration {
            nextState.frameElapsed -= Self.frameDuration
            nextState.frameIndex = (nextState.frameIndex + 1) % Self.frameCount
        }

        guard totalWidth > 0 else {
            return nextState
        }

        let dx = Self.speed * CGFloat(tickDuration)
        let minX = Self.boundaryInset
        let maxX = max(minX, totalWidth - Self.catSize - Self.boundaryInset)
        var nextX = nextState.xPos + (nextState.isMovingRight ? dx : -dx)

        if nextX >= maxX {
            nextX = maxX
            nextState.isMovingRight = false
        } else if nextX <= minX {
            nextX = minX
            nextState.isMovingRight = true
        }

        nextState.xPos = nextX
        return nextState
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
