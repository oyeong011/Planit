import Foundation

public enum ScheduleCreateDecision: Sendable, Equatable {
    case allowed
    case needsConfirmation
    case denied
}

public struct ScheduleCreateSource: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {
        case existingTodo
        case activeGoal
        case existingEvent
        case explicitUserRequestedBlock
        case explicitUserConfirmedBlock
    }

    public let kind: Kind
    public let title: String

    public init(kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }
}

public struct ScheduleCreateRequest: Sendable, Equatable {
    public let title: String
    public let allowedCreateSources: [ScheduleCreateSource]
    public let isConfirmed: Bool

    public init(
        title: String,
        allowedCreateSources: [ScheduleCreateSource],
        isConfirmed: Bool
    ) {
        self.title = title
        self.allowedCreateSources = allowedCreateSources
        self.isConfirmed = isConfirmed
    }
}

public enum ScheduleCreatePolicy {
    public static let maxTitleLength = 200

    public static func classify(_ request: ScheduleCreateRequest) -> ScheduleCreateDecision {
        let normalizedTitle = normalizeTitle(request.title)
        guard isValidTitle(normalizedTitle) else {
            return .denied
        }

        let matchingSources = request.allowedCreateSources.filter {
            normalizeTitle($0.title) == normalizedTitle
        }

        if matchingSources.contains(where: allowsImmediately) {
            return .allowed
        }

        if matchingSources.contains(where: needsExplicitConfirmation) {
            return request.isConfirmed ? .allowed : .needsConfirmation
        }

        if isSyntheticBlockTitle(normalizedTitle) {
            return .denied
        }

        return .denied
    }

    private static func allowsImmediately(_ source: ScheduleCreateSource) -> Bool {
        switch source.kind {
        case .existingTodo, .activeGoal, .existingEvent, .explicitUserConfirmedBlock:
            return true
        case .explicitUserRequestedBlock:
            return false
        }
    }

    private static func needsExplicitConfirmation(_ source: ScheduleCreateSource) -> Bool {
        source.kind == .explicitUserRequestedBlock
    }

    private static func isValidTitle(_ normalizedTitle: String) -> Bool {
        guard !normalizedTitle.isEmpty else { return false }
        return normalizedTitle.count <= maxTitleLength
    }

    private static func normalizeTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsedWhitespace = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsedWhitespace.lowercased()
    }

    private static func isSyntheticBlockTitle(_ normalizedTitle: String) -> Bool {
        let squashed = normalizedTitle
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        return syntheticBlockTitles.contains(squashed)
    }

    private static let syntheticBlockTitles: Set<String> = [
        "focustime",
        "focusblock",
        "rest",
        "resttime",
        "break",
        "breaktime",
        "depresstime",
        "deepwork",
        "deepworkblock",
        "휴식",
        "휴식시간",
        "딥워크",
        "딥워크블록"
    ]
}
