#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - AllDayRowView
//
// 주 시간 그리드 상단에 고정되는 종일 이벤트 row (32pt 고정 높이).
// 7개 컬럼 각각에 해당 날짜의 종일 이벤트 pill을 최대 2개까지 표시, 초과 시 "+N" 배지.
// 다일(multi-day) 이벤트는 v0.1.0에선 시작일에만 표시 + "계속" 뱃지.
// (가로 연결 렌더링은 v0.1.1 연기)

struct AllDayRowView: View {

    let days: [Date]                          // 7개 (월~일)
    let eventsByDay: [Date: [CalendarEvent]]  // startOfDay 키
    let onTap: (CalendarEvent) -> Void
    let leadingTimeGutter: CGFloat            // 좌측 시간 라벨 폭 (시간 그리드와 정렬)

    private let cal = Calendar.current
    private let maxVisible = 2

    var body: some View {
        HStack(spacing: 0) {
            // 좌측 시간 라벨 폭만큼 비워둠
            Color.clear
                .frame(width: leadingTimeGutter)
                .overlay(
                    Text("종일")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4),
                    alignment: .trailing
                )

            // 7일 컬럼
            GeometryReader { geo in
                let colW = geo.size.width / 7
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        dayCell(day: day, width: colW)
                    }
                }
            }
        }
        .frame(height: 32)
        .background(
            Color.calenCardSurface
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
        )
    }

    // MARK: - Day cell

    private func dayCell(day: Date, width: CGFloat) -> some View {
        let start = cal.startOfDay(for: day)
        let allEvents = eventsByDay[start] ?? []
        let visible = Array(allEvents.prefix(maxVisible))
        let overflow = allEvents.count - visible.count

        return VStack(alignment: .leading, spacing: 2) {
            ForEach(visible, id: \.self) { ev in
                AllDayPill(
                    event: ev,
                    isContinuation: isMultiDayContinuation(ev, day: start)
                )
                .onTapGesture { onTap(ev) }
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.calenBlue)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(width: width, height: 32, alignment: .top)
    }

    private func isMultiDayContinuation(_ event: CalendarEvent, day: Date) -> Bool {
        // event.startDate가 day보다 이전이면 "이어지는 날"
        return cal.startOfDay(for: event.startDate) < day
    }
}

// MARK: - AllDayPill

private struct AllDayPill: View {
    let event: CalendarEvent
    let isContinuation: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(hex: event.colorHex))
                .frame(width: 5, height: 5)
            Text(event.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if isContinuation {
                Text("계속")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: event.colorHex).opacity(0.18))
        )
    }
}

// MARK: - Preview

#Preview("AllDayRow") {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    let key = today
    let events: [Date: [CalendarEvent]] = [
        key: [
            CalendarEvent(
                id: "a1", calendarId: "c", title: "오프사이트",
                startDate: today, endDate: cal.date(byAdding: .day, value: 2, to: today)!,
                isAllDay: true, colorHex: "#9A5CE8"
            )
        ]
    ]
    return AllDayRowView(
        days: days,
        eventsByDay: events,
        onTap: { _ in },
        leadingTimeGutter: 48
    )
    .padding()
}
#endif
