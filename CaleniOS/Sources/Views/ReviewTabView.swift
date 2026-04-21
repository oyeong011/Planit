#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - ReviewTabView
//
// iOS v0.1.1 Review — 4번째 탭 루트. 일/주/월 세그먼티드 피커 + 5개 카드.
// 데이터 허브는 `ReviewViewModel` (@StateObject).
//
// 상단: 세그먼티드 picker
// 본문: ScrollView + LazyVStack(spacing 12) — 카드 5개
//   1. CompletionRateCard
//   2. CategoryTimeCard
//   3. HabitStreakCard
//   4. GrassMapCard
//   5. AISuggestionCard

struct ReviewTabView: View {

    @StateObject private var viewModel = ReviewViewModel()

    // 비동기 로드된 habit/grass 데이터. period 변경 시 재로드.
    @State private var habitDays: [DaySummary] = []
    @State private var grassDays: [GrassDay] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                periodPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        completionCard
                        categoryCard
                        habitCard
                        grassCard
                        aiCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await reloadAll()
                }
            }
            .background(Color.calenCream.ignoresSafeArea())
            .navigationTitle("리뷰")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            // 최초 진입 시 한 번 로드.
            await reloadAll()
        }
        .onChange(of: viewModel.period) { _, _ in
            Task { await reloadAll() }
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("기간", selection: $viewModel.period) {
            ForEach(ReviewPeriod.allCases, id: \.self) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Cards

    private var completionCard: some View {
        let data = viewModel.completion()
        return CompletionRateCard(
            done: data.done,
            total: data.total,
            rate: data.rate,
            periodLabel: periodLabel(viewModel.period)
        )
    }

    private var categoryCard: some View {
        CategoryTimeCard(minutesByCategory: viewModel.categoryMinutes())
    }

    private var habitCard: some View {
        HabitStreakCard(days: habitDays)
    }

    private var grassCard: some View {
        GrassMapCard(days: grassDays)
    }

    private var aiCard: some View {
        AISuggestionCard(
            summary: viewModel.aiSummary,
            isLoading: viewModel.isLoadingSummary,
            error: viewModel.aiError
        ) {
            Task { await viewModel.regenerateAISummary() }
        }
    }

    // MARK: - Reload

    private func reloadAll() async {
        await viewModel.refresh()
        async let hab = viewModel.recentHabitDays()
        async let grass = viewModel.grassDays(dayCount: 30)
        let (h, g) = await (hab, grass)
        self.habitDays = h
        self.grassDays = g
    }

    private func periodLabel(_ p: ReviewPeriod) -> String {
        switch p {
        case .day:   return "오늘"
        case .week:  return "이번 주"
        case .month: return "이번 달"
        }
    }
}

// MARK: - Preview

#Preview {
    ReviewTabView()
        .environmentObject(AppState())
}
#endif
