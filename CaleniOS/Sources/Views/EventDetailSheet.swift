#if os(iOS)
import SwiftUI

// MARK: - EventDetailSheet
//
// 이벤트 막대/카드 탭 시 오픈되는 읽기 전용 상세 시트 (v0.1.0 범위).
// 제목, 시간 범위, 카테고리, 위치, 메모를 표시한다. 편집은 v0.1.1로 연기.

struct EventDetailSheet: View {

    let item: ScheduleDisplayItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Category pill ─────────────────────────────────────
                    HStack(spacing: 6) {
                        Image(systemName: item.category.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(item.category.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(item.category.swiftUIColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        item.category.swiftUIColor.opacity(0.12),
                        in: Capsule()
                    )

                    // ── Title ─────────────────────────────────────────────
                    Text(item.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                        .dynamicTypeSize(.xSmall ... .accessibility1)

                    // ── Time ──────────────────────────────────────────────
                    infoRow(
                        icon: "clock",
                        title: "시간",
                        value: timeRangeString
                    )

                    // ── Location ──────────────────────────────────────────
                    if let location = item.location, !location.isEmpty {
                        infoRow(
                            icon: "mappin.and.ellipse",
                            title: "장소",
                            value: location
                        )
                    }

                    // ── Summary ───────────────────────────────────────────
                    if let summary = item.summary, !summary.isEmpty {
                        infoRow(
                            icon: "text.alignleft",
                            title: "요약",
                            value: summary
                        )
                    }

                    // ── Bullet points (notes) ─────────────────────────────
                    if !item.bulletPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("메모")
                            ForEach(item.bulletPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.calenBlue.opacity(0.6))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 7)
                                    Text(point)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    // ── Edit hint ─────────────────────────────────────────
                    Text("편집 기능은 곧 제공될 예정입니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.calenCream.ignoresSafeArea())
            .navigationTitle("일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.calenBlue)
                }
            }
        }
    }

    // MARK: - Helpers

    private var timeRangeString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월 d일 (E) HH:mm"
        let start = fmt.string(from: item.startTime)
        if let end = item.endTime {
            let endFmt = DateFormatter()
            endFmt.dateFormat = "HH:mm"
            return "\(start) – \(endFmt.string(from: end))"
        }
        return start
    }

    @ViewBuilder
    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.calenBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Preview

#Preview("Event Detail") {
    EventDetailSheet(item: ScheduleDisplayItem(
        title: "기획 리뷰",
        category: .work,
        startTime: Date(),
        endTime: Calendar.current.date(byAdding: .hour, value: 1, to: Date()),
        location: "본사 3층 회의실",
        summary: "Q2 로드맵 검토",
        travelTimeMinutes: nil,
        bulletPoints: ["지표 공유", "Top3 리스크", "액션 아이템"]
    ))
}
#endif
