import SwiftUI

struct WallpaperPreset: Identifiable, Equatable, Hashable {
    let id: String
    let nameKey: String
    let colorHexes: [String]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    let imageAssetName: String?
    let thumbnailAssetName: String?
    let readabilityOverlayOpacity: Double

    init(
        id: String,
        nameKey: String,
        colorHexes: [String],
        startPoint: UnitPoint,
        endPoint: UnitPoint,
        imageAssetName: String? = nil,
        thumbnailAssetName: String? = nil,
        readabilityOverlayOpacity: Double = 0
    ) {
        self.id = id
        self.nameKey = nameKey
        self.colorHexes = colorHexes
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.imageAssetName = imageAssetName
        self.thumbnailAssetName = thumbnailAssetName ?? imageAssetName
        self.readabilityOverlayOpacity = readabilityOverlayOpacity
    }

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
        // MARK: - 이미지 배경
        WallpaperPreset(
            id: "soft-studio-light",
            nameKey: "wallpaper.softStudioLight",
            colorHexes: ["#FFF5E8", "#F3D7BD", "#D8E8E4"],
            startPoint: .topLeading, endPoint: .bottomTrailing,
            imageAssetName: "calen_soft_studio_light",
            thumbnailAssetName: "calen_soft_studio_light_thumb",
            readabilityOverlayOpacity: 0.16
        ),
        WallpaperPreset(
            id: "quiet-midnight-dark",
            nameKey: "wallpaper.quietMidnightDark",
            colorHexes: ["#101820", "#1E2A3A", "#3A2D4A"],
            startPoint: .topLeading, endPoint: .bottomTrailing,
            imageAssetName: "calen_quiet_midnight_dark",
            thumbnailAssetName: "calen_quiet_midnight_dark_thumb",
            readabilityOverlayOpacity: 0.28
        ),
        WallpaperPreset(
            id: "pixel-pet-beige",
            nameKey: "wallpaper.pixelPetBeige",
            colorHexes: ["#F6E7D1", "#E8CFAE", "#FFF7EA"],
            startPoint: .topLeading, endPoint: .bottomTrailing,
            imageAssetName: "calen_pixel_pet_beige",
            thumbnailAssetName: "calen_pixel_pet_beige_thumb",
            readabilityOverlayOpacity: 0.18
        ),
        WallpaperPreset(
            id: "pixel-pet-pattern",
            nameKey: "wallpaper.pixelPetPattern",
            colorHexes: ["#F3DFC2", "#F9EBD5", "#DDBB92"],
            startPoint: .topLeading, endPoint: .bottomTrailing,
            imageAssetName: "calen_pixel_pet_pattern",
            thumbnailAssetName: "calen_pixel_pet_pattern_thumb",
            readabilityOverlayOpacity: 0.30
        ),
        WallpaperPreset(
            id: "cozy-pet-room",
            nameKey: "wallpaper.cozyPetRoom",
            colorHexes: ["#E8CBA3", "#A66F45", "#F4E4CA"],
            startPoint: .topLeading, endPoint: .bottomTrailing,
            imageAssetName: "calen_cozy_pet_room",
            thumbnailAssetName: "calen_cozy_pet_room_thumb",
            readabilityOverlayOpacity: 0.24
        ),
    ]
}
