#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - TodayReplanSheet
//
// v0.1.1 AI-2 — "오늘 다시 짜기" 풀스크린 시트.
//
// 구성:
//   - 상단: 제목 + Close 버튼
//   - 중단:
//       • isPlanning  → 로딩 스피너 + 진행 안내
//       • suggestions → 제안 카드 리스트 (accept/reject 스위치)
//   - 하단: "선택한 제안 적용" CTA (선택 개수 표시)
//   - 에러 배너 (오렌지 12% 배경 — QW1 동일 스타일)
//
// 사용:
//   HomeView에서 `.sheet(isPresented: $showReplan) { TodayReplanSheet(day:, repo:) }`
//   처럼 띄우고, 시트가 dismiss되면 HomeViewModel이 월 그리드를 리프레시한다.

struct TodayReplanSheet: View {

    // MARK: - Inputs

    /// 재계획 대상 날짜.
    let day: Date

    /// 시트 닫기 바인딩.
    @Binding var isPresented: Bool

    /// 적용 성공 후 HomeView가 그리드를 리프레시하도록 알리는 콜백.
    var onApplied: ((_ succeeded: Int, _ failed: Int) -> Void)?

    // MARK: - State

    @StateObject private var service: TodayReplanService

    /// 체크된 action id 집합. 기본값은 "전체 선택".
    @State private var accepted: Set<UUID> = []

    /// 초기 plan generate를 중복 호출 방지.
    @State private var hasStarted: Bool = false

    // MARK: - Init

    init(
        day: Date,
        repository: EventRepository,
        memoryFetcher: (any MemoryFetching)? = nil,
        isPresented: Binding<Bool>,
        onApplied: ((_ succeeded: Int, _ failed: Int) -> Void)? = nil
    ) {
        self.day = day
        self._isPresented = isPresented
        self.onApplied = onApplied
        self._service = StateObject(
            wrappedValue: TodayReplanService(
                repository: repository,
                memoryFetcher: memoryFetcher
            )
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.calenCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    if let err = service.error {
                        errorBanner(err)
                    }

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !service.suggestions.isEmpty {
                        applyCTA
                    }
                }
            }
            .navigationTitle(titleString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        isPresented = false
                    }
                    .foregroundStyle(Color.calenBlue)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await service.generatePlan(for: day) }
                        accepted = []
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.isPlanning || service.isApplying)
                    .accessibilityLabel("다시 생성")
                }
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await service.generatePlan(for: day)
            // 첫 로드 후 전체 선택
            accepted = Set(service.suggestions.map { $0.id })
        }
        .onChange(of: service.suggestions.map(\.id)) { _, newIds in
            // 새 plan이 들어오면 기본 전체 선택.
            accepted = Set(newIds)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var content: some View {
        if service.isPlanning {
            loadingState
        } else if !service.suggestions.isEmpty {
            suggestionList
        } else if service.error == nil {
            emptyState
        } else {
            // error는 배너로 이미 표시 중. placeholder.
            emptyState
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.3)
                .tint(Color.calenBlue)
            Text("AI가 오늘 일정을 다시 짜는 중…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(Color.calenBlue.opacity(0.7))
            Text("제안할 변경사항이 없습니다")
                .font(.system(size: 15, weight: .medium))
            Text("오늘 일정이 이미 잘 짜여 있어요.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let summary = service.suggestion?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
                if let rationale = service.suggestion?.rationale, !rationale.isEmpty {
                    Text(rationale)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                ForEach(service.suggestions) { action in
                    suggestionCard(action)
                        .padding(.horizontal, 20)
                }

                if let warnings = service.suggestion?.warnings, !warnings.isEmpty {
                    warningsBox(warnings)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }

                Color.clear.frame(height: 24)
            }
            .padding(.bottom, 12)
        }
    }

    private func suggestionCard(_ action: PlanningAction) -> some View {
        let isAccepted = accepted.contains(action.id)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: action))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.calenBlue)
                    Text(action.kindLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.calenBlue)
                }
                Text(action.diffSummary(formatter: Self.hourMinuteFormatter))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !action.reason.isEmpty {
                    Text(action.reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(
                get: { isAccepted },
                set: { newValue in
                    if newValue {
                        accepted.insert(action.id)
                    } else {
                        accepted.remove(action.id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Color.calenBlue)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.calenCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isAccepted ? Color.calenBlue.opacity(0.35) : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        )
    }

    private func warningsBox(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("참고 메시지")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(warnings.prefix(5).enumerated()), id: \.offset) { _, w in
                Text("• \(w)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var applyCTA: some View {
        let count = accepted.count
        return VStack(spacing: 0) {
            Divider()
            Button {
                applyAccepted()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(ctaLabel(count: count))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(count > 0 && !service.isApplying ? Color.calenBlue : Color.gray.opacity(0.4))
                )
            }
            .disabled(count == 0 || service.isApplying)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(Color.calenCream)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                service.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Actions

    private func applyAccepted() {
        let selected = service.suggestions.filter { accepted.contains($0.id) }
        guard !selected.isEmpty else { return }
        Task {
            let (ok, failed) = await service.applyAccepted(selected)
            onApplied?(ok, failed)
            if failed == 0 {
                // 전부 성공 시 시트 자동 닫기
                isPresented = false
            }
        }
    }

    // MARK: - Formatters / Strings

    private var titleString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 재계획"
        return f.string(from: day)
    }

    private func ctaLabel(count: Int) -> String {
        if service.isApplying {
            return "적용 중…"
        }
        return count == 0 ? "제안 선택" : "선택한 \(count)개 제안 적용"
    }

    private func iconName(for action: PlanningAction) -> String {
        switch action {
        case .createEvent: return "plus.circle.fill"
        case .moveEvent:   return "arrow.right.circle.fill"
        case .cancelEvent: return "xmark.circle.fill"
        }
    }

    private static let hourMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Preview

#Preview("TodayReplanSheet") {
    @Previewable @State var presented = true
    return Color.white
        .sheet(isPresented: $presented) {
            TodayReplanSheet(
                day: Date(),
                repository: FakeEventRepository(),
                isPresented: $presented
            )
            .presentationDetents([.large])
        }
}
#endif
