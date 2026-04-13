// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Planit",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Planit",
            path: "Planit",
            exclude: ["Info.plist", "Planit.entitlements"]
        )
    ]
)
