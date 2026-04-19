#if os(iOS)
import SwiftUI
import SwiftData

/// iOS Hermes 기억 탭 — **read-only**. 추가/수정/삭제는 macOS에서만.
/// Mac에서 CloudKit으로 동기화된 기억을 최신순으로 표시한다.
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
                }
            }
            .navigationTitle("Hermes 기억")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Mac에서 학습된 기억이 여기에 표시됩니다")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("iCloud 동기화가 완료되면 최신순으로 나타납니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
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
#endif
