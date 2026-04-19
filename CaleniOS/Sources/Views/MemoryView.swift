#if os(iOS)
import SwiftUI
@_exported import CalenShared

/// iOS Hermes 기억 탭 — **read-only**. 추가/수정/삭제는 macOS에서만.
/// macOS에서 CloudKit `HermesMemoryFactV1`으로 업로드한 기억을 최신순으로 표시.
struct MemoryView: View {

    // MARK: State

    @State private var memories: [MemoryFact] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var didLoadOnce: Bool = false

    private let fetcher: any MemoryFetching
    private let fetchLimit: Int

    // MARK: Init

    init(fetcher: (any MemoryFetching)? = nil, fetchLimit: Int = 50) {
        // 기본값은 실제 iOS fetcher. 프리뷰/테스트에서는 대체 구현 주입 가능.
        self.fetcher = fetcher ?? iOSMemoryFetcher()
        self.fetchLimit = fetchLimit
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Hermes 기억")
                .refreshable { await load() }
                .task {
                    guard !didLoadOnce else { return }
                    didLoadOnce = true
                    await load()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            if isLoading && memories.isEmpty {
                loadingState
            } else if let errorMessage, memories.isEmpty {
                errorState(errorMessage)
            } else if memories.isEmpty {
                emptyState
            } else {
                ForEach(memories) { fact in
                    MemoryRowView(fact: fact)
                }
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 40)
            Spacer()
        }
        .listRowBackground(Color.clear)
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

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("기억을 불러오지 못했습니다")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await fetcher.fetchRecentMemories(limit: fetchLimit)
            memories = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

struct MemoryRowView: View {
    let fact: MemoryFact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fact.category.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(.purple)
                    .cornerRadius(4)
                Spacer()
                Text(fact.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
