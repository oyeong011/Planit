import Foundation
import OSLog

enum PlanitLoggers {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.planit.calen"

    static let crud = Logger(subsystem: subsystem, category: "crud")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let ai = Logger(subsystem: subsystem, category: "ai")
}

enum CRUDOperation: String {
    case create
    case update
    case delete
}

enum CRUDSource: String {
    case google
    case apple
    case local
    case todo
}

struct CRUDErrorNotice: Identifiable, Equatable {
    let id = UUID()
    let operation: CRUDOperation
    let source: CRUDSource
    let eventID: String?

    var message: String {
        let target = source == .todo ? "todo sync" : "\(source.rawValue) calendar"
        return "Could not \(operation.rawValue) \(target). Please try again."
    }

    var logMetadata: [String: String] {
        [
            "operation": operation.rawValue,
            "source": source.rawValue,
            "eventID": eventID ?? "none"
        ]
    }
}
