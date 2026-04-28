#if os(iOS)
import SwiftUI

// MARK: - HomeV2 Components (Sprint B', v0.6 시안 정확 반영)
//
// Figma "호주 (1)" Section 1 / Home.png 톤.
// 각 컴포넌트는 Dynamic Type 100% 대응 (Theme.swift 폰트 토큰 사용).
// 카드 색은 `CalenTheme.CardTone` 의 라이트 블루 통일(저녁식사만 핑크 변주).

// MARK: - CalenLogoMini

/// 좌상단 작은 "Calen" 텍스트 로고 (시안 블루 색).
struct CalenLogoMini: View {
    var body: some View {
        Text("Calen")
            .font(.system(.title3, design: .default).weight(.bold))
            .foregroundStyle(Color(hex: "#2B8BDA"))
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - WeekStripView

/// 7일 가로 strip (오늘 강조 + SAT/SUN 한국식 강조 옵션).
struct WeekStripView: View {
    let days: [Date]
    let selected: Date
    var onSelect: (Date) -> Void = { _ in }

    private static let weekdayLabels = ["MON","TUE","WED","THU","FRI","SAT","SUN"]
    private let cal = Calendar(identifier: .gregorian)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { idx, date in
                let isToday  = cal.isDateInToday(date)
                let isSelect = cal.isDate(date, inSameDayAs: selected)
                Button {
                    onSelect(date)
                } label: {
                    VStack(spacing: 2) {
                        Text("\(cal.component(.day, from: date))")
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundStyle(numColor(isToday: isToday, idx: idx))
                        Text(Self.weekdayLabels[safe: idx] ?? "")
                            .font(.system(.caption2).weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(lblColor(idx: idx))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(isSelect && !isToday
                                ? Color.black.opacity(0.04)
                                : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    private func numColor(isToday: Bool, idx: Int) -> Color {
        if isToday { return Color(hex: "#2B8BDA") }
        return Color.calenPrimary
    }
    private func lblColor(idx: Int) -> Color {
        Color.calenTertiary
    }
}

// MARK: - TodayPill

/// "오늘의 일정" outline 둥근 라벨.
struct TodayPill: View {
    var text: String = "오늘의 일정"
    var body: some View {
        Text(text)
            .font(.calenCaption)
            .foregroundStyle(Color.calenPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(
                Capsule()
                    .stroke(Color.calenPrimary, lineWidth: 1.2)
            )
    }
}

// MARK: - InlineWakeRow

/// 시간 라벨 + 해 아이콘 + 일정명 inline (카드 미사용).
struct InlineWakeRow: View {
    let time: String   // "8:00"
    let title: String  // "기상"
    let symbolName: String  // "sun.max"

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(time)
                .font(.calenTimeMono)
                .foregroundStyle(Color.calenTertiary)
                .frame(width: 44, alignment: .trailing)
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(Color(hex: "#E8AC55"))
                    .font(.system(.callout))
                Text(title)
                    .font(.calenBodyEmph)
                    .foregroundStyle(Color.calenPrimary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - DriveSegmentView

/// 점선 + 차 캡슐 + 이동 시간 라벨 (시안 정확 반영).
struct DriveSegmentView: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 6) {
            // 점선 — 좌측 들여쓰기 위치 시작
            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                .foregroundStyle(Color(hex: "#B5CDE8"))
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "#E8F1FE"), Color(hex: "#DBE7F7")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color(hex: "#2B8BDA").opacity(0.08), lineWidth: 1))
                Image(systemName: "car")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.calenPrimary)
            }

            Text(driveText)
                .font(.calenBodyEmph)
                .foregroundStyle(Color.calenPrimary)
                .fixedSize()
        }
        .padding(.leading, 0)
        .padding(.trailing, 0)
        .padding(.vertical, 4)
    }

    private var driveText: String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            if m == 0 { return "\(h)시간 이동" }
            return "\(h)시간 \(m)분 이동"
        }
        return "\(minutes)분 이동"
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX, y: y))
        return p
    }
}

// MARK: - ScheduleCard

/// 일정 카드 (work / meeting / dinner 3종 톤).
/// 좌측 흰 원 안 라인 아이콘 + 타이틀 + (요약 또는 bullets) + (액션 칩).
struct ScheduleCard: View {

    enum Tone {
        case work, meeting, dinner

        var background: Color {
            switch self {
            case .work:    return CalenTheme.CardTone.work
            case .meeting: return CalenTheme.CardTone.meeting
            case .dinner:  return CalenTheme.CardTone.dinner
            }
        }
        var icon: String {
            switch self {
            case .work:    return "building.2"
            case .meeting: return "person.crop.circle"
            case .dinner:  return "fork.knife"
            }
        }
    }

    enum Body_ {
        case bullets([String])
        case summary(String)
    }

    let time: String      // "9:00"
    let tone: Tone
    let title: String
    let bodyContent: Body_
    let actions: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(.calenTimeMono)
                .foregroundStyle(Color.calenTertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 14)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tone.background)

                HStack(alignment: .top, spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.calenTitle)
                            .foregroundStyle(Color.calenPrimary)
                        bodySection
                        if !actions.isEmpty {
                            chipsRow
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
            Image(systemName: tone.icon)
                .font(.system(.callout, design: .default).weight(.medium))
                .foregroundStyle(Color.calenPrimary)
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        switch bodyContent {
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Color.calenSecondary)
                        Text(line)
                            .font(.calenCaption)
                            .foregroundStyle(Color.calenPrimary)
                    }
                }
            }
        case .summary(let text):
            Text(text)
                .font(.calenCaption)
                .foregroundStyle(Color.calenPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 6) {
            ForEach(actions, id: \.self) { action in
                Text(action)
                    .font(.calenCaption)
                    .foregroundStyle(Color(hex: "#2B8BDA"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#DEEAF8"), in: Capsule())
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - BottomTabBar5

/// 5탭 (Home / Calendar / Mic / Person / Settings) — 마이크 inline (시안 정확 반영).
struct BottomTabBar5: View {

    enum Tab: Int, CaseIterable {
        case home, calendar, mic, person, settings

        var symbol: String {
            switch self {
            case .home:     return "house"
            case .calendar: return "calendar"
            case .mic:      return "mic"
            case .person:   return "person"
            case .settings: return "gearshape"
            }
        }
    }

    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(tab == selection
                                         ? Color(hex: "#2B8BDA")
                                         : Color.calenPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .background(
            Color.white
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color(hex: "#F0F1F4")),
                    alignment: .top
                )
        )
    }
}

// MARK: - Helpers

extension Array {
    fileprivate subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
#endif
