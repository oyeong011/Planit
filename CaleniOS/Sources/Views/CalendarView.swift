#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - CalendarView
//
// 레퍼런스 `Calen-iOS/Calen/Features/Calendar/CalendarView.swift` 1:1 포팅 (M2 UI v3).

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CalendarViewModel()

    @State private var showingAddSheet = false

    // Korean weekday header labels (Sunday → Saturday)
    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    private let accentBlue = Color(red: 0.23, green: 0.51, blue: 0.96)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: Month navigation header
                        monthHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 16)

                        // MARK: Calendar grid
                        calendarGrid
                            .padding(.horizontal, 12)

                        Divider()
                            .padding(.top, 16)
                            .padding(.horizontal, 20)

                        // MARK: Daily schedule list
                        dailyScheduleList
                            .padding(.top, 4)
                    }
                }

                // MARK: FAB
                addButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAddSheet) {
                CalendarAddView(preselectedDate: viewModel.selectedDate) { newSchedule in
                    viewModel.addSchedule(newSchedule)
                }
            }
            .task {
                // Inject the SwiftData context once the view appears
                if viewModel.modelContext == nil {
                    viewModel.modelContext = modelContext
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text("Calen")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(accentBlue)
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack(spacing: 12) {
            // Month / Year label
            Text(currentMonthTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            // Prev / Next navigation
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.previousMonth()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray6), in: Circle())
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.nextMonth()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accentBlue)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray6), in: Circle())
                }
            }
        }
    }

    private var currentMonthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월"
        return fmt.string(from: viewModel.currentMonth)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            // Weekday label row
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            index == 0 ? Color.red
                            : index == 6 ? accentBlue
                            : .secondary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }

            // Day cells
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(0..<viewModel.datesInMonth.count, id: \.self) { index in
                    if let date = viewModel.datesInMonth[index] {
                        DayCell(
                            date: date,
                            isSelected: isSameDay(date, viewModel.selectedDate),
                            isToday: isSameDay(date, Date()),
                            dotColor: viewModel.hasSchedule(for: date)
                                ? viewModel.firstCategory(for: date)?.swiftUIColor
                                : nil,
                            accentBlue: accentBlue,
                            columnIndex: index % 7
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.selectDate(date)
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 46)
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    }

    // MARK: - Daily Schedule List

    private var dailyScheduleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text(selectedDateTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(viewModel.schedulesForSelectedDate.count)개")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if viewModel.schedulesForSelectedDate.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.schedulesForSelectedDate) { schedule in
                        ScheduleListCard(schedule: schedule, accentBlue: accentBlue)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 100) // clearance above FAB
            }
        }
    }

    private var selectedDateTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일 (E)"
        return fmt.string(from: viewModel.selectedDate)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 38))
                .foregroundStyle(accentBlue.opacity(0.4))
            Text("이 날의 일정이 없어요")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Text("+ 버튼을 눌러 일정을 추가해보세요")
                .font(.system(size: 13))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - FAB

    private var addButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(accentBlue, in: Circle())
                .shadow(color: accentBlue.opacity(0.40), radius: 12, x: 0, y: 6)
        }
    }

    // MARK: - Helpers

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }
}

// MARK: - DayCell

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let dotColor: Color?
    let accentBlue: Color
    let columnIndex: Int

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var textColor: Color {
        if isSelected     { return .white }
        if isToday        { return accentBlue }
        if columnIndex == 0 { return .red }
        if columnIndex == 6 { return accentBlue }
        return .primary
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Selection highlight
                if isSelected {
                    Circle()
                        .fill(accentBlue)
                        .frame(width: 34, height: 34)
                } else if isToday {
                    Circle()
                        .strokeBorder(accentBlue, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }

                Text(dayNumber)
                    .font(.system(size: 15, weight: (isToday || isSelected) ? .bold : .regular))
                    .foregroundStyle(textColor)
            }
            .frame(width: 34, height: 34)

            // Schedule dot
            Circle()
                .fill(dotColor ?? Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - ScheduleListCard

private struct ScheduleListCard: View {
    let schedule: Schedule
    let accentBlue: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Category colour bar
            RoundedRectangle(cornerRadius: 2)
                .fill(schedule.category.swiftUIColor)
                .frame(width: 4)
                .frame(minHeight: 52)

            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: schedule.category.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(schedule.category.swiftUIColor)

                    Text(schedule.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    // Category badge
                    Text(schedule.category.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(schedule.category.swiftUIColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            schedule.category.swiftUIColor.opacity(0.12),
                            in: Capsule()
                        )
                }

                // Time range
                Text(schedule.timeRangeString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // Location
                if let location = schedule.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .lineLimit(1)
                }

                // Summary / notes
                if let summary = schedule.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview("Calendar – with mock data") {
    CalendarView()
        .modelContainer(for: Schedule.self, inMemory: true)
}
#endif
