import SwiftUI

struct WalkingCatView: View {
    @State private var xPos: CGFloat
    @State private var facingRight: Bool = true
    @State private var frameIndex: Int = 0
    @State private var isWalking: Bool = true
    @State private var walkTimer: Timer? = nil
    @State private var pauseTimer: Timer? = nil

    let containerWidth: CGFloat
    let catSize: CGFloat = 48

    private let fps: TimeInterval = 1.0 / 10   // 10fps 걷기
    private let speed: CGFloat = 2.2            // px per frame
    private let rFrames: [NSImage] = Self.loadFrames(prefix: "R")
    private let lFrames: [NSImage] = Self.loadFrames(prefix: "L")

    init(containerWidth: CGFloat) {
        self.containerWidth = containerWidth
        self._xPos = State(initialValue: CGFloat.random(in: 60...(containerWidth - 60)))
    }

    var body: some View {
        currentFrameImage
            .frame(width: catSize, height: catSize)
            .offset(x: xPos - catSize / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { startWalking() }
            .onDisappear { stopTimers() }
    }

    // MARK: - Current Frame

    @ViewBuilder
    private var currentFrameImage: some View {
        let frames = facingRight ? rFrames : lFrames
        if !frames.isEmpty {
            let frame = frames[frameIndex % frames.count]
            Image(nsImage: frame)
                .resizable()
                .interpolation(.high)
                .frame(width: catSize, height: catSize)
        }
    }

    // MARK: - Animation Loop

    private func startWalking() {
        walkTimer = Timer.scheduledTimer(withTimeInterval: fps, repeats: true) { _ in
            guard isWalking else { return }
            tick()
        }
    }

    private func tick() {
        frameIndex = (frameIndex + 1) % 8

        let edge = catSize / 2 + 8
        if facingRight {
            xPos += speed
            if xPos >= containerWidth - edge {
                xPos = containerWidth - edge
                facingRight = false
                randomPause()
            }
        } else {
            xPos -= speed
            if xPos <= edge {
                xPos = edge
                facingRight = true
                randomPause()
            }
        }
    }

    private func randomPause() {
        guard Double.random(in: 0...1) < 0.5 else { return }
        isWalking = false
        frameIndex = 0
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: 1.2...3.5),
            repeats: false
        ) { _ in isWalking = true }
    }

    private func stopTimers() {
        walkTimer?.invalidate()
        pauseTimer?.invalidate()
    }

    // MARK: - Resource Loading

    private static func loadFrames(prefix: String) -> [NSImage] {
        (1...8).compactMap { i in
            guard let url = Bundle.module.url(forResource: "CatWalk_\(prefix)\(i)", withExtension: "png"),
                  let img = NSImage(contentsOf: url) else { return nil }
            return img
        }
    }
}
