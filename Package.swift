// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Calen",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Calen",
            path: "Planit",
            exclude: ["Info.plist", "Planit.entitlements"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy"),
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "CalenTests",
            path: "Tests"
        )
    ]
)
