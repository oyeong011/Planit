#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - HomeView (v4)
//
// TimeBlocks 스타일 메인 화면.
// 레이아웃: 월 네비 헤더 → (가로 스와이프) MonthGridView → WeekExpansionView + FAB.
//
// 구성:
//  - 상단 헤더: "2026년 4월" + prev/next 버튼, 우측 ⋯ / ⚙ 액션
//  - 요일 헤더 + 6×7 월 그리드 (TabView로 가로 스와이프 지원)
//  - 선택된 주의 확장 영역 (일정 카드 리스트)
//  - 하단 우측 FAB(⊕) → CalendarAddView 시트
//  - 이벤트 막대/카드 탭 → EventDetailSheet

struct HomeView: View {

    @StateObject private var viewModel = HomeViewModel()
    @Environment(\.modelContext) private var modelContext

    @State private var detailItem: ScheduleDisplayItem?
    @State private var showAddSheet = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.calenCream
                .ignoresSafeArea()

            VStack(spacing: 0) {
                monthHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                monthPager
                    .padding(.horizontal, 12)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                weekExpansion
            }

            // MARK: FAB
            fab
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .sheet(item: $detailItem) { item in
            EventDetailSheet(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddSheet) {
            CalendarAddView(preselectedDate: viewModel.selectedDate) { newSchedule in
                // Phase B M4-4: Google 로그인 시 GCal insert, 미로그인 시 SwiftData 로컬 저장.
                if viewModel.usingGoogleRepo {
                    viewModel.createOnGoogleCalendar(from: newSchedule)
                } else if let ctx = viewModel.modelContext {
                    ctx.insert(newSchedule)
                    try? ctx.save()
                    reloadAfterAdd()
                }
            }
        }
        // v5 Phase A: 풀스크린 주 시간 그리드 시트.
        // Phase B M4: 로그인 시 GoogleCalendarRepository, 미로그인 시 FakeEventRepository.
        .sheet(isPresented: $viewModel.showWeekSheet) {
            if let googleRepo = viewModel.googleRepository {
                WeekTimeGridSheet(
                    isPresented: $viewModel.showWeekSheet,
                    initialDate: viewModel.sheetAnchorDate,
                    repo: googleRepo
                )
            } else {
                WeekTimeGridSheet(
                    isPresented: $viewModel.showWeekSheet,
                    initialDate: viewModel.sheetAnchorDate,
                    repo: viewModel.eventRepository
                )
            }
        }
        // v5 Phase A: 풀스크린 주 시간 그리드 시트
        .sheet(isPresented: $viewModel.showWeekSheet) {
            WeekTimeGridSheet(
                isPresented: $viewModel.showWeekSheet,
                initialDate: viewModel.sheetAnchorDate,
                repo: viewModel.eventRepository
            )
        }
        .task {
            if viewModel.modelContext == nil {
                viewModel.modelContext = modelContext
            }
            #if DEBUG
            // QA: UserDefaults planit.devOpenWeekSheet=1 일 때 주 시트 자동 오픈.
            // 프로덕션 빌드에서는 이 블록이 컴파일되지 않음.
            if UserDefaults.standard.bool(forKey: "planit.devOpenWeekSheet") {
                try? await Task.sleep(nanoseconds: 400_000_000)
                viewModel.sheetAnchorDate = viewModel.selectedDate
                viewModel.showWeekSheet = true
            }
            #endif
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Text(monthTitleString)
                .font(.calenMonthTitle)
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 6) {
                navButton(icon: "chevron.left") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.goToPreviousMonth()
                    }
                }
                navButton(icon: "chevron.right") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.goToNextMonth()
                    }
                }
                navButton(icon: "ellipsis") {
                    // placeholder: 필터/정렬 메뉴 v0.1.1
                }
            }
        }
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.calenBlue)
                .frame(width: 34, height: 34)
                .background(Color.calenBlue.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var monthTitleString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월"
        return fmt.string(from: viewModel.currentMonth)
    }

    // MARK: - Month Pager (가로 스와이프)

    private var monthPager: some View {
        // TabView(.page) + 3슬롯 슬라이딩 윈도우.
        // selection 변경이 사용자의 스와이프로 발생했을 때 ViewModel의 currentMonth를
        // 이전/다음 월로 맞춘다.
        TabView(selection: swipeBinding) {
            ForEach(-1...1, id: \.self) { offset in
                let month = shiftedMonth(by: offset)
                MonthGridView(
                    monthAnchor: month,
                    schedules: viewModel.schedulesInMonth,
                    selectedDate: viewModel.selectedDate,
                    expandedWeekStart: viewModel.expandedWeekStart,
                    onTapDate: { date in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.tapDate(date)
                        }
                    },
                    onTapEvent: { item in
                        detailItem = item
                    }
                )
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: monthGridHeight)
    }

    /// 월 그리드 높이. DayCell minHeight(92pt) × 6행 + 요일 헤더 + 간격 여유.
    private var monthGridHeight: CGFloat { 92 * 6 + 36 }

    /// TabView selection 바인딩. 사용자 스와이프(offset != 0)를 감지해 월 이동 후 0으로 리셋.
    private var swipeBinding: Binding<Int> {
        Binding(
            get: { 0 },
            set: { newValue in
                guard newValue != 0 else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if newValue > 0 {
                        viewModel.goToNextMonth()
                    } else {
                        viewModel.goToPreviousMonth()
                    }
                }
            }
        )
    }

    private func shiftedMonth(by offset: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: offset, to: viewModel.currentMonth)
            ?? viewModel.currentMonth
    }

    // MARK: - Week Expansion

    private var weekExpansion: some View {
        Group {
            if let weekStart = viewModel.expandedWeekStart {
                WeekExpansionView(
                    weekStart: weekStart,
                    groups: viewModel.weekGroups(starting: weekStart),
                    selectedDate: viewModel.selectedDate,
                    onTapEvent: { item in
                        detailItem = item
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.expandedWeekStart)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.calenBlue, in: Circle())
                .calenFloatingShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("새 일정 추가")
    }

    // MARK: - Actions

    private func reloadAfterAdd() {
        viewModel.reloadSchedules()
    }
}

// MARK: - Previews

#Preview("Home v4") {
    HomeView()
        .modelContainer(for: Schedule.self, inMemory: true)
}
#endif
