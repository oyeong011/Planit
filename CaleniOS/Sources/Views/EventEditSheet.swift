#if os(iOS)
import SwiftUI
import UIKit
import CalenShared

// MARK: - EventEditSheet
//
// v6 주 시트에서 이벤트 블록 탭 시 열리는 편집 시트.
// 요구사항(UI v6):
//  - 제목/위치/시간/카테고리/메모 편집 + 삭제
//  - Save: isSaving 상태 → 성공시 dismiss, 실패시 sheet 내부 에러 배너 유지
//  - Delete: confirm alert → optimistic 제거 + 실패시 복원 토스트 (parent가 toast 표시)
//  - hasChanges 시 interactive dismiss 차단 + Cancel 확인 alert
//  - 기본 detent `.large` (편집 필드가 많아 medium으로 부족)

struct EventEditSheet: View {

    // MARK: - Input

    /// 편집 대상 원본 이벤트. 저장 성공 시 onSaved로 업데이트된 이벤트 전달.
    let event: CalendarEvent

    /// 저장 클로저. async throws — 실패 시 sheet 내부에 에러 배너로 노출.
    let onSave: (CalendarEvent) async throws -> CalendarEvent

    /// 삭제 클로저. async throws — 실패 시 parent에 토스트 위임.
    let onDelete: (CalendarEvent) async throws -> Void

    // MARK: - Draft state

    @State private var title: String
    @State private var location: String
    @State private var notes: String
    @State private var colorHex: String
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    // MARK: - Flow state

    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var showDeleteConfirm: Bool = false
    @State private var showCancelConfirm: Bool = false
    @State private var isDeleting: Bool = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    init(
        event: CalendarEvent,
        onSave: @escaping (CalendarEvent) async throws -> CalendarEvent,
        onDelete: @escaping (CalendarEvent) async throws -> Void
    ) {
        self.event = event
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: event.title)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.description ?? "")
        _colorHex = State(initialValue: event.colorHex)
        _isAllDay = State(initialValue: event.isAllDay)
        _startDate = State(initialValue: event.startDate)
        _endDate = State(initialValue: event.endDate)
    }

    // MARK: - Derived

    /// 원본 대비 변경 여부. Save 버튼 활성화 + dismiss 차단 기준.
    private var hasChanges: Bool {
        title != event.title
            || location != (event.location ?? "")
            || notes != (event.description ?? "")
            || colorHex != event.colorHex
            || isAllDay != event.isAllDay
            || startDate != event.startDate
            || endDate != event.endDate
    }

    private var canSave: Bool {
        !isSaving && !isDeleting && hasChanges && !title.trimmingCharacters(in: .whitespaces).isEmpty && endDate > startDate
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                formContent

                if let saveError {
                    errorBanner(message: saveError)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("일정 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasChanges || isSaving || isDeleting)
            .confirmationDialog(
                "변경사항을 취소할까요?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("변경사항 버리기", role: .destructive) {
                    dismiss()
                }
                Button("계속 편집", role: .cancel) {}
            }
            .confirmationDialog(
                "이 일정을 삭제할까요?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제 후 복원은 실패 시 자동으로만 시도됩니다.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Form

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section("기본") {
                TextField("제목", text: $title)
                    .textInputAutocapitalization(.sentences)
                TextField("위치(선택)", text: $location)
                    .textInputAutocapitalization(.words)
            }

            Section("시간") {
                Toggle("종일", isOn: $isAllDay)
                    .onChange(of: isAllDay) { _, newValue in
                        if newValue {
                            let cal = Calendar.current
                            startDate = cal.startOfDay(for: startDate)
                            endDate = cal.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                        }
                    }

                if isAllDay {
                    DatePicker("시작", selection: $startDate, displayedComponents: .date)
                    DatePicker("종료", selection: $endDate, in: startDate..., displayedComponents: .date)
                } else {
                    DatePicker("시작", selection: $startDate)
                    DatePicker("종료", selection: $endDate, in: startDate...)
                }
            }

            Section("카테고리") {
                colorPicker
            }

            Section("메모") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }

            if !event.isReadOnly {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView().controlSize(.small)
                                Text("삭제 중...")
                                    .padding(.leading, 6)
                            } else {
                                Image(systemName: "trash")
                                Text("일정 삭제")
                                    .padding(.leading, 4)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving || isDeleting)
                }
            }
        }
        .disabled(isSaving)
    }

    // MARK: - Color picker

    private static let palette: [String] = [
        "#F56691", // work pink
        "#3B82F6", // meeting blue
        "#FAC430", // meal yellow
        "#40C786", // exercise green
        "#9A5CE8", // personal violet
        "#909094"  // general gray
    ]

    private var colorPicker: some View {
        HStack(spacing: 12) {
            ForEach(Self.palette, id: \.self) { hex in
                Button {
                    colorHex = hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                        if colorHex.uppercased() == hex.uppercased() {
                            Circle()
                                .stroke(Color.primary, lineWidth: 2)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colorLabel(hex: hex))
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func colorLabel(hex: String) -> String {
        switch hex.uppercased() {
        case "#F56691": return "업무"
        case "#3B82F6": return "미팅"
        case "#FAC430": return "식사"
        case "#40C786": return "운동"
        case "#9A5CE8": return "개인"
        default: return "일반"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("취소") {
                if hasChanges && !isSaving {
                    showCancelConfirm = true
                } else if !isSaving {
                    dismiss()
                }
            }
            .disabled(isSaving || isDeleting)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView().controlSize(.small)
            } else {
                Button("저장") {
                    Task { await performSave() }
                }
                .disabled(!canSave)
            }
        }
    }

    // MARK: - Error banner (sheet 내부 상단)

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
            Button {
                withAnimation { saveError = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.92))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: - Flow

    private func performSave() async {
        guard canSave else { return }

        var updated = event
        updated.title = title.trimmingCharacters(in: .whitespaces)
        updated.location = location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : location
        updated.description = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        updated.colorHex = colorHex
        updated.isAllDay = isAllDay
        updated.startDate = startDate
        updated.endDate = endDate

        withAnimation { saveError = nil }
        isSaving = true
        do {
            _ = try await onSave(updated)
            isSaving = false
            impact(.medium)
            dismiss()
        } catch {
            isSaving = false
            impact(.heavy)
            withAnimation(.easeOut(duration: 0.2)) {
                saveError = "저장 실패 — \(error.localizedDescription)"
            }
        }
    }

    private func performDelete() async {
        isDeleting = true
        do {
            try await onDelete(event)
            isDeleting = false
            impact(.medium)
            dismiss()
        } catch {
            // parent에 토스트 처리 위임. sheet는 닫히지 않음 → 사용자 재시도 가능.
            isDeleting = false
            withAnimation(.easeOut(duration: 0.2)) {
                saveError = "삭제 실패 — \(error.localizedDescription)"
            }
            impact(.heavy)
        }
    }

    // MARK: - Haptics

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Preview

#Preview("EventEditSheet") {
    struct Wrap: View {
        @State var show = true
        let sample = CalendarEvent(
            id: "demo",
            calendarId: "fake:primary",
            title: "팀 스탠드업",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            description: "OKR 진행 공유",
            location: "본사 3층",
            colorHex: "#3B82F6"
        )
        var body: some View {
            Color.calenCream
                .sheet(isPresented: $show) {
                    EventEditSheet(
                        event: sample,
                        onSave: { updated in
                            try await Task.sleep(for: .milliseconds(300))
                            return updated
                        },
                        onDelete: { _ in
                            try await Task.sleep(for: .milliseconds(300))
                        }
                    )
                }
        }
    }
    return Wrap()
}
#endif
