import SwiftUI
import EventKit
import UserNotifications
import Combine

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
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var globalClickMonitor: Any?
    private let updater = UpdateCheckerService.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NotificationService()

        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows
                .filter { !($0 is NSPanel) && ($0.title.isEmpty || $0.title.contains("설정") || $0.title == "Settings") }
                .forEach { $0.close() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calen")
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 1320, height: 860)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainView())

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }

        // 업데이트 체크 (하루 1회)
        updater.checkIfNeeded()

        // 업데이트 있으면 아이콘 변경
        updater.$updateAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)
    }

    @objc func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        if updater.updateAvailable, let latest = updater.latestVersion {
            let updateItem = NSMenuItem(
                title: "새 버전 있음: v\(latest) → 업데이트",
                action: #selector(openReleasePage),
                keyEquivalent: ""
            )
            updateItem.target = self
            updateItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(updateItem)
        } else {
            let upToDate = NSMenuItem(title: "최신 버전입니다 (v\(updater.currentVersion))", action: nil, keyEquivalent: "")
            upToDate.isEnabled = false
            menu.addItem(upToDate)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Calen 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // 다음 좌클릭에 메뉴가 뜨지 않도록 초기화
    }

    @objc private func openReleasePage() {
        if let url = URL(string: "https://github.com/oyeong011/Planit/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshStatusIcon() {
        let symbolName = updater.updateAvailable ? "calendar.badge.exclamationmark" : "calendar"
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Calen")
    }
}

extension AppDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
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
