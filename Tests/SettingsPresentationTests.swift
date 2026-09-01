import Foundation
import Testing
@testable import Calen

@Suite("Settings presentation")
struct SettingsPresentationTests {
    @Test("open always presents settings")
    func openAlwaysPresentsSettings() {
        #expect(SettingsPresentationIntent.open.resolvedValue(from: false) == true)
        #expect(SettingsPresentationIntent.open.resolvedValue(from: true) == true)
    }

    @Test("close always dismisses settings")
    func closeAlwaysDismissesSettings() {
        #expect(SettingsPresentationIntent.close.resolvedValue(from: false) == false)
        #expect(SettingsPresentationIntent.close.resolvedValue(from: true) == false)
    }

    @Test("toggle flips current presentation")
    func toggleFlipsCurrentPresentation() {
        #expect(SettingsPresentationIntent.toggle.resolvedValue(from: false) == true)
        #expect(SettingsPresentationIntent.toggle.resolvedValue(from: true) == false)
    }

    @Test("settings overlay can be dismissed without close button")
    func settingsOverlayCanDismissFromBackdrop() throws {
        let source = try projectFile("Planit/Views/MainView.swift")

        #expect(!source.contains(".sheet(isPresented: $showSettings)"),
                "Settings should not use a modal sheet that forces the close button path.")
        #expect(source.contains(".onTapGesture {\n                            closeSettings()"),
                "Settings backdrop should dismiss when the user clicks outside the panel.")
    }

    private func projectFile(_ path: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
