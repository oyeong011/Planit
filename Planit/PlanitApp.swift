import SwiftUI
import EventKit
import UserNotifications

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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var globalClickMonitor: Any?   // 팝오버 외부 클릭 감지 — applicationWillTerminate에서 제거
    var localPasteMonitor: Any?    // Cmd+V 이미지 붙여넣기 인터셉트

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NotificationService()

        NSApp.setActivationPolicy(.accessory)

        // Settings scene이 만드는 "Calen 설정" 창만 닫기 — NSHostingController 내부 창은 건드리지 않음
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.windows
                .filter { !($0 is NSPanel) && ($0.title.isEmpty || $0.title.contains("설정") || $0.title == "Settings") }
                .forEach { $0.close() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calen")
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 1320, height: 860)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainView())
        popover.delegate = self

        // 팝오버 외부 클릭 시 닫기
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            setupPasteMonitor()
        }
    }


    // MARK: - 로컬 Cmd+V 인터셉트
    // performKeyEquivalent 방식은 Edit 메뉴가 먼저 가로채기 때문에 동작 안 함.
    // 로컬 모니터는 메뉴/필드에디터보다 먼저 keyDown을 인터셉트하므로 올바른 방법.

    private func setupPasteMonitor() {
        guard localPasteMonitor == nil else { return }
        localPasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.popover.isShown,
                  event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "v" else { return event }

            switch ChatPasteboardReader.payload(from: .general) {
            case .files(let urls):
                NotificationCenter.default.post(
                    name: CalenNotification.pasteFiles,
                    object: nil,
                    userInfo: ["urls": urls]
                )
                return nil  // 이벤트 소비 — 텍스트 붙여넣기 방지
            case .image(let image):
                NotificationCenter.default.post(
                    name: CalenNotification.pasteImage,
                    object: nil,
                    userInfo: ["image": image]
                )
                return nil
            case nil:
                return event  // 텍스트는 정상 처리
            }
        }
    }

    private func teardownPasteMonitor() {
        if let monitor = localPasteMonitor {
            NSEvent.removeMonitor(monitor)
            localPasteMonitor = nil
        }
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        teardownPasteMonitor()
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

// MARK: - Notifications & Pasteboard

enum CalenNotification {
    static let pasteImage = Notification.Name("CalenPasteImage")
    static let pasteFiles = Notification.Name("CalenPasteFiles")
}

enum ChatPastePayload {
    case files([URL])
    case image(NSImage)
}

enum ChatPasteboardReader {
    private static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp", "heic", "pdf"
    ]

    static func payload(from pasteboard: NSPasteboard) -> ChatPastePayload? {
        let urls = supportedFileURLs(from: pasteboard)
        if !urls.isEmpty { return .files(urls) }
        if let image = NSImage(pasteboard: pasteboard) { return .image(image) }
        return nil
    }

    private static func supportedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
    }
}
