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
            .navigationTitle(Text("edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasChanges || isSaving || isDeleting)
            .confirmationDialog(
                Text("edit.confirm.cancel"),
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("edit.confirm.discard", comment: ""), role: .destructive) {
                    dismiss()
                }
                Button(NSLocalizedString("edit.confirm.keep", comment: ""), role: .cancel) {}
            }
            .confirmationDialog(
                Text("edit.confirm.delete"),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                    Task { await performDelete() }
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Form

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section(header: Text("edit.basic")) {
                TextField(NSLocalizedString("edit.title.placeholder", comment: ""), text: $title)
                    .textInputAutocapitalization(.sentences)
                TextField(NSLocalizedString("edit.location.placeholder", comment: ""), text: $location)
                    .textInputAutocapitalization(.words)
            }

            Section(header: Text("edit.time")) {
                Toggle(isOn: $isAllDay) { Text("edit.allday") }
                    .onChange(of: isAllDay) { _, newValue in
                        if newValue {
                            let cal = Calendar.current
                            startDate = cal.startOfDay(for: startDate)
                            endDate = cal.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                        }
                    }

                if isAllDay {
                    DatePicker(selection: $startDate, displayedComponents: .date) { Text("edit.start") }
                    DatePicker(selection: $endDate, in: startDate..., displayedComponents: .date) { Text("edit.end") }
                } else {
                    DatePicker(selection: $startDate) { Text("edit.start") }
                    DatePicker(selection: $endDate, in: startDate...) { Text("edit.end") }
                }
            }

            Section(header: Text("edit.category")) {
                colorPicker
            }

            Section(header: Text("edit.memo")) {
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
                                Text("edit.delete")
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
        case "#F56691": return NSLocalizedString("category.work",     comment: "")
        case "#3B82F6": return NSLocalizedString("category.meeting",  comment: "")
        case "#FAC430": return NSLocalizedString("category.meal",     comment: "")
        case "#40C786": return NSLocalizedString("category.exercise", comment: "")
        case "#9A5CE8": return NSLocalizedString("category.personal", comment: "")
        default:        return NSLocalizedString("category.general",  comment: "")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(NSLocalizedString("common.cancel", comment: "")) {
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
                Button(NSLocalizedString("common.save", comment: "")) {
                    Task { await performSave() }
                }
                .disabled(!canSave)
            }
        }
    }

    // MARK: - Error banner (sheet 내부 상단) — macOS `CRUDErrorInlineNotice` 패턴 이식 (Quick Win)

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.systemOrange))
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("edit.save.fail")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { saveError = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("오류 닫기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemOrange).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(.systemOrange).opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("오류: \(message)")
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
