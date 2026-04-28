import Foundation
import Testing

@Suite("macOS privacy entitlements")
struct MacPrivacyEntitlementTests {
    @Test("shipping entitlements do not request user file areas")
    func shippingEntitlementsAvoidUserFileAreas() throws {
        for path in ["Planit/Planit.entitlements", "Planit/Planit-dev.entitlements"] {
            let keys = try entitlementKeys(path)

            #expect(!keys.contains("com.apple.security.files.user-selected.read-write"))
            #expect(!keys.contains("com.apple.security.files.downloads.read-write"))
            #expect(!keys.contains("com.apple.security.files.music.read-write"))
            #expect(!keys.contains("com.apple.security.files.pictures.read-write"))
            #expect(!keys.contains("com.apple.security.files.network-volumes.read-write"))
            #expect(!keys.contains("com.apple.security.network.server"))
            #expect(!keys.contains("com.apple.security.network.client"))
            #expect(!keys.contains("com.apple.security.automation.apple-events"))
        }
    }

    @Test("dev app bundle does not copy entitlement files as resources")
    func devBundleDoesNotCopyEntitlementsAsResources() throws {
        let script = try projectFile("scripts/run-dev.sh")

        #expect(!script.contains(#"cp "$PROJECT_DIR/Planit/Planit.entitlements" "$APP/Contents/Resources/""#))
        #expect(script.contains("rm -f \"$APP/Contents/Resources/Planit.entitlements\""))
        #expect(script.contains("--entitlements \"$PROJECT_DIR/Planit/Planit-dev.entitlements\""))
        #expect(script.contains("--sign -"))
    }

    @Test("release bundle signs ad hoc builds with production entitlements")
    func releaseBundleSignsAdHocBuildsWithProductionEntitlements() throws {
        let script = try projectFile("scripts/build-app.sh")

        #expect(script.contains("rm -f \"$APP_BUNDLE/Contents/Resources/Planit.entitlements\""))
        #expect(script.contains("--entitlements \"$PROJECT_DIR/Planit/Planit.entitlements\""))
        #expect(script.contains("--sign -"))
    }

    private func projectFile(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func entitlementKeys(_ path: String) throws -> Set<String> {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any] else { return [] }
        return Set(dictionary.keys)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
