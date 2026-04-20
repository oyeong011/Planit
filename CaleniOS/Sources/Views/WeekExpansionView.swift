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

    private let cal = Calendar.current

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.day) { group in
                    WeekDayGroup(
                        day: group.day,
                        items: group.items,
                        isSelectedDay: cal.isDate(group.day, inSameDayAs: selectedDate),
                        onTapEvent: onTapEvent
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if items.isEmpty {
                emptyRow
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        EventCard(item: item)
                            .onTapGesture { onTapEvent(item) }
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(dayNumberString)
                .font(.system(size: 15, weight: isSelectedDay ? .bold : .semibold))
                .foregroundStyle(isSelectedDay ? Color.calenBlue : Color.primary)
                .frame(minWidth: 22, alignment: .leading)

            Text(dayNameString)
                .font(.system(size: 13, weight: .medium))
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

    private var dayNumberString: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    private var dayNameString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일 EEEE"
        return fmt.string(from: day)
    }
}

// MARK: - EventCard

private struct EventCard: View {
    let item: ScheduleDisplayItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 좌측 색상 바 4pt
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.category.swiftUIColor)
                .frame(width: 4)
                .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 3) {
                // 제목 라인
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.category.swiftUIColor)

                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(timeRangeString)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let location = item.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10))
                        Text(location)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .dynamicTypeSize(.xSmall ... .accessibility1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.calenCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .calenCardShadow()
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
        onTapEvent: { _ in }
    )
    .background(Color.calenCream)
}
#endif
