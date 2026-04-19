import SwiftUI
import SwiftData

struct MemoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MemoryFactRecord.updatedAt, order: .reverse) private var facts: [MemoryFactRecord]

    var body: some View {
        NavigationStack {
            List {
                if facts.isEmpty {
                    emptyState
                } else {
                    ForEach(facts, id: \.id) { fact in
                        MemoryRowView(fact: fact)
                    }
                    .onDelete(perform: deleteFacts)
                }
            }
            .navigationTitle("Hermes 기억")
            .toolbar {
                if !facts.isEmpty {
                    Button(role: .destructive) {
                        clearAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("아직 학습된 패턴이 없습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Mac에서 대화하면 이곳에 자동 동기화됩니다 (iCloud).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private func deleteFacts(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(facts[idx])
        }
        try? context.save()
    }

    private func clearAll() {
        try? context.delete(model: MemoryFactRecord.self)
        try? context.save()
    }
}

struct MemoryRowView: View {
    let fact: MemoryFactRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fact.categoryRaw)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(.purple)
                    .cornerRadius(4)
                Spacer()
                Text("\(Int(fact.confidence * 100))%")
                    .font(.caption.monospaced())
                    .foregroundStyle(confidenceColor)
            }
            Text(fact.key)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
            Text(fact.value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var confidenceColor: Color {
        if fact.confidence >= 0.75 { return .green }
        if fact.confidence >= 0.5 { return .orange }
        return .secondary
    }
}
