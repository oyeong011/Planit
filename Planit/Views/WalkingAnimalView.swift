import AppKit
import SwiftUI

struct WalkingAnimalView: View {
    static let laneHeight: CGFloat = 64

    @ObservedObject private var settings = AnimalSettings.shared
    @State private var xPos: CGFloat = 6
    @State private var isMovingRight = true
    @State private var frameIndex = 0
    @State private var frameElapsed: TimeInterval = 0

    private static let animalSize: CGFloat = 56
    private static let speed: CGFloat = 50
    private static let boundaryInset: CGFloat = 6
    private static let tickDuration: TimeInterval = 1.0 / 30.0
    private static let frameDuration: TimeInterval = 1.0 / 12.0

    private let tick = Timer.publish(every: Self.tickDuration, on: .main, in: .common).autoconnect()

    var body: some View {
        if settings.isEnabled {
            GeometryReader { geo in
                currentFrame
                    .frame(width: Self.animalSize, height: Self.animalSize)
                    .scaleEffect(x: isMovingRight ? 1 : -1, y: 1)
                    .offset(x: xPos, y: Self.laneHeight - Self.animalSize)
                    .animation(.linear(duration: Self.tickDuration), value: xPos)
                    .frame(width: geo.size.width, height: Self.laneHeight, alignment: .topLeading)
                    .clipped()
                    .onReceive(tick) { _ in
                        advance(totalWidth: geo.size.width, style: settings.selectedStyle)
                    }
                    .onChange(of: settings.selectedStyle) { _, style in
                        frameIndex %= style.frameCount
                    }
            }
            .frame(height: Self.laneHeight)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var currentFrame: some View {
        if let image = AnimalSpriteImageCache.shared.image(style: settings.selectedStyle, frameIndex: frameIndex) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }

    private func advance(totalWidth: CGFloat, style: WalkingAnimalStyle) {
        let next = Self.advancedState(
            from: MotionState(
                xPos: xPos,
                isMovingRight: isMovingRight,
                frameIndex: frameIndex,
                frameElapsed: frameElapsed
            ),
            totalWidth: totalWidth,
            frameCount: style.frameCount
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
        frameCount: Int,
        tickDuration: TimeInterval = Self.tickDuration
    ) -> MotionState {
        var nextState = state
        let safeFrameCount = max(1, frameCount)
        nextState.frameElapsed += tickDuration

        while nextState.frameElapsed >= Self.frameDuration {
            nextState.frameElapsed -= Self.frameDuration
            nextState.frameIndex = (nextState.frameIndex + 1) % safeFrameCount
        }

        guard totalWidth > 0 else {
            return nextState
        }

        let dx = Self.speed * CGFloat(tickDuration)
        let minX = Self.boundaryInset
        let maxX = max(minX, totalWidth - Self.animalSize - Self.boundaryInset)
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
}

final class AnimalSpriteImageCache {
    static let shared = AnimalSpriteImageCache()
    private var cache: [String: NSImage] = [:]

    func image(style: WalkingAnimalStyle, frameIndex: Int) -> NSImage? {
        image(named: style.frameResourceName(for: frameIndex))
    }

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Animals"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache[name] = image
        return image
    }
}
