import SwiftUI

struct WalkingCatView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var xPos: CGFloat = 100
    @State private var facingRight: Bool = true
    @State private var frameIndex: Int = 0
    @State private var isWalking: Bool = true
    @State private var walkTimer: Timer? = nil
    @State private var pauseTimer: Timer? = nil
    @State private var containerWidth: CGFloat = 700

    let catSize: CGFloat = 48

    private let fps: TimeInterval = 1.0 / 10   // 10fps 걷기
    private let speed: CGFloat = 2.2            // px per frame
    private let rFrames: [NSImage] = Self.loadFrames(prefix: "R")
    private let lFrames: [NSImage] = Self.loadFrames(prefix: "L")

    var body: some View {
        GeometryReader { geo in
            currentFrameImage
                .frame(width: catSize, height: catSize)
                .offset(x: xPos - catSize / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    containerWidth = geo.size.width
                    xPos = CGFloat.random(in: 60...(max(containerWidth - 60, 61)))
                    startWalking()
                }
                .onDisappear { stopTimers() }
        }
        .frame(height: catSize)
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
                // 다크모드: 흰 고양이가 어두운 배경에서 너무 강하게 튀지 않도록 살짝 dim
                .colorMultiply(colorScheme == .dark ? Color(white: 0.82) : .white)
                // 배경 상관없이 고양이 윤곽이 보이도록 부드러운 그림자
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.55 : 0.18),
                    radius: 3, x: 0, y: 1
                )
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
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        return (1...8).compactMap { i in
            // Retina에서 @2x 명시 로드 후 논리 사이즈를 절반으로 설정
            if scale >= 2.0,
               let url2x = Bundle.module.url(forResource: "CatWalk_\(prefix)\(i)@2x", withExtension: "png"),
               let img = NSImage(contentsOf: url2x) {
                img.size = NSSize(width: img.size.width / 2, height: img.size.height / 2)
                return img
            }
            guard let url = Bundle.module.url(forResource: "CatWalk_\(prefix)\(i)", withExtension: "png"),
                  let img = NSImage(contentsOf: url) else { return nil }
            return img
        }
    }
}
