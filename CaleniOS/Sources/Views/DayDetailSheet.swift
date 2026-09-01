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
                        EventCard(
                            event: event,
                            onTap: { onRequestEdit(event) },
                            onToggleCompletion: {
                                let updated = event.settingCompleted(!event.isCompleted)
                                persistChange(from: event, to: updated)
                            },
                            onMove: { updated in
                                persistChange(from: event, to: updated)
                            },
                            onResize: { updated in
                                persistChange(from: event, to: updated)
                            }
                        )
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
            Text("home.day.empty")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text("home.day.empty.hint")
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
        .accessibilityLabel(Text("home.fab.add"))
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

    private func persistChange(from original: CalendarEvent, to updated: CalendarEvent) {
        guard !original.isReadOnly else { return }
        repo.replaceInMemory(updated)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            do {
                let saved = try await repo.update(updated)
                repo.replaceInMemory(saved)
            } catch {
                repo.replaceInMemory(original)
                print("[DayDetailSheet] update event error: \(error)")
            }
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

// MARK: - EventCard (Quick Win: macOS DailyDetail 패턴 — 시간 rail + 색상 바 + 카드)

private struct EventCard: View {
    let event: CalendarEvent
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
    var onMove: (CalendarEvent) -> Void
    var onResize: (CalendarEvent) -> Void

    @GestureState private var dragOffset: CGFloat = 0
    @GestureState private var resizeOffset: CGFloat = 0

    private let pointsPerHour: CGFloat = 72

    var body: some View {
        // Planit 톤: 좌측은 시간 rail(흰), 우측은 카테고리 fill 큰 영역.
        // 다일/일반 모두 한 줄 카드. 카테고리 fill이 카드의 시각적 무게를 담당.
        HStack(spacing: 0) {
            // 좌측 시간 rail (흰색 배경)
            VStack(alignment: .leading, spacing: 3) {
                if event.isAllDay {
                    Text("종일")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(fillTextColor)
                } else {
                    Text(startTimeText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(endTimeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 64, alignment: .leading)
            .padding(.leading, 14)
            .padding(.vertical, 14)
            .background(Color.calenCardSurface)

            // 우측 카테고리 fill 영역 (제목 + 카테고리 + 위치 + 체크 + 핸들)
            ZStack(alignment: .leading) {
                Rectangle().fill(fillColor)

                HStack(alignment: .center, spacing: 8) {
                    if canAdjustTime {
                        moveHandle
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(event.isCompleted ? Color.secondary : fillTextColor)
                            .strikethrough(event.isCompleted)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            Text(categoryLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(fillTextColor.opacity(0.85))
                            if let loc = event.location, !loc.isEmpty {
                                Text("·")
                                    .foregroundStyle(fillTextColor.opacity(0.5))
                                Text(loc)
                                    .font(.system(size: 11))
                                    .foregroundStyle(fillTextColor.opacity(0.75))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Button(action: {
                        onToggleCompletion()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        Image(systemName: event.isCompleted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(event.isCompleted ? fillTextColor : fillTextColor.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(event.isReadOnly)
                    .opacity(event.isReadOnly ? 0.35 : 1.0)
                    .accessibilityLabel(event.isCompleted ? "완료 취소" : "완료 표시")

                    if canAdjustTime {
                        resizeHandle
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .frame(minHeight: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .opacity(event.isCompleted ? 0.6 : 1.0)
        .offset(y: dragOffset)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var canAdjustTime: Bool {
        !event.isAllDay && !event.isReadOnly
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, state, _ in
                guard canAdjustTime, abs(value.translation.height) > abs(value.translation.width) else { return }
                state = value.translation.height
            }
            .onEnded { value in
                guard canAdjustTime, abs(value.translation.height) > abs(value.translation.width) else { return }
                let moved = CalendarInteractionMath.movedTimeRange(
                    start: event.startDate,
                    end: event.endDate,
                    verticalTranslation: Double(value.translation.height),
                    pointsPerHour: Double(pointsPerHour),
                    calendar: Calendar.current
                )
                var updated = event
                updated.startDate = moved.start
                updated.endDate = moved.end
                onMove(updated)
            }
    }

    private var moveHandle: some View {
        HStack(spacing: 3) {
            Capsule()
                .frame(width: 2, height: 18)
            Capsule()
                .frame(width: 2, height: 18)
            Capsule()
                .frame(width: 2, height: 18)
        }
        .foregroundStyle(fillTextColor.opacity(0.45))
        .frame(width: 26, height: 36)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .accessibilityLabel("시간 이동")
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.and.down")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(categoryColor)
            .frame(width: 34, height: 34)
            .background(categoryColor.opacity(0.12), in: Circle())
            .offset(y: resizeOffset)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .updating($resizeOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        guard canAdjustTime else { return }
                        var updated = event
                        updated.endDate = CalendarInteractionMath.resizedEnd(
                            start: event.startDate,
                            end: event.endDate,
                            verticalTranslation: Double(value.translation.height),
                            pointsPerHour: Double(pointsPerHour),
                            minimumMinutes: 15,
                            calendar: Calendar.current
                        )
                        onResize(updated)
                    }
            )
            .accessibilityLabel("시간 길이 조절")
    }

    private var categoryColor: Color { Color(hex: event.colorHex) ?? .calenBlue }

    /// Planit 톤 옅은 fill (카드 우측 영역 배경).
    private var fillColor: Color {
        switch event.colorHex.uppercased() {
        case "#F56691": return .categoryFillWork
        case "#3B82F6", "#3A82F6": return .categoryFillMeeting
        case "#FAC430": return .categoryFillMeal
        case "#40C786": return .categoryFillExercise
        case "#9A5CE8": return .categoryFillPersonal
        default: return .categoryFillGeneral
        }
    }

    /// fill 위에 올리는 짙은 텍스트 색.
    private var fillTextColor: Color {
        switch event.colorHex.uppercased() {
        case "#F56691": return Color(red: 0.82, green: 0.20, blue: 0.40)
        case "#3B82F6", "#3A82F6": return Color(red: 0.18, green: 0.38, blue: 0.85)
        case "#FAC430": return Color(red: 0.72, green: 0.50, blue: 0.05)
        case "#40C786": return Color(red: 0.15, green: 0.55, blue: 0.35)
        case "#9A5CE8": return Color(red: 0.45, green: 0.25, blue: 0.75)
        default: return Color(red: 0.40, green: 0.40, blue: 0.45)
        }
    }

    /// 카테고리 라벨 — colorHex 기반 macOS 매핑 재활용.
    private var categoryLabel: String {
        switch event.colorHex.uppercased() {
        case "#F56691": return "업무"
        case "#3B82F6", "#3A82F6": return "미팅"
        case "#FAC430": return "식사"
        case "#40C786": return "운동"
        case "#9A5CE8": return "개인"
        default: return "일반"
        }
    }

    private var startTimeText: String { Self.hm.string(from: event.startDate) }
    private var endTimeText: String { Self.hm.string(from: event.endDate) }

    private var durationText: String {
        let minutes = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
        if minutes <= 0 { return "" }
        if minutes < 60 { return "\(minutes)분" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)시간" : "\(h)시간 \(m)분"
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f
    }()
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
