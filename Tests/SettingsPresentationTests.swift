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
}
