// MARK: - TodayEventsWidget
//
// 오늘의 다음 일정(2~4개)을 홈스크린에 보여주는 WidgetKit 위젯.
//
// Family 별 설계:
//   .systemSmall  — 다음 1개 이벤트. 시간 큰 글씨 + 제목 2줄.
//   .systemMedium — 다음 3개 이벤트 리스트. 시간 + 제목 + 카테고리 색상 바.
//   .systemLarge  — v0.1.2로 미룸(placeholder 주석).
//
// Timeline:
//   - 5분 간격으로 refresh.
//   - 추가로 다음 이벤트의 start 시각 기준으로 entry 추가 — 그 시각을 지나면 "다음" 이
//     자연스럽게 앞당겨진다.

import WidgetKit
import SwiftUI

// MARK: - TodayEventsEntry

struct TodayEventsEntry: TimelineEntry {
    let date: Date
    let events: [EventSnapshot]
}

// MARK: - TodayEventsProvider

struct TodayEventsProvider: TimelineProvider {

    // MARK: Placeholder / Snapshot

    func placeholder(in context: Context) -> TodayEventsEntry {
        TodayEventsEntry(date: Date(), events: TodayEventsMock.sample(count: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEventsEntry) -> Void) {
        let events = WidgetDataProvider.loadUpcomingEvents(limit: 4)
        let entry = TodayEventsEntry(
            date: Date(),
            events: events.isEmpty ? TodayEventsMock.sample(count: 3) : events
        )
        completion(entry)
    }

    // MARK: Timeline

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEventsEntry>) -> Void) {
        let now = Date()
        let events = WidgetDataProvider.loadUpcomingEvents(now: now, limit: 4)

        // Entry 1: 지금.
        var entries: [TodayEventsEntry] = [TodayEventsEntry(date: now, events: events)]

        // Entry 2: 5분 뒤 refresh baseline.
        if let plus5 = Calendar.current.date(byAdding: .minute, value: 5, to: now) {
            entries.append(TodayEventsEntry(
                date: plus5,
                events: WidgetDataProvider.loadUpcomingEvents(now: plus5, limit: 4)
            ))
        }

        // Entry 3: 가장 가까운 이벤트 start 시각 — "다음" 표시가 밀리도록.
        if let nextStart = events.first?.start, nextStart > now {
            entries.append(TodayEventsEntry(
                date: nextStart,
                events: WidgetDataProvider.loadUpcomingEvents(now: nextStart, limit: 4)
            ))
        }

        // 다음 refresh는 최소 5분 후 또는 next start 중 이른 쪽.
        let policyDate = entries.last?.date ?? now.addingTimeInterval(300)
        let timeline = Timeline(entries: entries, policy: .after(policyDate))
        completion(timeline)
    }
}

// MARK: - TodayEventsWidget (entry point)

struct TodayEventsWidget: Widget {
    let kind: String = "TodayEventsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayEventsProvider()) { entry in
            TodayEventsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("오늘의 일정")
        .description("Calen의 다음 일정을 홈스크린에서 바로 확인하세요.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium]
        if #available(iOSApplicationExtension 16.0, *) {
            families.append(contentsOf: [
                .accessoryInline,
                .accessoryCircular,
                .accessoryRectangular,
            ])
        }
        return families
    }
}

// MARK: - Entry view (family router)

struct TodayEventsWidgetEntryView: View {
    let entry: TodayEventsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .accessoryInline:
            AccessoryInlineWidgetView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularWidgetView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            // systemLarge는 v0.1.2로 미룸 — fallback으로 medium 레이아웃 재사용.
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Small

private struct SmallWidgetView: View {
    let entry: TodayEventsEntry

    var body: some View {
        if let first = entry.events.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("다음")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(dayLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(WidgetColor.color(forHex: first.colorHex))
                    .frame(height: 4)

                Text(timeLabel(for: first))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(first.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(timeRangeLabel(for: first))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyStateView()
        }
    }

    private func timeLabel(for ev: EventSnapshot) -> String {
        if ev.isAllDay { return "종일" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: ev.start)
    }

    private func timeRangeLabel(for ev: EventSnapshot) -> String {
        if ev.isAllDay { return "종일 블록" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: ev.start)) – \(fmt.string(from: ev.end))"
    }

    private var dayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M.d E"
        return fmt.string(from: entry.date)
    }
}

// MARK: - Medium

private struct MediumWidgetView: View {
    let entry: TodayEventsEntry

    var body: some View {
        if entry.events.isEmpty {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("오늘의 블록")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text(dayLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 5) {
                    ForEach(entry.events.prefix(3)) { ev in
                        MediumWidgetEventRow(event: ev)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var dayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M.d E"
        return fmt.string(from: entry.date)
    }
}

private struct MediumWidgetEventRow: View {
    let event: EventSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Text(startLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(WidgetColor.color(forHex: event.colorHex))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(endLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var startLabel: String {
        if event.isAllDay { return "종일" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: event.start)
    }

    private var endLabel: String {
        if event.isAllDay { return "하루 전체" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "까지 \(fmt.string(from: event.end))"
    }
}

@available(iOSApplicationExtension 16.0, *)
private struct AccessoryInlineWidgetView: View {
    let entry: TodayEventsEntry

    var body: some View {
        if let first = entry.events.first {
            Text("다음 \(inlineTimeLabel(for: first)) \(first.title)")
                .lineLimit(1)
        } else {
            Text("오늘 일정 없음")
        }
    }

    private func inlineTimeLabel(for ev: EventSnapshot) -> String {
        if ev.isAllDay { return "종일" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: ev.start)
    }
}

@available(iOSApplicationExtension 16.0, *)
private struct AccessoryCircularWidgetView: View {
    let entry: TodayEventsEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let first = entry.events.first {
                VStack(spacing: 2) {
                    Text(first.isAllDay ? "종일" : shortHourLabel(for: first))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(first.isAllDay ? "일정" : shortMinuteLabel(for: first))
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                }
            } else {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
    }

    private func shortHourLabel(for ev: EventSnapshot) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH"
        return fmt.string(from: ev.start)
    }

    private func shortMinuteLabel(for ev: EventSnapshot) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "mm"
        return fmt.string(from: ev.start)
    }
}

@available(iOSApplicationExtension 16.0, *)
private struct AccessoryRectangularWidgetView: View {
    let entry: TodayEventsEntry

    var body: some View {
        if let first = entry.events.first {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(WidgetColor.color(forHex: first.colorHex))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeRangeLabel(for: first))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(first.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("오늘 일정 없음")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func timeRangeLabel(for ev: EventSnapshot) -> String {
        if ev.isAllDay { return "종일" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let start = fmt.string(from: ev.start)
        let end = fmt.string(from: ev.end)
        return "\(start) – \(end)"
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("오늘은 일정이 없어요")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("새 블록을 추가해보세요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Hex → Color (Widget local, CalenShared 의존 회피)

enum WidgetColor {
    static func color(forHex hex: String) -> Color {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            return .blue
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

// MARK: - Mock (Preview / placeholder)

enum TodayEventsMock {
    static func sample(count: Int) -> [EventSnapshot] {
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        let fixtures: [(String, String)] = [
            ("팀 스탠드업", "#3B82F6"),
            ("기획 리뷰", "#F56691"),
            ("점심 식사", "#FAC430"),
            ("헬스장", "#40C786"),
        ]
        return (0..<min(count, fixtures.count)).map { i in
            let (title, hex) = fixtures[i]
            let start = cal.date(byAdding: .hour, value: i * 2, to: now) ?? now
            let end = start.addingTimeInterval(3600)
            return EventSnapshot(
                id: "mock-\(i)",
                title: title,
                start: start,
                end: end,
                colorHex: hex,
                isAllDay: false
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview(as: .systemSmall) {
    TodayEventsWidget()
} timeline: {
    TodayEventsEntry(date: .now, events: TodayEventsMock.sample(count: 1))
    TodayEventsEntry(date: .now, events: [])
}

#Preview(as: .systemMedium) {
    TodayEventsWidget()
} timeline: {
    TodayEventsEntry(date: .now, events: TodayEventsMock.sample(count: 3))
    TodayEventsEntry(date: .now, events: [])
}

@available(iOSApplicationExtension 16.0, *)
#Preview(as: .accessoryInline) {
    TodayEventsWidget()
} timeline: {
    TodayEventsEntry(date: .now, events: TodayEventsMock.sample(count: 1))
}

@available(iOSApplicationExtension 16.0, *)
#Preview(as: .accessoryCircular) {
    TodayEventsWidget()
} timeline: {
    TodayEventsEntry(date: .now, events: TodayEventsMock.sample(count: 1))
    TodayEventsEntry(date: .now, events: [])
}

@available(iOSApplicationExtension 16.0, *)
#Preview(as: .accessoryRectangular) {
    TodayEventsWidget()
} timeline: {
    TodayEventsEntry(date: .now, events: TodayEventsMock.sample(count: 1))
    TodayEventsEntry(date: .now, events: [])
}
#endif
