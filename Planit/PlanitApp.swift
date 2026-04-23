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
    private let updater = UpdaterService.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NotificationService()

        AppearanceService.shared.bootstrap()
        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows
                .filter { !($0 is NSPanel) && ($0.title.isEmpty || $0.title.contains("설정") || $0.title == "Settings") }
                .forEach { $0.close() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = Self.makeStatusBarImage(update: false)
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 1320, height: 860)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MainView())

        // 업데이트 있으면 아이콘 변경 (Sparkle이 자체 스케줄로 백그라운드 체크 수행)
        updater.$updateAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }
            .store(in: &cancellables)

        // appearance 변경 시 NSApp + popover 양쪽 모두 즉시 반영
        AppearanceService.shared.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                switch mode {
                case .system: NSApp.appearance = nil
                case .light:  NSApp.appearance = NSAppearance(named: .aqua)
                case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
                }
                self?.popover.appearance = NSApp.appearance
            }
            .store(in: &cancellables)

        // 앱이 메뉴바에 조용히 떠 있어도 새 버전을 자동 감지해 알림으로 알리도록 주기 폴링 시작.
        // (Sparkle의 accessory 앱 UI가 안 뜨는 환경에서도 배너 + 시스템 알림 동작)
        updater.startPeriodicAppcastPolling()
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

        let feedbackItem = NSMenuItem(title: "피드백 보내기...", action: #selector(sendFeedback), keyEquivalent: "")
        feedbackItem.target = self
        feedbackItem.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: nil)
        menu.addItem(feedbackItem)

        menu.addItem(.separator())

        let relaunch = NSMenuItem(title: "재시작", action: #selector(relaunchApp), keyEquivalent: "r")
        relaunch.target = self
        relaunch.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        menu.addItem(relaunch)

        let quit = NSMenuItem(title: "Calen 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // 다음 좌클릭에 메뉴가 뜨지 않도록 초기화
    }

    /// Sparkle 업데이트 다이얼로그 트리거
    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func sendFeedback() {
        let version = updater.currentVersion
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let subject = "Calen v\(version) 피드백"
        let body = """

            ---
            앱 버전: \(version)
            macOS: \(osVersion)
            """
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:oyeong011@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 앱 재시작 (업데이트 적용 또는 단순 재시작)
    @objc private func relaunchApp() {
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", appPath]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func refreshStatusIcon() {
        statusItem.button?.image = Self.makeStatusBarImage(update: updater.updateAvailable)
    }

    private static func makeStatusBarImage(update: Bool) -> NSImage {
        if !update, let url = Bundle.module.url(forResource: "StatusBarIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        let symbol = update ? "calendar.badge.exclamationmark" : "calendar"
        return NSImage(systemSymbolName: symbol, accessibilityDescription: "Calen") ?? NSImage()
    }
}

// MARK: - NSPopoverDelegate
extension AppDelegate: NSPopoverDelegate {
    /// popover가 외부 클릭 등으로 닫힐 때 → MainView의 showSettings를 리셋
    func popoverWillShow(_ notification: Notification) {
        // 팝오버 열릴 때 외부(Google Calendar 앱/웹)에서 추가된 이벤트를 즉시 반영
        NotificationCenter.default.post(name: .calenPopoverWillShow, object: nil)
    }

    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .calenPopoverDidClose, object: nil)
    }
}

extension Notification.Name {
    static let calenPopoverDidClose  = Notification.Name("calenPopoverDidClose")
    static let calenPopoverWillShow  = Notification.Name("calenPopoverWillShow")
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
