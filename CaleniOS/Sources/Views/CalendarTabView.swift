#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - CalendarTabView
//
// 3탭 레이아웃의 첫 번째 탭("오늘").
// - 이번 주 7일 스크롤 헤더 (선택된 날짜 강조)
// - 선택 날짜의 Google Calendar 이벤트 목록
//   (P0: placeholder — 실제 이벤트 로드는 AUTH/SYNC 팀장 구현 후 연결)
//
// 로그인이 필요한 빈 상태에서는 설정 탭으로의 프로그래매틱 전환을 지원한다.
struct CalendarTabView: View {
    /// 상위 RootTabView에서 관리하는 선택된 탭 인덱스. "로그인" 버튼에서 사용.
    @Binding var selectedTab: Int

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// v0.1.0 P0 — 실제 이벤트 로드는 AUTH 팀장 PR 이후 연결.
    /// 빈 배열이면 "로그인 후 이벤트 표시" 빈 상태를 보여준다.
    @State private var events: [CalendarEvent] = []

    /// placeholder — 실제 값은 AUTH 팀장의 `iOSGoogleAuthManager` 연결 후 교체.
    @State private var isLoggedIn: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)

                Divider()

                content
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Week header (이번 주 7일)

    private var weekHeader: some View {
        let days = weekDays(containing: selectedDate)
        return HStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                DayChip(
                    date: day,
                    isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                    isToday: Calendar.current.isDateInToday(day)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = Calendar.current.startOfDay(for: day)
                    }
                }
            }
        }
    }

    private func weekDays(containing date: Date) -> [Date] {
        let cal = Calendar.current
        // 주의 시작 요일(로케일 따름)을 기준으로 7일 반환.
        let weekday = cal.component(.weekday, from: date)
        let firstWeekday = cal.firstWeekday
        let offset = (weekday - firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: date)) else {
            return [date]
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if eventsForSelectedDate.isEmpty {
            emptyState
        } else {
            List {
                ForEach(eventsForSelectedDate) { event in
                    EventRow(event: event)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
        }
    }

    private var eventsForSelectedDate: [CalendarEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.startDate, inSameDayAs: selectedDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(isLoggedIn ? "이 날짜에는 일정이 없습니다" : "로그인 후 이벤트 표시")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !isLoggedIn {
                Button {
                    // 설정 탭으로 프로그래매틱 전환 (index 2).
                    selectedTab = 2
                } label: {
                    Text("로그인")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("설정에서 Google 로그인")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Title

    private var navigationTitleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return Calendar.current.isDateInToday(selectedDate)
            ? "오늘 · \(f.string(from: selectedDate))"
            : f.string(from: selectedDate)
    }
}

// MARK: - DayChip

private struct DayChip: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(weekdayShort)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text("\(dayNumber)")
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                Circle()
                    .fill(isToday ? (isSelected ? Color.white : Color.accentColor) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(for: date))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var weekdayShort: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E"
        return f.string(from: date)
    }

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    private static func accessibilityLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f.string(from: date)
    }
}

// MARK: - EventRow

private struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: event.colorHex))
                .frame(width: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(timeRange)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let location = event.location, !location.isEmpty {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var timeRange: String {
        if event.isAllDay {
            return "종일"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return "\(f.string(from: event.startDate)) – \(f.string(from: event.endDate))"
    }
}
#endif
