#if os(iOS)
import SwiftUI
@_exported import CalenShared

/// iOS Hermes 기억 탭 — **read-only**. 추가/수정/삭제는 macOS에서만.
/// macOS에서 CloudKit `HermesMemoryFactV1`으로 업로드한 기억을 최신순으로 표시.
///
/// UI 스타일은 디자인 토큰(`Color.calenBlue` + `calenCardShadow`) 기반으로 소폭 조정되어
/// SettingsView / CalendarTabView 와 룩 앤 필이 일치함. 기능/데이터 경로는 변경 없음.
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
        self.fetcher = fetcher ?? iOSMemoryFetcher()
        self.fetchLimit = fetchLimit
    }

    // MARK: Body

    var body: some View {
        content
            .navigationTitle("Hermes 기억")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task {
                guard !didLoadOnce else { return }
                didLoadOnce = true
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if isLoading && memories.isEmpty {
                loadingState
            } else if let errorMessage, memories.isEmpty {
                errorState(errorMessage)
            } else if memories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(memories) { fact in
                            MemoryRowView(fact: fact)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
            Text("불러오는 중…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 52))
                .foregroundStyle(Color.calenBlue.opacity(0.4))
            Text("Mac에서 학습된 기억이 여기에 표시됩니다")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("iCloud 동기화가 완료되면 최신순으로 나타납니다.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("기억을 불러오지 못했습니다")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .tint(Color.calenBlue)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(fact.category.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.cardPersonal.opacity(0.15))
                    )
                    .foregroundStyle(Color.cardPersonal)

                Spacer()

                Text(fact.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Text("\(Int(fact.confidence * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(confidenceColor)
            }

            Text(fact.key)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.calenPrimary)

            Text(fact.value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: CalenRadius.medium, style: .continuous)
        )
        .calenCardShadow()
    }

    private var confidenceColor: Color {
        if fact.confidence >= 0.75 { return Color.cardExercise }
        if fact.confidence >= 0.5  { return Color.cardMeal }
        return .secondary
    }
}
#endif
