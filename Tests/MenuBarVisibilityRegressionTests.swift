import Foundation
import Testing

@Test func menuBarStatusItem_hasVisibleTemplateIconAndDevTitleFallback() throws {
    let appSource = try readProjectFile("Planit/PlanitApp.swift")

    #expect(appSource.contains("devStatusTitleEnvironmentKey"))
    #expect(appSource.contains("NSStatusItem.squareLength"))
    #expect(appSource.contains("image.isTemplate = true"))
    #expect(appSource.contains("button.toolTip = \"Calen\""))
    #expect(appSource.contains("button.title = showDevStatusTitle ? \" Calen\" : \"\""))
    #expect(appSource.contains("button.imagePosition = showDevStatusTitle ? .imageLeading : .imageOnly"))
    #expect(!appSource.contains("showPopoverIfPossible(retriesRemaining:"))
}

@Test func runDevStopsInstalledCopiesAndLaunchesVisibleDevApp() throws {
    let script = try readProjectFile("scripts/run-dev.sh")

    #expect(script.contains("kill_installed_calen_copies"))
    #expect(script.contains("/Applications/Calen.app/Contents/MacOS/Calen"))
    #expect(!script.contains("kill_orphaned_calendar_mcp_copies"))
    #expect(!script.contains("@cocal/google-calendar-mcp"))
    #expect(!script.contains("CALEN_OPEN_POPOVER_ON_LAUNCH"))
    #expect(script.contains("CALEN_SHOW_STATUS_TITLE=1"))
    #expect(script.contains("open -n --env CALEN_SHOW_STATUS_TITLE=1 \"$APP\""))
}

@Test func automaticReviewActivityMatching_doesNotLaunchExternalAI() throws {
    let classifierSource = try readProjectFile("Planit/Services/GoalActivityClassifier.swift")

    #expect(classifierSource.contains("automaticActivityAIClassificationEnabled"))
    #expect(classifierSource.contains("Self.automaticActivityAIClassificationEnabled"))
    #expect(!classifierSource.contains("let aiMatches = await classifyByAI(pendingAI, against: goals)"))
}

private func readProjectFile(_ relativePath: String) throws -> String {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let projectRoot = testsDirectory.deletingLastPathComponent()
    let fileURL = projectRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: fileURL, encoding: .utf8)
}
