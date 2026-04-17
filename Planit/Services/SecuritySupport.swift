import CryptoKit
import Foundation

enum ExternalContextPolicy {
    private static let sensitiveCalendarKeywords = [
        "private", "personal", "secret", "sensitive", "medical", "health",
        "therapy", "doctor", "hospital", "bank", "finance", "legal",
        "개인", "비공개", "민감", "의료", "병원", "상담", "치료", "금융", "은행", "법률",
    ]

    static func isSensitiveCalendar(id: String, name: String) -> Bool {
        if UserDefaults.standard.stringArray(forKey: "planit.aiExcludedCalendarIDs")?.contains(id) == true {
            return true
        }

        let normalized = name.lowercased()
        return sensitiveCalendarKeywords.contains { normalized.contains($0) }
    }

    static func sanitizeUntrustedText(_ text: String, maxLength: Int) -> String {
        let sanitized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "```", with: "")
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let lowered = trimmed.lowercased()
                if lowered.hasPrefix("system:") ||
                   lowered.hasPrefix("assistant:") ||
                   lowered.hasPrefix("human:") ||
                   trimmed.hasPrefix("사용자:") ||
                   trimmed.hasPrefix("어시스턴트:") {
                    return "[filtered]"
                }
                return line
            }
            .joined(separator: " ")
            .replacingOccurrences(of: "[\\x00-\\x08\\x0B-\\x1F\\x7F]", with: "", options: .regularExpression)
        return String(sanitized.prefix(maxLength))
    }

    static func preview(userMessage: String, calendarContext: String, userContext: String, attachmentNames: [String]) -> String {
        var sections = [
            "User message:\n\(sanitizeUntrustedText(userMessage, maxLength: 1200))",
            "Calendar context:\n\(String(calendarContext.prefix(2000)))",
        ]
        if !userContext.isEmpty {
            sections.append("User context:\n\(String(userContext.prefix(1600)))")
        }
        if !attachmentNames.isEmpty {
            sections.append("Attachments:\n" + attachmentNames.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n---\n\n")
    }
}

enum AttachmentSecurity {
    static let maxAttachmentBytes = 20_971_520

    static func validateFile(url: URL, maxBytes: Int = maxAttachmentBytes) -> ChatAttachmentType? {
        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue <= maxBytes else { return nil }

        switch resolved.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp", "heic":
            return .image
        default:
            return nil
        }
    }
}

enum FileIntegrity {
    static func signature(for payload: Data, key: Data) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: key))
        return Data(code).base64EncodedString()
    }

    static func verify(_ payload: Data, signature expectedSignature: String, key: Data) -> Bool {
        guard let expectedCode = Data(base64Encoded: expectedSignature) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            expectedCode,
            authenticating: payload,
            using: SymmetricKey(data: key)
        )
    }
}

enum SignedFileStore {
    static func signatureURL(for dataURL: URL) -> URL {
        dataURL.deletingLastPathComponent()
            .appendingPathComponent(dataURL.lastPathComponent + ".hmac")
    }

    static func write(_ data: Data, to url: URL, key: Data) throws {
        try data.write(to: url, options: .atomic)
        let signature = FileIntegrity.signature(for: data, key: key)
        try signature.data(using: .utf8)?.write(to: signatureURL(for: url), options: .atomic)
    }

    static func readVerified(from url: URL, key: Data) throws -> Data? {
        let data = try Data(contentsOf: url)
        let sigURL = signatureURL(for: url)
        guard FileManager.default.fileExists(atPath: sigURL.path),
              let sigData = try? Data(contentsOf: sigURL),
              let signature = String(data: sigData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return FileIntegrity.verify(data, signature: signature, key: key) ? data : nil
    }
}
