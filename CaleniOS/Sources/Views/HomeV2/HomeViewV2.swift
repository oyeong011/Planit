#if os(iOS)
import SwiftUI

// MARK: - HomeViewV2 (Sprint B', v0.6 시안 정확 반영)
//
// Figma "호주 (1)" Section 1 / Home.png 톤. 기존 HomeView(v4 TimeBlocks 월그리드)와는 IA 가
// 다르므로 별도 파일로 둔다. RootView 가 v2 로 교체하기 전까진 빌드만 보장.
//
// 구조:
//  Calen 로고 → 7일 strip → "오늘의 일정" pill → 타임라인(InlineWakeRow + Drive +
//  ScheduleCard 3종) → BottomTabBar5

struct HomeViewV2: View {

    // 데모 데이터 — Sprint C 에서 ViewModel + SwiftData 연결로 교체.
    @State private var selected: Date = .now

    /// MainTabView 안에 embedded 될 때는 자체 BottomTabBar5 를 그리지 않는다.
    /// (기존 4탭 CustomTabBar 와 중복 방지)
    var showsOwnTabBar: Bool = false
    @State private var ownTab: BottomTabBar5.Tab = .home

    /// Sprint C — CloudKit 동기화 상태. coordinator 를 직접 구독.
    @ObservedObject private var sync = CloudKitSyncCoordinator.shared

    var body: some View {
        VStack(spacing: 0) {
            // 동기화 상태 배너 (offline/failed/syncing 일 때만 노출)
            SyncStatusBanner(status: sync.status)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sync.status)

            CalenLogoMini()

            WeekStripView(
                days: weekDays(around: selected),
                selected: selected,
                onSelect: { selected = $0 }
            )
            .padding(.top, 4)

            HStack {
                TodayPill()
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("8:00")
                            .font(.calenTimeMono)
                            .foregroundStyle(Color.calenTertiary)
                            .frame(width: 44, alignment: .trailing)
                        InlineWakeRowInner()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    DriveSegmentView(minutes: 20)
                        .padding(.horizontal, 24)

                    ScheduleCard(
                        time: "9:00",
                        tone: .work,
                        title: "직장",
                        bodyContent: .bullets([
                            "자간 맞추기",
                            "랜더링 돌리기",
                            "리깅 수정하기 → Paint Skin Weight 조절",
                            "텍스처 만들기",
                            "레퍼런스 찾기"
                        ]),
                        actions: ["업무 진행도 보기", "할 일 추가하기"]
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                    ScheduleCard(
                        time: "15:00",
                        tone: .meeting,
                        title: "거래처 회의",
                        bodyContent: .summary("일정 요약: 지난 9일 미팅에서 얘기한 디자인 컨펌"),
                        actions: ["지난 회의 요약 보기", "회의 내용 저장하기"]
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 6)

                    DriveSegmentView(minutes: 60)
                        .padding(.horizontal, 24)

                    ScheduleCard(
                        time: "18:00",
                        tone: .dinner,
                        title: "저녁식사",
                        bodyContent: .summary("일정 요약: 제인과 서클러키에서의 약속"),
                        actions: []
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
            .scrollIndicators(.hidden)

            if showsOwnTabBar {
                BottomTabBar5(selection: $ownTab)
            }
        }
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: - 주간 7일 (월 시작)

    private func weekDays(around date: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // 월요일 시작 (시안 strip이 MON 시작)
        let comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let weekStart = cal.date(from: comp) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }
}

// MARK: - Inline Wake (재사용 — InlineWakeRow 의 inner content 만)

private struct InlineWakeRowInner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max")
                .font(.system(.callout))
                .foregroundStyle(Color(hex: "#E8AC55"))
            Text("기상")
                .font(.calenBodyEmph)
                .foregroundStyle(Color.calenPrimary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview

#Preview("HomeV2 — Light") {
    HomeViewV2()
        .preferredColorScheme(.light)
}

#Preview("HomeV2 — Dynamic Type AX1") {
    HomeViewV2()
        .environment(\.dynamicTypeSize, .accessibility1)
}
#endif
