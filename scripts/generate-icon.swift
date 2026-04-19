#!/usr/bin/env swift
// Calen 앱 아이콘 생성기 — 하늘색 3D C 로고
// 사용법: swift scripts/generate-icon.swift
// 결과: Planit/Resources/AppIcon.icns + 임시 PNG들

import SwiftUI
import AppKit

// MARK: - Icon Design

struct CalenIcon: View {
    var body: some View {
        ZStack {
            // 부드러운 rounded square 배경 (macOS Big Sur 이후 표준 형태)
            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.93, blue: 1.00),  // 하늘색 (top)
                            Color(red: 0.30, green: 0.67, blue: 0.98)   // 진한 하늘색 (bottom)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // 상단 하이라이트 (유리 질감)
                    RoundedRectangle(cornerRadius: 220, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.5),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 6
                        )
                )
                .shadow(color: Color.blue.opacity(0.4), radius: 40, x: 0, y: 20)

            // C 문자 — 3D 느낌을 위해 그림자 레이어 여러 개
            ZStack {
                // 뒤에 깔리는 깊이 그림자
                Text("C")
                    .font(.system(size: 700, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.85))
                    .offset(x: 0, y: 14)
                    .blur(radius: 8)
                    .opacity(0.6)

                // 중간 그림자
                Text("C")
                    .font(.system(size: 700, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.55, blue: 0.9))
                    .offset(x: 0, y: 6)

                // 메인 C — 그라데이션
                Text("C")
                    .font(.system(size: 700, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.92, green: 0.97, blue: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 상단 하이라이트
                Text("C")
                    .font(.system(size: 700, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .mask(
                        Text("C")
                            .font(.system(size: 700, weight: .black, design: .rounded))
                    )
            }
            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 8)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Rendering

@MainActor
func renderIcon(size: CGFloat) -> NSImage? {
    let renderer = ImageRenderer(content: CalenIcon().frame(width: size, height: size).scaleEffect(size / 1024))
    renderer.scale = 1.0
    renderer.proposedSize = ProposedViewSize(width: size, height: size)
    return renderer.nsImage
}

@MainActor
func savePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 변환 실패"])
    }
    try png.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

@MainActor
func main() async throws {
    let fm = FileManager.default
    let projectDir = fm.currentDirectoryPath
    let iconsetDir = "\(projectDir)/.build/AppIcon.iconset"
    let resourcesDir = "\(projectDir)/Planit/Resources"

    // iconset 디렉토리 생성
    try? fm.removeItem(atPath: iconsetDir)
    try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    // iconutil이 요구하는 7가지 크기
    let sizes: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]

    for (size, filename) in sizes {
        print("  Rendering \(size)x\(size)...")
        guard let img = renderIcon(size: CGFloat(size)) else {
            throw NSError(domain: "IconGen", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "렌더 실패 \(size)"])
        }
        try savePNG(img, to: "\(iconsetDir)/\(filename)")
    }

    // iconutil로 .icns 변환
    print("→ iconutil로 .icns 생성 중...")
    let icnsPath = "\(resourcesDir)/AppIcon.icns"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
    try task.run()
    task.waitUntilExit()

    guard task.terminationStatus == 0 else {
        throw NSError(domain: "IconGen", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "iconutil 실패"])
    }

    // 1024 PNG는 DMG 배경 등에서도 쓸 수 있게 따로 저장
    if let preview = renderIcon(size: 1024) {
        try savePNG(preview, to: "\(projectDir)/.build/AppIcon-1024.png")
    }

    print("✅ \(icnsPath)")
    print("✅ .build/AppIcon-1024.png (미리보기용)")
}

do {
    try await main()
} catch {
    print("❌ \(error.localizedDescription)")
    exit(1)
}
