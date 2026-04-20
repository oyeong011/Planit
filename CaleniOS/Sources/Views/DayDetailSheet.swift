#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - DayDetailSheet
//
// PRD v0.1 §4.2 — WeekTimeGridSheet를 대체하는 단일일 상세 시트.
// TimeBlocks 기조 유지하되 iPhone 세로에서 hour grid의 구조적 복잡성 포기.
//
// 구성:
//   [< 4월 20일 월요일 >]                     ← 상단 네비 + 닫기
//   - 색상 바 + 제목 + 시간 + 위치            ← 이벤트 카드 리스트 (시간 오름차순)
//   - ...
//   [빈 상태: "일정이 없어요"]                  ← 0개일 때
//                                    (+)    ← FAB (새 일정 추가)
//
// 인터랙션:
//   - 카드 탭 → EventEditSheet
//   - 가로 스와이프 → 이전/다음 날 전환
//   - 바깥 탭/swipe-down → dismiss

struct DayDetailSheet<Repo: iOSEventRepository>: View {

    @Binding var isPresented: Bool

    /// 현재 표시 중인 날짜. 스와이프로 이전/다음 날 이동.
    @State var day: Date

    @ObservedObject var repo: Repo

    /// 블록(또는 카드) 탭 시 편집 시트 요청.
    var onRequestEdit: (CalendarEvent) -> Void = { _ in }

    /// + 버튼 탭 — 새 일정 시트 요청.
    var onRequestAdd: (Date) -> Void = { _ in }

    @State private var showingDeleteConfirm: CalendarEvent?
    @State private var swipeOffset: CGFloat = 0

    private let cal = Calendar.current

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                background
                content
                fab
            }
            .toolbar { toolbarContent }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .gesture(horizontalSwipeGesture)
    }

    // MARK: - Background

    private var background: some View {
        Color.calenCream
            .ignoresSafeArea()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let events = eventsForDay

        if events.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(events, id: \.id) { event in
                        EventCard(event: event, onTap: { onRequestEdit(event) })
                            .contextMenu {
                                Button(role: .destructive) {
                                    showingDeleteConfirm = event
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 96) // FAB clearance
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.calenBlue.opacity(0.4))
            Text("일정이 없어요")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text("+ 버튼으로 추가해보세요")
                .font(.system(size: 13))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { goToPreviousDay() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.calenBlue)
                    .frame(width: 40, height: 40)
                    .background(Color.calenBlue.opacity(0.10), in: Circle())
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("이전 날")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(dayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text(weekdayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                Button { goToNextDay() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.calenBlue)
                        .frame(width: 40, height: 40)
                        .background(Color.calenBlue.opacity(0.10), in: Circle())
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("다음 날")

                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("닫기")
            }
        }
    }

    // MARK: - FAB

    private var fab: some View {
        Button { onRequestAdd(day) } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.calenBlue, in: Circle())
                .shadow(color: Color.calenBlue.opacity(0.30), radius: 14, x: 0, y: 6)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel("새 일정 추가")
    }

    // MARK: - Gestures / Navigation

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 2 else { return }
                if dx > 0 { goToPreviousDay() } else { goToNextDay() }
            }
    }

    private func goToPreviousDay() {
        if let prev = cal.date(byAdding: .day, value: -1, to: day) {
            withAnimation(.easeInOut(duration: 0.2)) { day = prev }
        }
    }

    private func goToNextDay() {
        if let next = cal.date(byAdding: .day, value: 1, to: day) {
            withAnimation(.easeInOut(duration: 0.2)) { day = next }
        }
    }

    // MARK: - Data

    private var eventsForDay: [CalendarEvent] {
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return repo.events
            .filter { $0.endDate > start && $0.startDate < end }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
    }

    private var dayTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        return fmt.string(from: day)
    }

    private var weekdayText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "EEEE"
        return fmt.string(from: day)
    }
}

// MARK: - EventCard

private struct EventCard: View {
    let event: CalendarEvent
    var onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(categoryColor.opacity(0.95))
                .frame(width: 4)
                .frame(minHeight: 58)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Image(systemName: event.isAllDay ? "sun.max.fill" : "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(categoryColor)
                    Text(timeRangeText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let loc = event.location, !loc.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(.tertiaryLabel))
                        Text(loc)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.calenCardSurface)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var categoryColor: Color {
        Color(hex: event.colorHex) ?? .calenBlue
    }

    private var timeRangeText: String {
        if event.isAllDay { return "종일" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate)) – \(fmt.string(from: event.endDate))"
    }
}

// MARK: - Preview

#Preview("DayDetailSheet") {
    let repo = FakeEventRepository()
    return DayDetailSheet(
        isPresented: .constant(true),
        day: Date(),
        repo: repo
    )
}
#endif
