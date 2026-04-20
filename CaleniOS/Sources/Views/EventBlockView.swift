#if os(iOS)
import SwiftUI
import CalenShared

// MARK: - EventBlockView
//
// 주 시간 그리드에 렌더되는 단일 이벤트 블록.
// v6 요구사항 (v5 대비 가독성 강화):
//  - 카테고리 컬러 4pt leading bar + 배경 opacity 0.18 + stroke opacity 0.7
//  - cornerRadius 6
//  - 제목 13pt semibold / 시간 11pt regular secondary / 위치 11pt regular tertiary
//  - 높이 ≥ 32pt: 제목 + 시간 + (선택) 위치
//    22 ≤ 높이 < 32: 제목만 1줄
//    높이 < 22pt: 제목 1자 + 생략("…")
//  - padding 8pt horizontal / 6pt vertical
//  - 읽기 전용은 하단 resize handle 숨김 + opacity 0.75
//  - Drag 중 border 2pt + 강화 그림자
//  - .contentShape(Rectangle()) 로 탭/드래그 히트 영역 명시
//
// 제스처(탭/이동/리사이즈)는 WeekTimeGridSheet에서 외부에서 주입.
// 이 View 자체는 순수 렌더만 담당(isDragging / isResizing state만 받음).

struct EventBlockView: View {

    let event: CalendarEvent
    let height: CGFloat
    let isDragging: Bool
    let isResizing: Bool

    /// 하단 handle 영역(높이 12pt)에 제스처를 달기 위한 tag로만 사용.
    /// (실제 제스처는 parent가 overlay로 주입.)
    let showResizeHandle: Bool

    private var color: Color {
        Color(hex: event.colorHex)
    }

    /// 높이 22pt 미만: 제목 1자만 + 생략.
    private var isUltraCompact: Bool { height < 22 }

    /// 높이 22~32pt: 제목 1줄만.
    private var isCompact: Bool { height < 32 }

    private var opacity: Double {
        event.isReadOnly ? 0.75 : 1.0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 카드
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            color.opacity(isDragging || isResizing ? 0.95 : 0.7),
                            lineWidth: (isDragging || isResizing) ? 2 : 1
                        )
                )

            // 좌측 색상 bar (v6: 3pt → 4pt)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 4)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // 본문 (v6: horizontal 8pt / vertical 6pt)
            contentStack
                .padding(.leading, 12) // 4pt bar + 8pt gap
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 하단 resize handle visual
            if showResizeHandle && !event.isReadOnly {
                VStack(spacing: 0) {
                    Spacer()
                    handleVisual
                }
                .allowsHitTesting(false)
            }
        }
        .opacity(opacity)
        .contentShape(Rectangle())
        .shadow(
            color: (isDragging || isResizing) ? Color.black.opacity(0.18) : Color.clear,
            radius: (isDragging || isResizing) ? 8 : 0,
            x: 0,
            y: (isDragging || isResizing) ? 4 : 0
        )
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .animation(.easeOut(duration: 0.12), value: isResizing)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentStack: some View {
        if isUltraCompact {
            // 높이 < 22 → 제목 1자 정도만 보여주고 자연 truncation
            Text(event.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if isCompact {
            // 22 ≤ 높이 < 32 → 제목 1줄
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        } else {
            // 높이 ≥ 32 → 제목 + 시간 (+ 위치 옵션)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(timeString)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty, height > 56 {
                    Text(location)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .lineLimit(1)
                }
            }
        }
    }

    private var handleVisual: some View {
        // 하단 3pt grab bar — 중앙에 얇은 line.
        HStack {
            Spacer()
            Capsule(style: .continuous)
                .fill(color.opacity(0.55))
                .frame(width: 22, height: 3)
            Spacer()
        }
        .padding(.bottom, 3)
        .opacity(isResizing ? 1.0 : 0.7)
    }

    // MARK: - Helpers

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.startDate))–\(fmt.string(from: event.endDate))"
    }
}

// MARK: - Preview

#Preview("EventBlock") {
    VStack(spacing: 12) {
        EventBlockView(
            event: CalendarEvent(
                id: "p1",
                calendarId: "fake:primary",
                title: "팀 스탠드업",
                startDate: Date(),
                endDate: Date().addingTimeInterval(1800),
                colorHex: "#3B82F6"
            ),
            height: 60,
            isDragging: false,
            isResizing: false,
            showResizeHandle: true
        )
        .frame(width: 140, height: 60)

        EventBlockView(
            event: CalendarEvent(
                id: "p2",
                calendarId: "fake:primary",
                title: "짧은 회의",
                startDate: Date(),
                endDate: Date().addingTimeInterval(900),
                colorHex: "#F56691"
            ),
            height: 18,
            isDragging: false,
            isResizing: false,
            showResizeHandle: true
        )
        .frame(width: 140, height: 18)

        EventBlockView(
            event: CalendarEvent(
                id: "p3",
                calendarId: "fake:primary",
                title: "읽기 전용",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                colorHex: "#909094",
                isReadOnly: true
            ),
            height: 60,
            isDragging: false,
            isResizing: false,
            showResizeHandle: true
        )
        .frame(width: 140, height: 60)
    }
    .padding()
    .background(Color.calenCream)
}
#endif
