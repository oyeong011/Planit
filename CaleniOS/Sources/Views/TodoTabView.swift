#if os(iOS)
import SwiftUI

// MARK: - TodoTabView
//
// 3탭 레이아웃의 두 번째 탭("할일").
// iOS v0.1.0 — **로컬 전용** (UserDefaults JSON via `LocalTodoStore`).
// Google Tasks / CalDAV 등 외부 동기화는 v0.2+에서.
struct TodoTabView: View {
    @StateObject private var store = LocalTodoStore()

    @State private var isAdding: Bool = false
    @State private var newTitle: String = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if store.todos.isEmpty && !isAdding {
                    emptyState
                } else {
                    todoList
                }
            }
            .navigationTitle("할일")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            isAdding = true
                        }
                        // 다음 런루프에서 포커스 (시트/필드 렌더 후)
                        DispatchQueue.main.async {
                            addFieldFocused = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("새 할일 추가")
                }
            }
        }
    }

    // MARK: List

    private var todoList: some View {
        List {
            if isAdding {
                Section {
                    HStack {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        TextField("할일을 입력하세요", text: $newTitle)
                            .focused($addFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(commitNew)
                        Button("추가", action: commitNew)
                            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Section {
                ForEach(store.todos) { todo in
                    TodoRow(todo: todo) {
                        store.toggle(todo)
                    }
                }
                .onDelete { offsets in
                    store.delete(at: offsets)
                }
            } header: {
                if !store.todos.isEmpty {
                    Text("\(remainingCount)개 남음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("할일이 비어있습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("오른쪽 위 + 버튼을 눌러 추가하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Helpers

    private var remainingCount: Int {
        store.todos.filter { !$0.isCompleted }.count
    }

    private func commitNew() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(title: trimmed)
        newTitle = ""
        withAnimation {
            isAdding = false
        }
        addFieldFocused = false
    }
}

// MARK: - TodoRow

private struct TodoRow: View {
    let todo: LocalTodo
    let toggleAction: () -> Void

    var body: some View {
        Button(action: toggleAction) {
            HStack(spacing: 12) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isCompleted ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(todo.title)
                    .strikethrough(todo.isCompleted, color: .secondary)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todo.title)
        .accessibilityValue(todo.isCompleted ? "완료됨" : "미완료")
        .accessibilityAddTraits(todo.isCompleted ? [.isSelected] : [])
    }
}
#endif
