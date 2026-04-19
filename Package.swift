// swift-tools-version: 5.9
import Foundation
import PackageDescription

let hasBundledCredentials = FileManager.default.fileExists(
    atPath: "Planit/Services/BundledCredentials.local.swift"
)

let package = Package(
    name: "Calen",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "CalenShared", targets: ["CalenShared"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // macOS/iOS/iPadOS 공통 도메인 — Models, Memory, Planning, Networking
        // 플랫폼 의존성 없는 순수 Swift + SwiftData + Foundation만 사용
        .target(
            name: "CalenShared",
            path: "Shared/Sources/CalenShared"
        ),
        .executableTarget(
            name: "Calen",
            dependencies: [
                "CalenShared",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Planit",
            exclude: ["Info.plist", "Planit.entitlements"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
                .copy("Resources/AppIcon.icns"),
                .process("Resources/ko.lproj"),
                .process("Resources/en.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/zh-Hant.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fr.lproj"),
                .process("Resources/de.lproj"),
                .process("Resources/pt-BR.lproj"),
                .process("Resources/it.lproj"),
                .process("Resources/ru.lproj"),
                .process("Resources/ar.lproj"),
                .process("Resources/hi.lproj"),
                .process("Resources/th.lproj"),
                .process("Resources/vi.lproj"),
                .process("Resources/id.lproj"),
                .process("Resources/ms.lproj"),
                .process("Resources/tr.lproj"),
                .process("Resources/pl.lproj"),
                .process("Resources/nl.lproj"),
                .process("Resources/sv.lproj"),
                .process("Resources/da.lproj"),
                .process("Resources/no.lproj"),
                .process("Resources/fi.lproj"),
                .process("Resources/uk.lproj"),
                .process("Resources/cs.lproj"),
                .process("Resources/ro.lproj"),
                .process("Resources/hu.lproj"),
                .process("Resources/el.lproj"),
                .process("Resources/he.lproj")
            ],
            swiftSettings: hasBundledCredentials ? [.define("HAS_BUNDLED_CREDENTIALS")] : []
        ),
        .testTarget(
            name: "CalenTests",
            dependencies: ["Calen"],
            path: "Tests"
        )
    ]
)
