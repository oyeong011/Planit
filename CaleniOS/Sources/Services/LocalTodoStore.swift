#if os(iOS)
import Foundation
import SwiftUI

// MARK: - LocalTodoStore
//
// iOS v0.1.0 — Todo의 **로컬 영속화** 담당 (UserDefaults JSON).
// SwiftData/CloudKit 도입은 v0.2+로 연기. 지금은 로컬 single source of truth.
//
// - UserDefaults key: `calen-ios.todos.v1`
// - @MainActor ObservableObject — View에서 `@StateObject`로 바인딩.
@MainActor
final class LocalTodoStore: ObservableObject {
    static let defaultsKey = "calen-ios.todos.v1"

    @Published private(set) var todos: [LocalTodo] = []

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return }
        if let decoded = try? decoder.decode([LocalTodo].self, from: data) {
            self.todos = decoded
        }
    }

    private func save() {
        if let data = try? encoder.encode(todos) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: Mutations

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(LocalTodo(title: trimmed), at: 0)
        save()
    }

    func toggle(_ todo: LocalTodo) {
        guard let idx = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[idx].isCompleted.toggle()
        save()
    }

    func delete(at offsets: IndexSet) {
        todos.remove(atOffsets: offsets)
        save()
    }

    func delete(id: UUID) {
        todos.removeAll { $0.id == id }
        save()
    }
}
#endif
