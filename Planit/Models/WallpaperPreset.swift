import SwiftUI

struct WallpaperPreset: Identifiable, Equatable, Hashable {
    let id: String
    let nameKey: String
    let colorHexes: [String]
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    static func == (lhs: WallpaperPreset, rhs: WallpaperPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var colors: [Color] { colorHexes.compactMap { Color(hex: $0) } }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }

    var localizedName: String { String(localized: String.LocalizationValue(nameKey)) }

    static let builtIn: [WallpaperPreset] = [
        WallpaperPreset(
            id: "aurora",
            nameKey: "wallpaper.aurora",
            colorHexes: ["#0F0C29", "#302B63", "#24243E"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "sunset",
            nameKey: "wallpaper.sunset",
            colorHexes: ["#FC466B", "#3F5EFB"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "ocean",
            nameKey: "wallpaper.ocean",
            colorHexes: ["#005C97", "#363795"],
            startPoint: .top, endPoint: .bottom
        ),
        WallpaperPreset(
            id: "lavender",
            nameKey: "wallpaper.lavender",
            colorHexes: ["#C471ED", "#12C2E9"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "forest",
            nameKey: "wallpaper.forest",
            colorHexes: ["#134E5E", "#71B280"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "midnight",
            nameKey: "wallpaper.midnight",
            colorHexes: ["#232526", "#414345"],
            startPoint: .top, endPoint: .bottom
        ),
        WallpaperPreset(
            id: "peach",
            nameKey: "wallpaper.peach",
            colorHexes: ["#ED4264", "#FFEDBC"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "mint",
            nameKey: "wallpaper.mint",
            colorHexes: ["#00B09B", "#96C93D"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        // MARK: - 계절 배경
        WallpaperPreset(
            id: "spring",
            nameKey: "wallpaper.spring",
            colorHexes: ["#FFCAD4", "#B5EAD7", "#C7CEEA"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "summer",
            nameKey: "wallpaper.summer",
            colorHexes: ["#00C9FF", "#12D8FA", "#A6FFCB"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "autumn",
            nameKey: "wallpaper.autumn",
            colorHexes: ["#F7971E", "#FFD200", "#EB5757"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        WallpaperPreset(
            id: "winter",
            nameKey: "wallpaper.winter",
            colorHexes: ["#1A2980", "#26D0CE", "#E0F7FA"],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
    ]
}
