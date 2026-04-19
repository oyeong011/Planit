#if os(iOS)
import Foundation

// MARK: - LocalTodo
//
// iOS v0.1.0 **로컬 전용** Todo 모델.
// macOS `Planit/Models/TodoItem.swift`는 아직 `CalenShared`로 승격되지 않았기 때문에
// iOS 쪽에서는 별도 경량 모델을 사용한다. (Shared 승격 전까지의 한시적 구조.)
//
// SwiftData 대신 `UserDefaults`(JSON) 저장 — `LocalTodoStore` 참고.
struct LocalTodo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
#endif
