import SwiftUI

#if os(macOS)
import AppKit
#endif

struct WallpaperResourceImage: View {
    let resourceName: String

    var body: some View {
        #if os(macOS)
        if let image = WallpaperImageCache.image(named: resourceName) {
            Image(nsImage: image)
                .resizable()
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}

#if os(macOS)
@MainActor
private enum WallpaperImageCache {
    private static var images: [String: NSImage] = [:]

    static func image(named resourceName: String) -> NSImage? {
        if let cached = images[resourceName] {
            return cached
        }

        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: "png",
            subdirectory: "Wallpapers"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        images[resourceName] = image
        return image
    }
}
#endif
