#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - CalendarAddView
//
// 레퍼런스 `Calen-iOS/Calen/Features/Calendar/CalendarAddView.swift` 1:1 포팅 (M2 UI v3).

struct CalendarAddView: View {

    // MARK: Environment & Callbacks

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Called with the new Schedule when the user saves
    var onSave: ((Schedule) -> Void)?

    // MARK: Form State

    @State private var title: String = ""
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var hasEndTime: Bool = false
    @State private var location: String = ""
    @State private var category: ScheduleCategory = .general
    @State private var notes: String = ""
    @FocusState private var focusedField: FormField?

    // MARK: Validation

    @State private var showingTitleAlert = false

    // MARK: - Init

    init(preselectedDate: Date = Date(), onSave: ((Schedule) -> Void)? = nil) {
        self.onSave = onSave
        let cal = Calendar.current

        // Normalise to the selected day; default start time = next full hour
        let day = cal.startOfDay(for: preselectedDate)
        var comps = cal.dateComponents([.hour, .minute], from: Date())
        comps.minute = 0
        let nextHour = (comps.hour ?? 9) + 1
        let start = cal.date(bySettingHour: min(nextHour, 23), minute: 0, second: 0, of: day) ?? day
        let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start

        _date      = State(initialValue: day)
        _startTime = State(initialValue: start)
        _endTime   = State(initialValue: end)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 일정명 (Title)
                Section {
                    TextField("일정 이름을 입력하세요", text: $title)
                        .font(.system(size: 15))
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .location }
                } header: {
                    sectionHeader("일정명")
                }

                // MARK: 날짜 & 시간 (Date and Time)
                Section {
                    // Date picker
                    DatePicker("날짜", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ko_KR"))

                    // Start time picker
                    DatePicker("시작 시간", selection: $startTime, displayedComponents: .hourAndMinute)
                        .onChange(of: startTime) { _, newVal in
                            // Keep end time at least 30 min after start
                            if hasEndTime && endTime <= newVal {
                                endTime = Calendar.current.date(byAdding: .minute, value: 30, to: newVal) ?? newVal
                            }
                        }

                    // End time toggle + picker
                    Toggle(isOn: $hasEndTime) {
                        Text("종료 시간")
                            .font(.system(size: 15))
                    }
                    .tint(Color(red: 0.23, green: 0.51, blue: 0.96))

                    if hasEndTime {
                        DatePicker(
                            "종료 시간",
                            selection: $endTime,
                            in: startTime...,
                            displayedComponents: .hourAndMinute
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } header: {
                    sectionHeader("날짜 및 시간")
                }
                .animation(.easeInOut(duration: 0.2), value: hasEndTime)

                // MARK: 카테고리 (Category)
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ScheduleCategory.allCases, id: \.self) { cat in
                                CategoryChip(
                                    category: cat,
                                    isSelected: category == cat
                                ) {
                                    category = cat
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    sectionHeader("카테고리")
                }

                // MARK: 장소 (Location, optional)
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(.tertiaryLabel))
                        TextField("장소 (선택)", text: $location)
                            .font(.system(size: 15))
                            .focused($focusedField, equals: .location)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .notes }
                    }
                } header: {
                    sectionHeader("장소")
                }

                // MARK: 메모 (Notes, optional)
                Section {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("메모를 입력하세요 (선택)")
                                .foregroundStyle(Color(.tertiaryLabel))
                                .font(.system(size: 15))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $notes)
                            .focused($focusedField, equals: .notes)
                            .font(.system(size: 15))
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    sectionHeader("메모")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }

                // Save
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") {
                        saveSchedule()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        title.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color(.tertiaryLabel)
                            : Color(red: 0.23, green: 0.51, blue: 0.96)
                    )
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Keyboard Done button
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        focusedField = nil
                    }
                    .foregroundStyle(Color(red: 0.23, green: 0.51, blue: 0.96))
                }
            }
            .alert("일정명을 입력해주세요", isPresented: $showingTitleAlert) {
                Button("확인", role: .cancel) { focusedField = .title }
            }
        }
    }

    // MARK: - Save Logic

    private func saveSchedule() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showingTitleAlert = true
            return
        }

        // Combine selected date with time components
        let cal = Calendar.current
        let startComponents = cal.dateComponents([.hour, .minute], from: startTime)
        let finalStart = cal.date(
            bySettingHour: startComponents.hour ?? 9,
            minute: startComponents.minute ?? 0,
            second: 0,
            of: date
        ) ?? date

        var finalEnd: Date? = nil
        if hasEndTime {
            let endComponents = cal.dateComponents([.hour, .minute], from: endTime)
            finalEnd = cal.date(
                bySettingHour: endComponents.hour ?? 10,
                minute: endComponents.minute ?? 0,
                second: 0,
                of: date
            )
        }

        let schedule = Schedule(
            title: trimmed,
            date: cal.startOfDay(for: date),
            startTime: finalStart,
            endTime: finalEnd,
            location: location.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : location.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : notes.trimmingCharacters(in: .whitespaces),
            category: category
        )

        onSave?(schedule)
        dismiss()
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

// MARK: - FormField FocusState Enum

private enum FormField: Hashable {
    case title
    case location
    case notes
}

// MARK: - CategoryChip

private struct CategoryChip: View {
    let category: ScheduleCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(category.label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : category.swiftUIColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? category.swiftUIColor
                    : category.swiftUIColor.opacity(0.12),
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Add Schedule") {
    CalendarAddView(preselectedDate: Date()) { schedule in
        print("Saved: \(schedule.title)")
    }
    .modelContainer(for: Schedule.self, inMemory: true)
}
#endif
