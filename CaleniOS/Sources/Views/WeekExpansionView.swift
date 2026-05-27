#if os(iOS)
import SwiftUI

// MARK: - WeekExpansionView
//
// TimeBlocks 스타일 주 확장 영역.
// HomeView에서 월 그리드 아래 위치. 선택된 주(월요일~일요일)의 요일별 일정 카드를 나열.
//
// 디자인:
//  - 섹션 헤더: "4월 17일 월요일" 같은 형식. 일정 없는 요일은 `빈` 플레이스홀더 한 줄.
//  - 일정 카드: 좌측 색상 바(4pt) + VStack{제목, 시간}
//  - 전체를 ScrollView로 감싸되, 부모가 결정한 높이 내에서 스크롤.

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
            .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if items.isEmpty {
                emptyRow
            } else {
                VStack(spacing: 6) {
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
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isToday ? Color.calenBlue : Color.primary)

            Text(secondaryDateString)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if !items.isEmpty {
                Text("\(items.count)개")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Color.secondary.opacity(0.10),
                        in: Capsule()
                    )
            }
        }
    }

    private var emptyRow: some View {
        Text("일정 없음")
            .font(.system(size: 12))
            .foregroundStyle(Color(.tertiaryLabel))
            .padding(.leading, 2)
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
        // Planit 패턴: 카드 전체 ZStack — 좌측 카테고리 fill rect가 카드 좌측 절반을 채우고,
        // 그 위에 제목 + 카테고리 라벨 + 우측 체크박스. fill은 둥근 모서리로 카드와 통합.
        HStack(spacing: 0) {
            // 카테고리 색 fill 영역 (카드 전체 좌측 — Planit Today list 패턴)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(item.category.fillColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? Color.secondary : item.category.textColor)
                        .strikethrough(item.isCompleted)
                        .lineLimit(1)

                    Text(categorySubLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(item.category.textColor.opacity(0.75))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            // 우측 흰 영역 — 시간 + 체크박스
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeRangeString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let location = item.location, !location.isEmpty {
                        Text(location)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .lineLimit(1)
                    }
                }

                Button(action: onToggleCompletion) {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(item.isCompleted ? item.category.textColor : item.category.textColor.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "완료 취소" : "완료")
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(Color.calenCardSurface)
        }
        .frame(minHeight: 56)
        .opacity(item.isCompleted ? 0.6 : 1.0)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .calenCardShadow()
        .dynamicTypeSize(.xSmall ... .accessibility1)
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

    private var timeRangeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let start = fmt.string(from: item.startTime)
        if let end = item.endTime {
            return "\(start)–\(fmt.string(from: end))"
        }
        return start
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
