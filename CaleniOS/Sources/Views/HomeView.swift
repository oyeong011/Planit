#if os(iOS)
import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MemoryFactRecord.updatedAt, order: .reverse) private var facts: [MemoryFactRecord]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    quickActionsCard
                    memorySummaryCard
                }
                .padding(16)
            }
            .navigationTitle("Calen")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("오늘의 Hermes")
                    .font(.headline)
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
            Text(facts.isEmpty
                 ? "아직 학습된 패턴이 없습니다. Mac에서 대화하면 자동으로 여기에 반영됩니다."
                 : "\(facts.count)개의 사용자 패턴을 기억하고 있습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.08), Color.blue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }

    private var quickActionsCard: some View {
        VStack(spacing: 10) {
            ActionButton(
                title: "오늘 다시 짜기",
                icon: "calendar.badge.clock",
                tint: .purple
            ) {
                // TODO: Phase 3 — PlanningOrchestrator 호출
            }
            ActionButton(
                title: "빈 시간 채우기",
                icon: "plus.rectangle.on.rectangle",
                tint: .blue
            ) {
                // TODO: Phase 3
            }
        }
    }

    private var memorySummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 기억")
                .font(.headline)
            if facts.isEmpty {
                Text("없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(facts.prefix(3), id: \.id) { fact in
                    HStack {
                        Text(fact.key)
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Text("\(Int(fact.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .foregroundStyle(tint)
            .background(tint.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
#endif
