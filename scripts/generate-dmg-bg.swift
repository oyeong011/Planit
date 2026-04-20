#!/usr/bin/env swift
// DMG 배경 이미지 생성기 — 1000x600 @ 1x, 2000x1200 @ 2x (Retina)
// 사용: swift scripts/generate-dmg-bg.swift
// 결과: docs/dmg-background.png + docs/dmg-background@2x.png

import SwiftUI
import AppKit

struct DMGBackground: View {
    var body: some View {
        ZStack {
            // 배경: 다크 + radial gradient (브랜드 색)
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.07),
                    Color(red: 0.06, green: 0.07, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Ambient glow — 왼쪽 하늘색, 오른쪽 인디고
            RadialGradient(
                colors: [Color(red: 0.49, green: 0.83, blue: 0.99).opacity(0.18), .clear],
                center: .init(x: 0.2, y: 0.5),
                startRadius: 0,
                endRadius: 400
            )
            RadialGradient(
                colors: [Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.18), .clear],
                center: .init(x: 0.8, y: 0.5),
                startRadius: 0,
                endRadius: 400
            )

            // 중앙 화살표 — 드래그 방향 암시
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.49, green: 0.83, blue: 0.99).opacity(0.7 - Double(i) * 0.2),
                                    Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.7 - Double(i) * 0.2)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity)

            // 상단 안내 텍스트
            VStack {
                Text("Drag Calen to Applications to install")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.top, 36)
                Spacer()
                Text("Calen — AI calendar companion for macOS")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .padding(.bottom, 24)
            }
        }
        .frame(width: 1000, height: 600)
    }
}

@MainActor
func renderPNG(scale: CGFloat, to path: String) throws {
    let renderer = ImageRenderer(content: DMGBackground())
    renderer.scale = scale
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DMGBg", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed"])
    }
    try png.write(to: URL(fileURLWithPath: path))
    print("✓ \(path) — \(nsImage.size.width)x\(nsImage.size.height) @\(Int(scale))x")
}

@MainActor
func main() async throws {
    let proj = FileManager.default.currentDirectoryPath
    try renderPNG(scale: 1.0, to: "\(proj)/docs/dmg-background.png")
    try renderPNG(scale: 2.0, to: "\(proj)/docs/dmg-background@2x.png")
}

try await main()
