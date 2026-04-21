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

    // 스프라이트 표시 크기 — 넉넉하게 키워서 선명도·존재감 확보
    let catSize: CGFloat = 56

    private let fps: TimeInterval = 1.0 / 10
    private let speed: CGFloat = 2.2
    private let rFrames: [NSImage] = Self.loadFrames(prefix: "R")
    private let lFrames: [NSImage] = Self.loadFrames(prefix: "L")

    var body: some View {
        GeometryReader { geo in
            currentFrameImage
                .offset(x: xPos - catSize / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    containerWidth = geo.size.width
                    xPos = CGFloat.random(in: catSize...(max(containerWidth - catSize, catSize + 1)))
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
            // aspectRatio 유지 + fit으로 프레임간 크기 떨림 방지
            Image(nsImage: frame)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: catSize, height: catSize)
                // 다크모드에서만 살짝 dim — 라이트모드는 원색 유지
                .opacity(colorScheme == .dark ? 0.88 : 1.0)
                // 배경과 분리되는 부드러운 그림자
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.6 : 0.2),
                    radius: 2, x: 0, y: 1
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
            // Retina: @2x 명시 로드, 논리 사이즈를 절반으로 설정해 포인트 일치
            if scale >= 2.0,
               let url2x = Bundle.module.url(forResource: "CatWalk_\(prefix)\(i)@2x", withExtension: "png"),
               let img = NSImage(contentsOf: url2x) {
                // 이미지 픽셀을 논리 포인트로 정규화 — 프레임간 크기 통일
                let normalized = NSSize(width: img.size.width / 2, height: img.size.height / 2)
                img.size = normalized
                return img
            }
            guard let url = Bundle.module.url(forResource: "CatWalk_\(prefix)\(i)", withExtension: "png"),
                  let img = NSImage(contentsOf: url) else { return nil }
            return img
        }
    }
}
