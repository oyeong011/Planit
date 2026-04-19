#if os(iOS)
import SwiftUI

// MARK: - TodoTabView
//
// 3탭 레이아웃의 두 번째 탭("할일").
// 레퍼런스: `Calen-iOS/Calen/Features/Home/HomeView.swift`의 `ScheduleCard` + Empty state 패턴을
// Todo 카드 스타일로 이식.
// - 카드 배경 `.systemBackground` + rounded 12 + `calenCardShadow()`
// - 좌측 원형 체크 (미완료 stroke / 완료 fill calenBlue)
// - 상단 "할일" `calenDisplay` + N개 · 완료 M개 카운트
// - 빈 상태: checklist 아이콘 + 안내 + "+ 버튼으로 추가하기"
// - + 추가: toolbar trailing plus.circle.fill (calenBlue 28pt) → sheet
//
// 저장은 기존 `LocalTodoStore` (UserDefaults JSON) 그대로 사용.
struct TodoTabView: View {
    @StateObject private var store = LocalTodoStore()
    @State private var showAddSheet: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 배경 — groupedBackground로 카드가 떠 보이게
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showAddSheet) {
                AddTodoSheet(onAdd: { title in
                    store.add(title: title)
                })
                .presentationDetents([.height(220), .medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text("Calen")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.calenBlue)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.calenBlue)
            }
            .accessibilityLabel("새 할일 추가")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.todos.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    LazyVStack(spacing: 10) {
                        ForEach(store.todos) { todo in
                            TodoCard(todo: todo, onToggle: { store.toggle(todo) })
                                .padding(.horizontal, 16)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.delete(id: todo.id)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                                // 스와이프 액션을 위해 List 대신 VStack을 쓰는 경우에도 작동하도록
                                // contextMenu로 보조 경로 제공.
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(id: todo.id)
                                    } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Header (타이틀 + 카운트)

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("할일")
                .font(.calenDisplay)
                .foregroundStyle(Color.calenPrimary)

            Text(countLine)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var countLine: String {
        let total = store.todos.count
        let done  = store.todos.filter(\.isCompleted).count
        return "총 \(total)개 · 완료 \(done)개"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 52))
                .foregroundStyle(Color.calenBlue.opacity(0.4))
                .accessibilityHidden(true)

            Text("할일이 없어요")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            Text("오른쪽 위 + 버튼으로 추가하기")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - TodoCard
//
// 단일 할일 카드. 레퍼런스 `ScheduleCard`의 카드 컨테이너 스타일을 따름.
private struct TodoCard: View {
    let todo: LocalTodo
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // 원형 체크
                ZStack {
                    Circle()
                        .strokeBorder(
                            todo.isCompleted ? Color.calenBlue : Color(.systemGray3),
                            lineWidth: 2
                        )
                        .frame(width: 24, height: 24)
                    if todo.isCompleted {
                        Circle()
                            .fill(Color.calenBlue)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(todo.isCompleted ? .secondary : Color.calenPrimary)
                        .strikethrough(todo.isCompleted, color: .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(createdAtText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.systemBackground),
                in: RoundedRectangle(cornerRadius: CalenRadius.medium, style: .continuous)
            )
            .calenCardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todo.title)
        .accessibilityValue(todo.isCompleted ? "완료됨" : "미완료")
        .accessibilityHint("두 번 탭하여 완료 상태 전환")
    }

    private var createdAtText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: todo.createdAt)
    }
}

// MARK: - AddTodoSheet

private struct AddTodoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("할일을 입력하세요", text: $text)
                    .focused($focused)
                    .font(.system(size: 17))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: CalenRadius.medium, style: .continuous)
                    )
                    .calenCardShadow()
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                Spacer()

                Button(action: commit) {
                    Text("추가")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            trimmed.isEmpty ? Color.calenBlue.opacity(0.4) : Color.calenBlue,
                            in: RoundedRectangle(cornerRadius: CalenRadius.medium, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("새 할일")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .onAppear {
                DispatchQueue.main.async { focused = true }
            }
        }
    }

    private func commit() {
        let value = trimmed
        guard !value.isEmpty else { return }
        onAdd(value)
        dismiss()
    }
}
#endif
