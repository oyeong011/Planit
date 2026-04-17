import SwiftUI

// MARK: - macOS App Entry Point

#if os(macOS)
@main
struct PlanitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Settings 메뉴 항목 제거 — 팝오버 앱에는 불필요
            CommandGroup(replacing: .appSettings) { }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NotificationService()
        menuBarController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController.stop()
    }
}

#elseif os(iOS)

// MARK: - iOS App Entry Point (향후 구현)

@main
struct PlanitApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

#endif
