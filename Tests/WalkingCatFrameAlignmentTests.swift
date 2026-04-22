import CoreGraphics
import Foundation
import ImageIO
import Testing

@Suite("WalkingCatFrameAlignment")
struct WalkingCatFrameAlignmentTests {
    @Test("1x frames keep the cat bottom-centered in a 44x44 canvas")
    func frames1xAreBottomCentered() throws {
        try assertBottomCentered(frameNames: (1...8).map { "frame_R\($0)" }, canvasSize: 44)
    }

    @Test("@2x frames keep the cat bottom-centered in an 88x88 canvas")
    func frames2xAreBottomCentered() throws {
        try assertBottomCentered(frameNames: (1...8).map { "frame_R\($0)@2x" }, canvasSize: 88)
    }

    private func assertBottomCentered(frameNames: [String], canvasSize: Int) throws {
        for name in frameNames {
            let image = try loadImage(named: name)
            #expect(image.width == canvasSize)
            #expect(image.height == canvasSize)

            let bbox = try alphaBoundingBox(in: image, threshold: 10)
            #expect(bbox != nil, "\(name) should contain visible pixels")

            guard let bbox else { continue }

            let centerOffset = abs(bbox.centerX - (Double(canvasSize) / 2.0))
            #expect(centerOffset <= 0.5, "\(name) center offset: \(centerOffset), bbox: \(bbox)")
            #expect(bbox.bottom == canvasSize, "\(name) bottom: \(bbox.bottom), bbox: \(bbox)")
        }
    }

    private func loadImage(named name: String) throws -> CGImage {
        let url = repositoryRoot()
            .appending(path: "Planit")
            .appending(path: "Resources")
            .appending(path: "\(name).png")

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw FrameAlignmentError.imageLoadFailed(url.path)
        }

        return image
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func alphaBoundingBox(in image: CGImage, threshold: UInt8) throws -> AlphaBBox? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FrameAlignmentError.bitmapContextFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var left = width
        var top = height
        var right = 0
        var bottom = 0
        var found = false

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * bytesPerRow) + (x * bytesPerPixel) + 3]
                if alpha <= threshold { continue }

                found = true
                left = min(left, x)
                top = min(top, y)
                right = max(right, x + 1)
                bottom = max(bottom, y + 1)
            }
        }

        guard found else { return nil }
        return AlphaBBox(left: left, top: top, right: right, bottom: bottom)
    }
}

private struct AlphaBBox: CustomStringConvertible {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int

    var width: Int { right - left }
    var centerX: Double { Double(left) + (Double(width) / 2.0) }
    var description: String { "(\(left), \(top), \(right), \(bottom))" }
}

private enum FrameAlignmentError: Error {
    case bitmapContextFailed
    case imageLoadFailed(String)
}
