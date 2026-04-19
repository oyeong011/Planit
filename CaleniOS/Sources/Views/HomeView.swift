#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - HomeView
//
// 레퍼런스 `Calen-iOS/Calen/Features/Home/HomeView.swift` 1:1 포팅 (M2 UI v3).

// MARK: - ScheduleCategory card colour mapping (view layer only)

private extension ScheduleCategory {
    var cardColor: Color {
        switch self {
        case .work:     return .cardWork
        case .meeting:  return .cardMeeting
        case .meal:     return .cardMeal
        case .exercise: return .cardExercise
        case .personal: return .cardPersonal
        case .general:  return .cardGeneral
        }
    }
}

// MARK: - HomeView

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── App header ────────────────────────────────────────
                HomeHeaderView()

                // ── Week strip ────────────────────────────────────────
                WeekStripView(
                    weekDates: viewModel.weekDates,
                    selectedDate: viewModel.selectedDate,
                    onSelect: { viewModel.selectDate($0) }
                )
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, 20)

                // ── Timeline scroll ───────────────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Section title: 오늘의 일정
                        Text("오늘의 일정")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        ScheduleTimelineView(schedules: viewModel.schedules)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 40)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.fetchSchedules()
        }
    }
}

// MARK: - HomeHeaderView

private struct HomeHeaderView: View {
    var body: some View {
        HStack {
            Text("Calen")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.calenBlue)

            Spacer()

            Button {
                // Notification action — placeholder
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.calenBlue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - WeekStripView

struct WeekStripView: View {
    let weekDates: [Date]
    let selectedDate: Date
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current
    // Korean single-character weekday labels, Monday-first
    private let dayLabels = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                WeekDayCell(
                    dayLabel: index < dayLabels.count ? dayLabels[index] : "",
                    dayNumber: calendar.component(.day, from: date),
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    onTap: { onSelect(date) }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

// MARK: - WeekDayCell

private struct WeekDayCell: View {
    let dayLabel: String
    let dayNumber: Int
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Day letter
                Text(dayLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .calenBlue : .secondary)

                // Date circle
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.calenBlue)
                            .frame(width: 34, height: 34)
                    } else if isToday {
                        Circle()
                            .stroke(Color.calenBlue, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                    }

                    Text("\(dayNumber)")
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(numberColor)
                }
                .frame(width: 34, height: 34)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday    { return .calenBlue }
        return .primary
    }
}

// MARK: - ScheduleTimelineView

struct ScheduleTimelineView: View {
    let schedules: [ScheduleDisplayItem]

    var body: some View {
        if schedules.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(schedules.enumerated()), id: \.element.id) { index, item in
                    TimelineRow(item: item)

                    // Travel indicator before the NEXT card
                    if index < schedules.count - 1 {
                        let next = schedules[index + 1]
                        if let minutes = next.travelTimeMinutes, minutes > 0 {
                            TravelTimeRow(minutes: minutes)
                        }
                    }
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.35))

            Text("오늘 등록된 일정이 없어요")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }
}

// MARK: - TimelineRow

private struct TimelineRow: View {
    let item: ScheduleDisplayItem

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // Left column: time label + vertical track
            VStack(spacing: 0) {
                Text(item.startTime, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .padding(.top, 2)

                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
            .padding(.leading, 20)
            .padding(.trailing, 10)

            // Right column: card
            ScheduleCard(item: item)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
        }
    }
}

// MARK: - TravelTimeRow

private struct TravelTimeRow: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 0) {
            // Visually align with the card body (20 leading + 48 time + 10 gap)
            Spacer().frame(width: 78)

            HStack(spacing: 8) {
                dashedVerticalLine
                    .frame(width: 1, height: 26)

                Image(systemName: "car.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondary.opacity(0.7))

                Text("\(minutes)분 이동")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var dashedVerticalLine: some View {
        GeometryReader { geo in
            Path { path in
                let x = geo.size.width / 2
                let dashLen: CGFloat = 4
                let gapLen:  CGFloat = 3
                var y: CGFloat = 0
                while y < geo.size.height {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: min(y + dashLen, geo.size.height)))
                    y += dashLen + gapLen
                }
            }
            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: - ScheduleCard

struct ScheduleCard: View {
    let item: ScheduleDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Header row ────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: item.category.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.calenBlue)

                Text(item.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                // Time range label (right-aligned)
                Group {
                    if let end = item.endTime {
                        Text(
                            "\(item.startTime.formatted(.dateTime.hour().minute()))–\(end.formatted(.dateTime.hour().minute()))"
                        )
                    } else {
                        Text(item.startTime.formatted(.dateTime.hour().minute()))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
            }

            // ── Body: bullet list OR summary ──────────────────────────
            if !item.bulletPoints.isEmpty {
                BulletList(points: item.bulletPoints)
            } else if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Location ──────────────────────────────────────────────
            if let location = item.location, !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(location)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // ── CTA buttons (work & meeting only) ─────────────────────
            if item.category == .work || item.category == .meeting {
                HStack(spacing: 8) {
                    let primaryLabel = item.category == .work
                        ? "업무 진행도 보기"
                        : "회의 내용 보기"
                    let primaryIcon = item.category == .work
                        ? "chart.bar"
                        : "doc.text"

                    CardCTAButton(title: primaryLabel, iconName: primaryIcon)
                    CardCTAButton(title: "할 일 추가하기", iconName: "plus.circle")
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(item.category.cardColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - BulletList

private struct BulletList: View {
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(points, id: \.self) { point in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(Color.calenBlue.opacity(0.65))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)

                    Text(point)
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - CardCTAButton

private struct CardCTAButton: View {
    let title: String
    let iconName: String

    var body: some View {
        Button {
            // Action placeholder
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.calenBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.calenBlue, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Home Screen") {
    HomeView()
        .modelContainer(for: Schedule.self, inMemory: true)
}

#Preview("Week Strip") {
    let today = Date()
    let cal = Calendar.current
    var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
    comps.weekday = 2
    let monday = cal.date(from: comps) ?? today
    let week = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }

    return WeekStripView(weekDates: week, selectedDate: today, onSelect: { _ in })
        .padding()
        .background(Color.white)
}

#Preview("Full Timeline") {
    ScrollView {
        ScheduleTimelineView(schedules: HomeViewModel.mockSchedules(for: Date()))
    }
    .padding(.top)
    .background(Color.white)
}
#endif
