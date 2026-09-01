import AppKit
import Foundation
import Testing
@testable import Calen

@Suite("Menu bar icon")
struct MenuBarIconTests {
    @Test("status bar icon renders from bundled image resources")
    func statusBarIconRendersFromBundledResources() throws {
        let image = MenuBarIcon.makeImage(updateAvailable: false)

        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)

        let source = try projectFile("Planit/Models/MenuBarIcon.swift")
        #expect(source.contains("StatusBarIcon"))
        #expect(!source.contains("MenuBarProgress"))
    }

    @Test("update badge keeps status bar icon non-empty")
    func updateBadgeKeepsIconNonEmpty() {
        let image = MenuBarIcon.makeImage(updateAvailable: true)

        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(!image.isTemplate)
        #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }

    @Test("update badge icon resolves menu bar tint at draw time")
    func updateBadgeIconResolvesMenuBarTintAtDrawTime() throws {
        let source = try projectFile("Planit/Models/MenuBarIcon.swift")

        #expect(source.contains("NSColor.labelColor"),
                "Badged status icons must resolve labelColor while drawing so dark menu bars stay legible.")
        #expect(source.contains(".destinationIn"),
                "The bundled status icon should mask the dynamic label color instead of baking black pixels.")
        #expect(!source.contains("lockFocus()"),
                "A one-time bitmap can become stale across appearance changes.")
    }

    private func projectFile(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
