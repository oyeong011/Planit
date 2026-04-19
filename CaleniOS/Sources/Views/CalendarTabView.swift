#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - CalendarTabView
//
// 3탭 레이아웃의 첫 번째 탭("오늘").
// 레퍼런스: `Calen-iOS/Calen/Features/Calendar/CalendarView.swift`의
//   - 월 네비게이션 헤더 (년·월 + prev/next chevron 36×36 systemGray6 circle)
//   - 7×N LazyVGrid (요일 라벨 + DayCell)
//   - 일정 리스트 (ScheduleListCard)
//   - FAB (56×56 calenBlue + floating shadow)
//   - Empty State (calendar.badge.plus + 안내 문구)
// 를 Google Calendar 연동 기반에 맞춰 적용.
//
// v0.1.0 P0:
//   - 이벤트 데이터 로드는 AUTH/SYNC 팀장 연결 후 활성화 — 현재 `@State events = []`
//   - FAB는 로그인 상태일 때만 표시 + toast placeholder
//   - 미로그인 상태에서는 "로그인 안내" 빈 상태(설정 탭으로 이동 버튼).
//
// v1 overlap 버그 근본 수정:
//   - `.navigationBarTitleDisplayMode(.large)` + 하단 VStack 으로 겹쳤던 부분을
//     `.inline` + `toolbar { leading "Calen" 로고 }` 로 분리.
//   - ScrollView 내부 VStack(spacing: 0)에 명시적 padding / Divider로 단을 구분.
struct CalendarTabView: View {

    /// 상위 RootTabView에서 관리하는 선택된 탭 인덱스. "로그인" 버튼에서 사용.
    @Binding var selectedTab: Int

    // MARK: State

    /// 선택된 날짜 (일정 목록 + grid 선택 highlight).
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// 현재 표시 중인 월(1일 기준).
    @State private var currentMonth: Date = Calendar.current.startOfDay(for: Date())

    /// v0.1.0 P0 — 실제 이벤트 로드는 AUTH 팀장 PR 이후 연결.
    /// 빈 배열이면 "로그인 후 이벤트 표시" 빈 상태를 보여준다.
    @State private var events: [CalendarEvent] = []

    /// placeholder — 실제 값은 AUTH 팀장의 `iOSGoogleAuthManager.isAuthenticated` 연결.
    @State private var isLoggedIn: Bool = false

    /// FAB 탭 시 띄우는 toast("기능 준비중").
    @State private var showComingSoonToast: Bool = false

    /// 한국어 요일 라벨 (일 → 토).
    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // MARK: Main scroll
                ScrollView {
                    VStack(spacing: 0) {
                        monthHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 16)

                        calendarGrid
                            .padding(.horizontal, 12)

                        Divider()
                            .padding(.top, 16)
                            .padding(.horizontal, 20)

                        dailyScheduleList
                            .padding(.top, 4)
                    }
                }

                // MARK: FAB (로그인 상태에서만)
                if isLoggedIn {
                    addButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                        .transition(.scale.combined(with: .opacity))
                }

                // MARK: Coming-soon toast
                if showComingSoonToast {
                    toast("기능 준비중")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 100)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .animation(.easeInOut(duration: 0.2), value: showComingSoonToast)
        }
    }

    // MARK: - Toolbar (Calen 브랜드 로고)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text("Calen")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.calenBlue)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Text(currentMonthTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 4) {
                monthNavButton(icon: "chevron.left") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentMonth = shift(month: currentMonth, by: -1)
                    }
                }
                .accessibilityLabel("이전 달")

                monthNavButton(icon: "chevron.right") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentMonth = shift(month: currentMonth, by: 1)
                    }
                }
                .accessibilityLabel("다음 달")
            }
        }
    }

    @ViewBuilder
    private func monthNavButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.calenBlue)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var currentMonthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월"
        return fmt.string(from: currentMonth)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            // Weekday label row
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(weekdayColor(index: index))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }

            // Day cells
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(0..<datesInMonth.count, id: \.self) { index in
                    if let date = datesInMonth[index] {
                        DayCell(
                            date: date,
                            isSelected: isSameDay(date, selectedDate),
                            isToday: isSameDay(date, Date()),
                            dotColor: dotColor(for: date),
                            columnIndex: index % 7
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDate = Calendar.current.startOfDay(for: date)
                            }
                        }
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    }

    private func weekdayColor(index: Int) -> Color {
        switch index {
        case 0: return .red
        case 6: return Color.calenBlue
        default: return .secondary
        }
    }

    // MARK: - Daily schedule list

    private var dailyScheduleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedDateTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(eventsForSelectedDate.count)개")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if eventsForSelectedDate.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(eventsForSelectedDate) { event in
                        ScheduleListCard(event: event)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 100) // FAB clearance
            }
        }
    }

    private var selectedDateTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일 (E)"
        return fmt.string(from: selectedDate)
    }

    // MARK: - Empty State
    //
    // v0.1.0 P0 — 로그인 전후 다른 메시지.
    // (레퍼런스의 "+ 버튼을 눌러 일정을 추가해보세요" 카피는 Google Calendar 연동 후 의미가 있기에
    //  로그인 상태에서만 사용. 미로그인 시에는 설정 탭으로 이동 버튼을 제공.)
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 38))
                .foregroundStyle(Color.calenBlue.opacity(0.4))
                .accessibilityHidden(true)

            Text("이 날의 일정이 없어요")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            if isLoggedIn {
                Text("일정을 추가해 보세요")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.tertiaryLabel))
            } else {
                Text("로그인 후 동기화됩니다")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(.tertiaryLabel))

                Button {
                    // 설정 탭으로 이동 (index 2).
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 2
                    }
                } label: {
                    Text("로그인")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.calenBlue))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityLabel("설정에서 Google 로그인")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - FAB

    private var addButton: some View {
        Button {
            // v0.1.0 — 이벤트 추가 sheet 미구현. 토스트로 placeholder.
            withAnimation {
                showComingSoonToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation {
                    showComingSoonToast = false
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.calenBlue, in: Circle())
        }
        .calenFloatingShadow()
        .buttonStyle(.plain)
        .accessibilityLabel("일정 추가 (준비중)")
    }

    // MARK: - Toast

    @ViewBuilder
    private func toast(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.black.opacity(0.8))
            )
    }

    // MARK: - Derived data

    private var datesInMonth: [Date?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: currentMonth),
              let firstOfMonth = cal.dateInterval(of: .day, for: interval.start)?.start
        else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: firstOfMonth) // 1=Sun ... 7=Sat
        let leadingEmpty = (firstWeekday - cal.firstWeekday + 7) % 7
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in 0..<daysInMonth {
            cells.append(cal.date(byAdding: .day, value: day, to: firstOfMonth))
        }
        // 주 단위로 정렬되도록 끝을 nil로 padding
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var eventsForSelectedDate: [CalendarEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.startDate, inSameDayAs: selectedDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func dotColor(for date: Date) -> Color? {
        let cal = Calendar.current
        guard let first = events.first(where: { cal.isDate($0.startDate, inSameDayAs: date) }) else {
            return nil
        }
        return Color(hex: first.colorHex)
    }

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

    private func shift(month: Date, by delta: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month
    }
}

// MARK: - DayCell
//
// 레퍼런스 `CalendarView.swift`의 `DayCell`을 그대로 이식.
// - 선택: calenBlue 원형 fill + 흰 숫자
// - 오늘: calenBlue strokeBorder (선택 안 됐을 때)
// - 일정 dot: 각 날짜 아래 5×5 원 (해당 카테고리 컬러)
private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let dotColor: Color?
    let columnIndex: Int

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var textColor: Color {
        if isSelected        { return .white }
        if isToday           { return Color.calenBlue }
        if columnIndex == 0  { return .red }
        if columnIndex == 6  { return Color.calenBlue }
        return .primary
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.calenBlue)
                        .frame(width: 34, height: 34)
                } else if isToday {
                    Circle()
                        .strokeBorder(Color.calenBlue, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }

                Text(dayNumber)
                    .font(.system(size: 15, weight: (isToday || isSelected) ? .bold : .regular))
                    .foregroundStyle(textColor)
            }
            .frame(width: 34, height: 34)

            // 일정 dot
            Circle()
                .fill(dotColor ?? Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(Self.accessibilityLabel(for: date, isSelected: isSelected, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static func accessibilityLabel(for date: Date, isSelected: Bool, isToday: Bool) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일 EEEE"
        var label = fmt.string(from: date)
        if isToday { label = "오늘, " + label }
        if isSelected { label = label + " (선택됨)" }
        return label
    }
}

// MARK: - ScheduleListCard
//
// 레퍼런스 `CalendarView.swift`의 `ScheduleListCard`를 `CalendarEvent` 기반으로 이식.
// - 좌측 4px color bar (colorHex → Color)
// - 제목 + 시간 + 위치
// - `calenCardShadow()` + rounded 12 + systemBackground
private struct ScheduleListCard: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Category colour bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.colorHex))
                .frame(width: 4)
                .frame(minHeight: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: event.colorHex))

                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    if event.isAllDay {
                        Text("종일")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: event.colorHex))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color(hex: event.colorHex).opacity(0.12),
                                in: Capsule()
                            )
                    }
                }

                // Time range
                Text(timeRangeString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // Location
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: CalenRadius.medium, style: .continuous)
        )
        .calenCardShadow()
        .accessibilityElement(children: .combine)
    }

    private var timeRangeString: String {
        if event.isAllDay { return "종일" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }
}
#endif
