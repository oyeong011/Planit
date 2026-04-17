#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var globalClickMonitor: Any?
    private let updater = UpdaterService.shared
    private var cancellables = Set<AnyCancellable>()

    func start() {
        NSApp.setActivationPolicy(.accessory)
        closeDefaultSettingsWindows()
        configureStatusItem()
        configurePopover()
        configureGlobalClickMonitor()
        observeUpdater()
    }

    func stop() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        cancellables.removeAll()
    }

    private func closeDefaultSettingsWindows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows
                .filter { !($0 is NSPanel) && ($0.title.isEmpty || $0.title.contains("설정") || $0.title == "Settings") }
                .forEach { $0.close() }
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calen")
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func configurePopover() {
        popover.contentSize = NSSize(width: 1320, height: 860)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MainView())
    }

    private func configureGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    private func observeUpdater() {
        updater.$updateAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
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
                title: "새 버전 있음: v\(latest) → 지금 설치",
                action: #selector(checkForUpdates),
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

        let checkItem = NSMenuItem(title: "업데이트 확인...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

        menu.addItem(.separator())

        let relaunch = NSMenuItem(title: "재시작", action: #selector(relaunchApp), keyEquivalent: "r")
        relaunch.target = self
        relaunch.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        menu.addItem(relaunch)

        let quit = NSMenuItem(title: "Calen 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func relaunchApp() {
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "sleep 0.3 && open '\(appPath)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func refreshStatusIcon() {
        let symbolName = updater.updateAvailable ? "calendar.badge.exclamationmark" : "calendar"
        statusItem?.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Calen")
    }
}

extension MenuBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .calenPopoverDidClose, object: nil)
    }
}

extension Notification.Name {
    static let calenPopoverDidClose = Notification.Name("calenPopoverDidClose")
}
#endif
