import Foundation
import Testing

@Suite("Localization quality")
struct LocalizationQualityTests {
    @Test("settings surfaces are localized instead of English fallback text")
    func settingsSurfacesAreLocalized() throws {
        let english = try localizedStrings(for: "en")
        let keys = [
            "settings.hermes.patterns.count",
            "settings.hermes.clear.all",
            "settings.hermes.decisions.recent",
            "settings.hermes.outcome.partial",
            "settings.hermes.decision.summary.categorized",
            "settings.animal.enabled.title",
            "settings.animal.enabled.desc",
            "settings.animal.display.mode",
            "settings.animal.parade.count",
            "settings.animal.shape",
            "settings.animal.display.selected",
            "settings.animal.display.random",
            "settings.animal.display.parade",
            "panel.statistics",
            "statistics.title",
            "statistics.subtitle",
            "settings.wallpaper.card",
            "settings.wallpaper.desc",
            "settings.wallpaper.none",
            "memory.category.preference",
            "planning.intent.categorizeUntagged",
            "planning.action.move",
            "settings.hermes.fact.key.preferredBlockLength",
            "settings.hermes.fact.value.preferredBlockLength.short",
            "settings.hermes.fact.key.preferredMorningWork",
            "settings.hermes.fact.value.preferredMorningWork"
        ]

        for locale in try availableLocales() where locale != "en" {
            let table = try localizedStrings(for: locale)
            for key in keys {
                let value = try requiredValue(table, key: key, locale: locale)
                let englishValue = try requiredValue(english, key: key, locale: "en")
                #expect(!value.isEmpty, "\(locale) \(key) is empty")
                #expect(value != englishValue, "\(locale) \(key) is still using English fallback text")
            }
        }
    }

    @Test("known Hermes memory fact keys and values have localized entries")
    func hermesMemoryFactsHaveLocalizedEntries() throws {
        let factKeys = [
            "settings.hermes.fact.key.preferredMorningWork",
            "settings.hermes.fact.value.preferredMorningWork",
            "settings.hermes.fact.key.avoidsMorningWork",
            "settings.hermes.fact.value.avoidsMorningWork",
            "settings.hermes.fact.key.preferredEveningWork",
            "settings.hermes.fact.value.preferredEveningWork",
            "settings.hermes.fact.key.avoidsEveningWork",
            "settings.hermes.fact.value.avoidsEveningWork",
            "settings.hermes.fact.key.preferredBlockLength",
            "settings.hermes.fact.value.preferredBlockLength.short",
            "settings.hermes.fact.value.preferredBlockLength.deep",
            "settings.hermes.fact.key.meetingFatigue",
            "settings.hermes.fact.value.meetingFatigue",
            "settings.hermes.fact.key.wantsSlotSuggestions",
            "settings.hermes.fact.value.wantsSlotSuggestions",
            "settings.hermes.fact.key.urgentReschedulingNeeds",
            "settings.hermes.fact.value.urgentReschedulingNeeds"
        ]

        for locale in try availableLocales() {
            let table = try localizedStrings(for: locale)
            for key in factKeys {
                let value = try requiredValue(table, key: key, locale: locale)
                #expect(!value.isEmpty, "\(locale) \(key) is empty")
                if locale != "ko" {
                    #expect(!containsHangul(value), "\(locale) \(key) still contains Korean fallback text")
                }
            }
        }
    }

    @Test("Vietnamese screenshot labels render localized text")
    func vietnameseSettingsLabelsMatchExpectedLocalizedText() throws {
        let vietnamese = try localizedStrings(for: "vi")

        #expect(vietnamese["settings.hermes.patterns.count"] == "Mẫu người dùng học từ trò chuyện và thao tác (%d)")
        #expect(vietnamese["settings.hermes.clear.all"] == "Xóa tất cả")
        #expect(vietnamese["settings.hermes.decisions.recent"] == "Quyết định kế hoạch gần đây")
        #expect(vietnamese["memory.category.preference"] == "Sở thích")
        #expect(vietnamese["planning.intent.categorizeUntagged"] == "Phân loại sự kiện chưa phân loại")
        #expect(vietnamese["settings.hermes.fact.key.preferredBlockLength"] == "Độ dài khối ưa thích")
        #expect(vietnamese["settings.hermes.fact.value.preferredBlockLength.short"] == "Khối ngắn khoảng 30 phút")
        #expect(vietnamese["settings.animal.enabled.title"] == "Hiển thị động vật")
        #expect(vietnamese["settings.animal.display.mode"] == "Chế độ hiển thị")
        #expect(vietnamese["settings.animal.display.selected"] == "Động vật đã chọn")
    }

    @Test("localization files do not contain duplicate keys")
    func localizationFilesDoNotContainDuplicateKeys() throws {
        for locale in try availableLocales() {
            let duplicates = try duplicateKeys(for: locale)
            #expect(duplicates.isEmpty, "\(locale) has duplicate localization keys: \(duplicates.joined(separator: ", "))")
        }
    }

    @Test("categorized decision summaries are stored as stable tokens")
    func categorizedDecisionSummariesUseStableTokens() throws {
        let source = try projectFile("Planit/Views/SuggestionPreviewSheet.swift")

        #expect(source.contains(#"return "categorizedEvents:\(applied)""#))
        #expect(!source.contains("summary: String(format: NSLocalizedString(\"settings.hermes.decision.summary.categorized\""))
    }

    private func availableLocales() throws -> [String] {
        let resourceURL = repositoryRoot.appendingPathComponent("Planit/Resources")
        return try FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func localizedStrings(for locale: String) throws -> [String: String] {
        let url = repositoryRoot
            .appendingPathComponent("Planit/Resources")
            .appendingPathComponent("\(locale).lproj")
            .appendingPathComponent("Localizable.strings")
        let contents = try String(contentsOf: url, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"^\s*"((?:\\"|[^"])*)"\s*=\s*"((?:\\"|[^"])*)";"#)
        var table: [String: String] = [:]

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            table[unescape(String(text[keyRange]))] = unescape(String(text[valueRange]))
        }

        if table.isEmpty {
            throw LocalizationTestError.invalidStringsFile(locale)
        }
        return table
    }

    private func duplicateKeys(for locale: String) throws -> [String] {
        let url = repositoryRoot
            .appendingPathComponent("Planit/Resources")
            .appendingPathComponent("\(locale).lproj")
            .appendingPathComponent("Localizable.strings")
        let contents = try String(contentsOf: url, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"^\s*"((?:\\"|[^"])*)"\s*="#)
        var counts: [String: Int] = [:]

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let keyRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            counts[unescape(String(text[keyRange])), default: 0] += 1
        }

        return counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
    }

    private func requiredValue(_ table: [String: String], key: String, locale: String) throws -> String {
        guard let value = table[key] else {
            throw LocalizationTestError.missingKey(locale: locale, key: key)
        }
        return value
    }

    private func containsHangul(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(Int(scalar.value))
        }
    }

    private func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\\n"#, with: "\n")
            .replacingOccurrences(of: #"\\\\"#, with: #"\"#)
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

private enum LocalizationTestError: Error, CustomStringConvertible {
    case invalidStringsFile(String)
    case missingKey(locale: String, key: String)

    var description: String {
        switch self {
        case let .invalidStringsFile(locale):
            return "\(locale) Localizable.strings could not be parsed"
        case let .missingKey(locale, key):
            return "\(locale) is missing localization key \(key)"
        }
    }
}
