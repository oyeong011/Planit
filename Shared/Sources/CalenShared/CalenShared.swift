import Foundation

/// CalenShared — macOS, iOS, iPadOS가 공유하는 도메인 레이어.
///
/// 구조:
/// - Models/   : 순수 도메인 (HermesModels, GoalModels, TodoItem, CalendarEvent)
/// - Memory/   : SwiftData 영속 (HermesMemoryService, CloudKit sync)
/// - Planning/ : AI planning orchestrator (protocol 기반, 플랫폼 중립)
/// - Networking/: Google Calendar/OAuth
///
/// 플랫폼 전용 기능(AppKit, UIKit, EventKit, Sparkle)은 여기 들어오지 않음.
public enum CalenShared {
    public static let version = "1.0.0"
}
