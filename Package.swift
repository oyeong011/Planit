// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Calen",
    defaultLocalization: "en",
    platforms: [
        // Multiplatform targets planned, but intentionally inactive until platform-specific
        // AppKit/Sparkle/menu-bar code is isolated from shared sources.
        // .iOS(.v17),
        // .watchOS(.v10),
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Calen",
            dependencies: [
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
            ]
        ),
        .testTarget(
            name: "CalenTests",
            dependencies: ["Calen"],
            path: "Tests"
        )
    ]
)
