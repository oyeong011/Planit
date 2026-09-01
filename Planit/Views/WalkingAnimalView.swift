import AppKit
import QuartzCore
import SwiftUI

struct WalkingAnimalView: View {
    static let animalSize: CGFloat = 56
    static let laneHeight: CGFloat = 64
    static let animationFrameRate: TimeInterval = 24
    static let spriteOriginY: CGFloat = laneHeight - animalSize
    static let speed: CGFloat = 90
    static let paradeSpacing: CGFloat = 22

    fileprivate static let frameCount = 8
    fileprivate static let boundaryInset: CGFloat = 6
    fileprivate static let tickDuration: TimeInterval = 1.0 / animationFrameRate
    fileprivate static let frameDuration: TimeInterval = 1.0 / 12.0
    fileprivate static let maxCatchUpDuration: TimeInterval = 1.0 / 20.0

    private static let randomSessionStyle: WalkingAnimalStyle = WalkingAnimalStyle.randomPool.randomElement() ?? .cat

    @ObservedObject private var settings = AnimalSettings.shared

    @ViewBuilder
    var body: some View {
        if settings.isEnabled {
            WalkingAnimalLayerView(
                selectedStyle: settings.selectedStyle,
                displayMode: settings.displayMode,
                paradeStyles: settings.selectedParadeStyles
            )
            .frame(height: Self.laneHeight)
        } else {
            EmptyView()
        }
    }

    struct MotionState {
        var xPos: CGFloat
        var isMovingRight: Bool
        var frameIndex: Int
        var frameElapsed: TimeInterval
    }

    struct ParadeTrack {
        let endX: CGFloat
        let cycleLength: CGFloat
    }

    static func visibleStyles(
        selectedStyle: WalkingAnimalStyle,
        displayMode: WalkingPetDisplayMode,
        paradeStyles: [WalkingAnimalStyle]
    ) -> [WalkingAnimalStyle] {
        switch displayMode {
        case .selected:
            return [selectedStyle]
        case .random:
            return [randomSessionStyle]
        case .parade:
            return AnimalSettings.normalizedParadeStyles(paradeStyles.isEmpty ? [selectedStyle] : paradeStyles)
        }
    }

    static func paradeInitialXPosition(for index: Int) -> CGFloat {
        boundaryInset + CGFloat(max(0, index)) * paradeStride
    }

    static func displayXPosition(
        _ xPos: CGFloat,
        totalWidth: CGFloat,
        displayMode: WalkingPetDisplayMode
    ) -> CGFloat {
        if displayMode == .parade {
            return xPos
        }

        return clampedXPosition(xPos, totalWidth: totalWidth)
    }

    static func shouldRenderFrame(
        at xPos: CGFloat,
        totalWidth: CGFloat,
        displayMode: WalkingPetDisplayMode
    ) -> Bool {
        guard displayMode == .parade else { return true }
        return xPos + animalSize >= 0 && xPos <= totalWidth
    }

    static func advancedState(
        from state: MotionState,
        totalWidth: CGFloat,
        frameCount: Int = Self.frameCount,
        tickDuration: TimeInterval = Self.tickDuration
    ) -> MotionState {
        var nextState = advancedFrameState(from: state, frameCount: frameCount, tickDuration: tickDuration)

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

    static func advancedParadeState(
        from state: MotionState,
        totalWidth: CGFloat,
        petCount: Int,
        frameCount: Int = Self.frameCount,
        tickDuration: TimeInterval = Self.tickDuration
    ) -> MotionState {
        guard let track = paradeTrack(totalWidth: totalWidth, petCount: petCount) else {
            return advancedFrameState(from: state, frameCount: frameCount, tickDuration: tickDuration)
        }

        return advancedParadeState(
            from: state,
            track: track,
            frameCount: frameCount,
            tickDuration: tickDuration
        )
    }

    static func advancedParadeState(
        from state: MotionState,
        track: ParadeTrack,
        frameCount: Int = Self.frameCount,
        tickDuration: TimeInterval = Self.tickDuration
    ) -> MotionState {
        var nextState = advancedFrameState(from: state, frameCount: frameCount, tickDuration: tickDuration)

        nextState.isMovingRight = true
        var nextX = nextState.xPos + speed * CGFloat(tickDuration)

        while nextX >= track.endX {
            nextX -= track.cycleLength
        }
        while nextX < -animalSize {
            nextX += track.cycleLength
        }

        nextState.xPos = nextX
        return nextState
    }

    fileprivate static func loadFrames(style: WalkingAnimalStyle) -> [NSImage] {
        AnimalSpriteImageCache.shared.frames(style: style, prefersRetina: (NSScreen.main?.backingScaleFactor ?? 1.0) >= 2.0)
    }

    private static var paradeStride: CGFloat {
        animalSize + paradeSpacing
    }

    private static func advancedFrameState(
        from state: MotionState,
        frameCount: Int,
        tickDuration: TimeInterval
    ) -> MotionState {
        var nextState = state
        let safeFrameCount = max(1, frameCount)
        nextState.frameElapsed += tickDuration

        while nextState.frameElapsed >= Self.frameDuration {
            nextState.frameElapsed -= Self.frameDuration
            nextState.frameIndex = (nextState.frameIndex + 1) % safeFrameCount
        }

        return nextState
    }

    private static func clampedXPosition(_ xPos: CGFloat, totalWidth: CGFloat) -> CGFloat {
        min(
            max(xPos, boundaryInset),
            max(boundaryInset, totalWidth - animalSize - boundaryInset)
        )
    }

    static func paradeTrack(totalWidth: CGFloat, petCount: Int) -> ParadeTrack? {
        guard totalWidth > 0 else { return nil }

        let visibleEndX = max(0, totalWidth) + boundaryInset
        guard petCount > 0 else {
            return ParadeTrack(endX: visibleEndX, cycleLength: visibleEndX + animalSize)
        }

        let lastInitialX = paradeInitialXPosition(for: petCount - 1)
        let endX = max(visibleEndX, lastInitialX + paradeStride)
        return ParadeTrack(endX: endX, cycleLength: endX + animalSize)
    }
}

private struct WalkingAnimalLayerView: NSViewRepresentable {
    let selectedStyle: WalkingAnimalStyle
    let displayMode: WalkingPetDisplayMode
    let paradeStyles: [WalkingAnimalStyle]

    func makeNSView(context: Context) -> WalkingAnimalAnimationView {
        let view = WalkingAnimalAnimationView()
        view.configure(selectedStyle: selectedStyle, displayMode: displayMode, paradeStyles: paradeStyles)
        return view
    }

    func updateNSView(_ nsView: WalkingAnimalAnimationView, context: Context) {
        nsView.configure(selectedStyle: selectedStyle, displayMode: displayMode, paradeStyles: paradeStyles)
    }
}

private final class WalkingAnimalAnimationView: NSView {
    private struct AnimatedPet {
        let layer: CALayer
        let style: WalkingAnimalStyle
        var state: WalkingAnimalView.MotionState
        var prefersRetina: Bool
        var appliedFrameIndex: Int?
        var appliedIsMovingRight: Bool?
    }

    private var pets: [AnimatedPet] = []
    private var timer: Timer?
    private var lastTickDate: Date?
    private var currentStyles: [WalkingAnimalStyle] = []
    private var currentDisplayMode: WalkingPetDisplayMode = .selected
    private var isPopoverVisible = true
    private var popoverDidCloseObserver: NSObjectProtocol?
    private var popoverWillShowObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.isGeometryFlipped = true
        observePopoverVisibility()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        stopAnimating()
        removePopoverVisibilityObservers()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: WalkingAnimalView.laneHeight)
    }

    override func layout() {
        super.layout()
        updateLayerBackingScale()
        applyState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerBackingScale()

        if window == nil {
            stopAnimating()
        } else {
            startAnimatingIfVisible()
        }
    }

    func configure(
        selectedStyle: WalkingAnimalStyle,
        displayMode: WalkingPetDisplayMode,
        paradeStyles: [WalkingAnimalStyle]
    ) {
        let styles = WalkingAnimalView.visibleStyles(
            selectedStyle: selectedStyle,
            displayMode: displayMode,
            paradeStyles: paradeStyles
        )
        guard currentStyles != styles || currentDisplayMode != displayMode else { return }
        currentStyles = styles
        currentDisplayMode = displayMode
        rebuildPets(styles: styles)
        applyState()
    }

    private func rebuildPets(styles: [WalkingAnimalStyle]) {
        pets.forEach { $0.layer.removeFromSuperlayer() }
        pets = styles.enumerated().map { index, style in
            let imageLayer = CALayer()
            imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            imageLayer.bounds = CGRect(
                x: 0,
                y: 0,
                width: WalkingAnimalView.animalSize,
                height: WalkingAnimalView.animalSize
            )
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.contentsScale = currentBackingScale
            imageLayer.magnificationFilter = .nearest
            imageLayer.minificationFilter = .nearest
            layer?.addSublayer(imageLayer)

            let prefersRetina = currentBackingScale >= 2.0
            let initialX = WalkingAnimalView.paradeInitialXPosition(for: index)
            let state = WalkingAnimalView.MotionState(
                xPos: initialX,
                isMovingRight: currentDisplayMode == .parade || index.isMultiple(of: 2),
                frameIndex: index % WalkingAnimalView.frameCount,
                frameElapsed: 0
            )
            return AnimatedPet(
                layer: imageLayer,
                style: style,
                state: state,
                prefersRetina: prefersRetina,
                appliedFrameIndex: nil,
                appliedIsMovingRight: nil
            )
        }
    }

    private var currentBackingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }

    private func updateLayerBackingScale() {
        let backingScale = currentBackingScale
        let prefersRetina = backingScale >= 2.0
        layer?.contentsScale = backingScale
        for index in pets.indices {
            pets[index].layer.contentsScale = backingScale
            if pets[index].prefersRetina != prefersRetina {
                pets[index].prefersRetina = prefersRetina
                pets[index].appliedFrameIndex = nil
            }
        }
    }

    private func observePopoverVisibility() {
        popoverDidCloseObserver = NotificationCenter.default.addObserver(
            forName: .calenPopoverDidClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPopoverVisible = false
            self?.stopAnimating()
        }

        popoverWillShowObserver = NotificationCenter.default.addObserver(
            forName: .calenPopoverWillShow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPopoverVisible = true
            self?.startAnimatingIfVisible()
        }
    }

    private func removePopoverVisibilityObservers() {
        if let popoverDidCloseObserver {
            NotificationCenter.default.removeObserver(popoverDidCloseObserver)
        }
        if let popoverWillShowObserver {
            NotificationCenter.default.removeObserver(popoverWillShowObserver)
        }
    }

    private func startAnimatingIfVisible() {
        guard window != nil, isPopoverVisible else { return }
        startAnimating()
    }

    private func startAnimating() {
        guard timer == nil else { return }
        lastTickDate = Date()

        let timer = Timer(timeInterval: WalkingAnimalView.tickDuration, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
    }

    private func tick() {
        let now = Date()
        let elapsed = lastTickDate.map { now.timeIntervalSince($0) } ?? WalkingAnimalView.tickDuration
        lastTickDate = now
        let boundedElapsed = min(max(elapsed, WalkingAnimalView.tickDuration), WalkingAnimalView.maxCatchUpDuration)
        let totalWidth = bounds.width

        if currentDisplayMode == .parade,
           let track = WalkingAnimalView.paradeTrack(totalWidth: totalWidth, petCount: pets.count) {
            for index in pets.indices {
                pets[index].state = WalkingAnimalView.advancedParadeState(
                    from: pets[index].state,
                    track: track,
                    frameCount: WalkingAnimalView.frameCount,
                    tickDuration: boundedElapsed
                )
            }
            applyState()
            return
        }

        for index in pets.indices {
            pets[index].state = WalkingAnimalView.advancedState(
                from: pets[index].state,
                totalWidth: totalWidth,
                frameCount: WalkingAnimalView.frameCount,
                tickDuration: boundedElapsed
            )
        }
        applyState()
    }

    private func applyState() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let totalWidth = bounds.width
        for index in pets.indices {
            let y = WalkingAnimalView.spriteOriginY
            let x = WalkingAnimalView.displayXPosition(
                pets[index].state.xPos,
                totalWidth: totalWidth,
                displayMode: currentDisplayMode
            )
            let frameCount = max(1, pets[index].style.frameCount)
            let frameIndex = pets[index].state.frameIndex % frameCount
            let isMovingRight = pets[index].state.isMovingRight

            pets[index].layer.position = CGPoint(
                x: x + WalkingAnimalView.animalSize / 2,
                y: y + WalkingAnimalView.animalSize / 2
            )

            if pets[index].appliedIsMovingRight != isMovingRight {
                pets[index].layer.transform = isMovingRight
                    ? CATransform3DIdentity
                    : CATransform3DMakeScale(-1, 1, 1)
                pets[index].appliedIsMovingRight = isMovingRight
            }

            if pets[index].appliedFrameIndex != frameIndex,
               WalkingAnimalView.shouldRenderFrame(at: x, totalWidth: totalWidth, displayMode: currentDisplayMode) {
                if let frame = AnimalSpriteImageCache.shared.renderedFrame(
                    style: pets[index].style,
                    frameIndex: frameIndex,
                    prefersRetina: pets[index].prefersRetina
                ) {
                    pets[index].layer.contents = frame
                    pets[index].appliedFrameIndex = frameIndex
                }
            }
        }
        CATransaction.commit()
    }

}

final class AnimalSpriteImageCache {
    static let shared = AnimalSpriteImageCache()
    private let lock = NSRecursiveLock()
    private var imageCache: [String: NSImage] = [:]
    private var framesCache: [String: [NSImage]] = [:]
    private var renderedFramesCache: [String: [CGImage]] = [:]
    private var renderedFrameCache: [String: CGImage] = [:]

    func image(style: WalkingAnimalStyle, frameIndex: Int) -> NSImage? {
        image(named: style.frameResourceName(for: frameIndex), subdirectory: style.spriteSubdirectory)
    }

    func image(named name: String, subdirectory: String = "CatSprites") -> NSImage? {
        withCacheLock {
            let cacheKey = "\(subdirectory)/\(name)"
            if let cached = imageCache[cacheKey] { return cached }
            guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: subdirectory),
                  let image = NSImage(contentsOf: url) else {
                return nil
            }
            imageCache[cacheKey] = image
            return image
        }
    }

    func frames(style: WalkingAnimalStyle, prefersRetina: Bool) -> [NSImage] {
        withCacheLock {
            let cacheKey = framesCacheKey(style: style, prefersRetina: prefersRetina)
            if let cached = framesCache[cacheKey] { return cached }

            let frames = (0..<style.frameCount).map { frameIndex in
                loadFrame(style: style, frameIndex: frameIndex, prefersRetina: prefersRetina)
            }
            framesCache[cacheKey] = frames
            return frames
        }
    }

    func renderedFrames(style: WalkingAnimalStyle, prefersRetina: Bool) -> [CGImage] {
        let cacheKey = framesCacheKey(style: style, prefersRetina: prefersRetina)
        if let cached = withCacheLock({ renderedFramesCache[cacheKey] }) {
            return cached
        }

        let renderedFrames = (0..<style.frameCount).compactMap { frameIndex in
            renderedFrame(style: style, frameIndex: frameIndex, prefersRetina: prefersRetina)
        }

        return withCacheLock {
            renderedFramesCache[cacheKey] = renderedFrames
            return renderedFrames
        }
    }

    func renderedFrame(style: WalkingAnimalStyle, frameIndex: Int, prefersRetina: Bool) -> CGImage? {
        let safeFrameIndex = max(0, min(frameIndex, max(0, style.frameCount - 1)))
        let cacheKey = renderedFrameCacheKey(style: style, frameIndex: safeFrameIndex, prefersRetina: prefersRetina)
        return withCacheLock {
            if let cached = renderedFrameCache[cacheKey] { return cached }

            let image = loadFrame(style: style, frameIndex: safeFrameIndex, prefersRetina: prefersRetina)
            guard let renderedFrame = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            renderedFrameCache[cacheKey] = renderedFrame
            return renderedFrame
        }
    }

    private func framesCacheKey(style: WalkingAnimalStyle, prefersRetina: Bool) -> String {
        "\(style.id)/\(prefersRetina ? "2x" : "1x")"
    }

    private func renderedFrameCacheKey(
        style: WalkingAnimalStyle,
        frameIndex: Int,
        prefersRetina: Bool
    ) -> String {
        "\(framesCacheKey(style: style, prefersRetina: prefersRetina))/frame-\(frameIndex)"
    }

    private func loadFrame(style: WalkingAnimalStyle, frameIndex: Int, prefersRetina: Bool) -> NSImage {
        let baseName = style.frameResourceName(for: frameIndex)

        if prefersRetina,
           let image = image(named: "\(baseName)@2x", subdirectory: style.spriteSubdirectory) {
            return image
        }

        if let image = image(named: baseName, subdirectory: style.spriteSubdirectory) {
            return image
        }

        if !prefersRetina,
           let image = image(named: "\(baseName)@2x", subdirectory: style.spriteSubdirectory) {
            return image
        }

        return NSImage(size: NSSize(width: WalkingAnimalView.animalSize, height: WalkingAnimalView.animalSize))
    }

    private func withCacheLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
