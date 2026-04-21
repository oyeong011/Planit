import SwiftUI

/// 화면 하단을 좌우로 걸어다니는 고양이 오버레이
struct WalkingCatView: View {
    // 고양이 위치 & 방향
    @State private var xPos: CGFloat = 80
    @State private var facingRight: Bool = true
    // 걷기 애니메이션 페이즈
    @State private var walkPhase: CGFloat = 0
    // 걷기/멈추기 상태
    @State private var isWalking: Bool = true
    @State private var pauseTimer: Timer? = nil
    @State private var walkTimer: Timer? = nil

    let containerWidth: CGFloat
    let catSize: CGFloat = 40

    private let speed: CGFloat = 0.8        // px per tick
    private let tickInterval: TimeInterval = 0.016 // ~60fps

    var body: some View {
        GeometryReader { _ in
            catImage
                .offset(x: xPos - catSize / 2, y: 0)
        }
        .frame(height: catSize)
        .onAppear { startWalking() }
        .onDisappear { stopTimers() }
    }

    // MARK: - Cat Image

    private var catImage: some View {
        Group {
            if let url = Bundle.main.url(forResource: "WalkingCat", withExtension: "png"),
               let nsImg = NSImage(contentsOf: url) {
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: catSize, height: catSize)
                    .scaleEffect(x: facingRight ? 1 : -1, y: 1)
                    // 발 동작: 좌우 흔들기
                    .rotationEffect(.degrees(isWalking ? sin(walkPhase) * 6 : 0),
                                    anchor: .bottom)
                    // 걸음 리듬: 위아래 바운스
                    .offset(y: isWalking ? -abs(sin(walkPhase * 2)) * 3 : 0)
            }
        }
    }

    // MARK: - Timers

    private func startWalking() {
        walkTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { _ in
            guard isWalking else { return }

            walkPhase += 0.18

            let halfCat = catSize / 2
            let minX = halfCat + 10
            let maxX = containerWidth - halfCat - 10

            if facingRight {
                xPos += speed
                if xPos >= maxX {
                    xPos = maxX
                    facingRight = false
                    randomPause()
                }
            } else {
                xPos -= speed
                if xPos <= minX {
                    xPos = minX
                    facingRight = true
                    randomPause()
                }
            }
        }
    }

    /// 가끔 멈춰서 앉아있다가 다시 걷기
    private func randomPause() {
        guard Bool.random() else { return }
        isWalking = false
        let pauseDuration = Double.random(in: 1.5...4.0)
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseDuration, repeats: false) { _ in
            isWalking = true
        }
    }

    private func stopTimers() {
        walkTimer?.invalidate()
        pauseTimer?.invalidate()
    }
}
