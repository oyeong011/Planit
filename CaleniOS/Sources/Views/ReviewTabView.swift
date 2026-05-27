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
    @State private var showEveningReview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                periodPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        eveningReviewSection
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

    @ViewBuilder
    private var eveningReviewSection: some View {
        let suggestions = viewModel.eveningReviewSuggestions()
        if shouldShowEveningReview || showEveningReview {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("저녁 리뷰", systemImage: "moon.stars.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !showEveningReview {
                        Button("보기") { showEveningReview = true }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                if showEveningReview || shouldShowEveningReview {
                    if suggestions.isEmpty {
                        Text("오늘 남은 미완료 일정이 없습니다.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(suggestions) { suggestion in
                            EveningSuggestionRow(suggestion: suggestion) {
                                Task { await viewModel.applyEveningReviewSuggestion(suggestion) }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.calenCardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        } else {
            Button {
                showEveningReview = true
            } label: {
                HStack {
                    Label("저녁 리뷰 보기", systemImage: "moon.stars")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.calenBlue)
                .padding(14)
                .background(Color.calenCardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var shouldShowEveningReview: Bool {
        Calendar.current.component(.hour, from: Date()) >= 21
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

private struct EveningSuggestionRow: View {
    let suggestion: EveningReviewSuggestion
    let onApply: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("내일 \(Self.timeFormatter.string(from: suggestion.targetStart))로 이동")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("적용", action: onApply)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.calenBlue, in: Capsule())
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - Preview

#Preview {
    ReviewTabView()
        .environmentObject(AppState())
}
#endif
