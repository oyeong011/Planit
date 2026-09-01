#if os(iOS)
import SwiftUI

// MARK: - WeekExpansionView
//
// TimeBlocks 스타일 주 확장 영역.
// HomeView에서 월 그리드 아래 위치. 선택된 주(월요일~일요일)의 요일별 일정 카드를 나열.
//
// 디자인:
//  - 선택일 이후 7일을 고정 시간열 + 블록 카드로 표시.
//  - 일정 없는 요일도 얇은 빈 슬롯으로 보여 타임블록 리듬을 유지.
//  - 전체를 ScrollView로 감싸되, 하단 탭/FAB와 겹치지 않도록 여백을 확보.

struct WeekExpansionView: View {

    /// 주 월요일.
    let weekStart: Date

    /// 요일별 그룹 (월~일 순서).
    let groups: [(day: Date, items: [ScheduleDisplayItem])]

    /// 선택된 날짜 (카드 하이라이트용).
    let selectedDate: Date

    /// 이벤트 카드 탭 콜백.
    let onTapEvent: (ScheduleDisplayItem) -> Void

    let onToggleCompletion: (ScheduleDisplayItem) -> Void

    private let cal = Calendar.current

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.day) { group in
                    WeekDayGroup(
                        day: group.day,
                        items: group.items,
                        isSelectedDay: cal.isDate(group.day, inSameDayAs: selectedDate),
                        onTapEvent: onTapEvent,
                        onToggleCompletion: onToggleCompletion
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 112)
        }
    }
}

// MARK: - WeekDayGroup

private struct WeekDayGroup: View {
    let day: Date
    let items: [ScheduleDisplayItem]
    let isSelectedDay: Bool
    let onTapEvent: (ScheduleDisplayItem) -> Void
    let onToggleCompletion: (ScheduleDisplayItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if items.isEmpty {
                emptyRow
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        EventCard(
                            item: item,
                            onToggleCompletion: { onToggleCompletion(item) }
                        )
                            .onTapGesture { onTapEvent(item) }
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(naturalHeader)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isToday ? Color.calenBlue : Color.primary)

            Text(secondaryDateString)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.56))

            Spacer()

            if !items.isEmpty {
                Text("\(items.count)개")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color.calenCardSurface.opacity(0.9),
                        in: Capsule()
                    )
            }
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Text("비어 있음")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.45))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 3)

            Text("새 블록을 추가할 수 있어요")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.42))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.calenCardSurface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isTomorrow: Bool {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) else { return false }
        return cal.isDate(day, inSameDayAs: tomorrow)
    }

    /// "오늘"/"내일"/"이번 주말"/요일 — 자연어 우선.
    private var naturalHeader: String {
        if isToday { return "오늘" }
        if isTomorrow { return "내일" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "EEEE"
        return fmt.string(from: day)
    }

    private var secondaryDateString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        if isToday || isTomorrow {
            fmt.dateFormat = "M월 d일 (E)"
        } else {
            fmt.dateFormat = "M월 d일"
        }
        return fmt.string(from: day)
    }
}

// MARK: - EventCard

private struct EventCard: View {
    let item: ScheduleDisplayItem
    let onToggleCompletion: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(startTimeString)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .monospacedDigit()
                Text(endTimeString)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .monospacedDigit()
            }
            .frame(width: 54, alignment: .trailing)
            .padding(.top, 2)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(item.category.swiftUIColor)
                .frame(width: 4, height: blockHeight - 20)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(item.isCompleted)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(categorySubLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.category.textColor.opacity(0.72))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.category.fillColor.opacity(0.72), in: Capsule())
                }

                if let location = item.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.48))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 2)

            Button(action: onToggleCompletion) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(item.isCompleted ? item.category.textColor : Color.primary.opacity(0.22))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "완료 취소" : "완료")
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: blockHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calenCardSurface)
        .opacity(item.isCompleted ? 0.6 : 1.0)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .dynamicTypeSize(.xSmall ... .accessibility1)
    }

    private var blockHeight: CGFloat {
        guard let end = item.endTime else { return 58 }
        let minutes = max(15, end.timeIntervalSince(item.startTime) / 60)
        return min(96, max(58, CGFloat(minutes) * 0.72))
    }

    private var categorySubLabel: String {
        switch item.category {
        case .work:     return "업무"
        case .meeting:  return "미팅"
        case .meal:     return "식사"
        case .exercise: return "운동"
        case .personal: return "개인"
        case .general:  return "일반"
        }
    }

    private var startTimeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: item.startTime)
    }

    private var endTimeString: String {
        guard let end = item.endTime else { return "시작" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: end)
    }
}

// MARK: - Preview

#Preview("Week Expansion") {
    let vm = HomeViewModel()
    let start = vm.weekStart(for: vm.selectedDate)
    let groups = vm.weekGroups(starting: start)
    return WeekExpansionView(
        weekStart: start,
        groups: groups,
        selectedDate: vm.selectedDate,
        onTapEvent: { _ in },
        onToggleCompletion: { _ in }
    )
    .background(Color.calenCream)
}
#endif
