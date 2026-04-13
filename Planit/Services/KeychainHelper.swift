import Foundation

/// File-based secure storage in Application Support (avoids Keychain password prompts)
enum KeychainHelper {
    private static var storageDir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Planit/tokens", isDirectory: true)
    }

    private static func ensureDir() {
        let dir = storageDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                      attributes: [.posixPermissions: 0o700])
        }
    }

    private static func filePath(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return storageDir.appendingPathComponent(safe)
    }

    @discardableResult
    static func save(key: String, value: String) -> Bool {
        ensureDir()
        guard let data = value.data(using: .utf8) else { return false }
        let path = filePath(for: key)
        do {
            try data.write(to: path, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            return true
        } catch {
            return false
        }
    }

    static func load(key: String) -> String? {
        let path = filePath(for: key)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let path = filePath(for: key)
        do {
            try FileManager.default.removeItem(at: path)
            return true
        } catch {
            return false
        }
    }
}
