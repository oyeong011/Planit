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
        .library(name: "CalenShared", targets: ["CalenShared"]),
        .executable(name: "CaleniOS", targets: ["CaleniOS"])
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
            exclude: [
                "Info.plist",
                "Planit.entitlements",
                "Planit-dev.entitlements",
                "Resources/WalkingCat.png",
                "Resources/WalkingCat@2x.png"
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/StatusBarIcon.png"),
                .copy("Resources/StatusBarIcon@2x.png"),
                .copy("Resources/frame_R1.png"),
                .copy("Resources/frame_R1@2x.png"),
                .copy("Resources/frame_R2.png"),
                .copy("Resources/frame_R2@2x.png"),
                .copy("Resources/frame_R3.png"),
                .copy("Resources/frame_R3@2x.png"),
                .copy("Resources/frame_R4.png"),
                .copy("Resources/frame_R4@2x.png"),
                .copy("Resources/frame_R5.png"),
                .copy("Resources/frame_R5@2x.png"),
                .copy("Resources/frame_R6.png"),
                .copy("Resources/frame_R6@2x.png"),
                .copy("Resources/frame_R7.png"),
                .copy("Resources/frame_R7@2x.png"),
                .copy("Resources/frame_R8.png"),
                .copy("Resources/frame_R8@2x.png"),
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
        .executableTarget(
            name: "CaleniOS",
            dependencies: ["CalenShared"],
            path: "CaleniOS/Sources",
            exclude: [
                // Info.plist + entitlements는 xcodebuild(.xcodeproj/project.yml)이 직접 사용.
                // SwiftPM executableTarget에서는 unhandled resources가 되지 않도록 제외.
                "Info.plist",
                "Resources/CaleniOS.entitlements"
            ],
            resources: [
                // v0.1.2 — iOS 전용 Localizable.strings. SwiftPM 빌드에서 bundle로 번들링.
                .process("Resources/ko.lproj"),
                .process("Resources/en.lproj")
            ]
        ),
        .testTarget(
            name: "CalenTests",
            // v0.1.1 Widget: WidgetDataPublisher 테스트를 위해 CaleniOS도 dependency로 추가.
            // (CaleniOS는 executableTarget이지만 @testable import는 허용됨.)
            dependencies: ["Calen", "CaleniOS"],
            path: "Tests"
        )
    ]
)
