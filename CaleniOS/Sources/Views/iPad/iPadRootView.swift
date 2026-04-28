#if os(iOS)
import SwiftUI

// MARK: - iPadRootView (Sprint B)
//
// iPad regular size class 전용 3-column NavigationSplitView.
// compact (iPad Split View 1/3, iPhone) 는 기존 MainTabView 가 담당.
//
// 구조:
//   ┌──────────────┬──────────────────────────┬──────────────┐
//   │ Sidebar      │ Content                  │ Inspector    │
//   │ 240~280pt    │ flex                     │ 320~380pt    │
//   ├──────────────┼──────────────────────────┼──────────────┤
//   │ Calen 로고    │ 선택 nav 의 메인 뷰        │ 일정 상세 또는 │
//   │ 7개 탐색      │ (HomeViewV2 / Chat /     │ AI 인사이트   │
//   │ Calendars    │  Review / Settings ...)  │              │
//   └──────────────┴──────────────────────────┴──────────────┘

struct iPadRootView: View {

    enum Nav: String, CaseIterable, Identifiable {
        case today    = "오늘"
        case calendar = "캘린더"
        case tasks    = "할 일"
        case hermes   = "Hermes"
        case voice    = "Voice"
        case review   = "리뷰"
        case settings = "설정"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .today:    return "house"
            case .calendar: return "calendar"
            case .tasks:    return "checkmark.square"
            case .hermes:   return "bubble.left"
            case .voice:    return "mic"
            case .review:   return "chart.bar"
            case .settings: return "gearshape"
            }
        }
    }

    /// 캘린더 카테고리 (사이드바 토글) — Sprint C 에서 SwiftData 연동.
    struct CalendarCategory: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let colorHex: String
        var enabled: Bool = true
    }

    @State private var selectedNav: Nav? = .today
    @State private var inspectorVisible: NavigationSplitViewVisibility = .all
    @State private var categories: [CalendarCategory] = [
        .init(name: "Personal",  colorHex: "#2B8BDA"),
        .init(name: "Work",      colorHex: "#DC5959"),
        .init(name: "Google",    colorHex: "#5A6DB5"),
        .init(name: "Family",    colorHex: "#3DAA68")
    ]

    var body: some View {
        NavigationSplitView(columnVisibility: $inspectorVisible) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 480, ideal: 600)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 380)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color(hex: "#2B8BDA"))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedNav) {
            Section {
                ForEach(Nav.allCases) { nav in
                    Label {
                        Text(nav.rawValue)
                            .font(.calenBody)
                    } icon: {
                        Image(systemName: nav.symbol)
                            .foregroundStyle(selectedNav == nav
                                             ? Color(hex: "#2B8BDA")
                                             : Color.calenPrimary)
                    }
                    .tag(nav)
                }
            } header: {
                HStack(spacing: 8) {
                    Text("Calen")
                        .font(.system(.title3).weight(.bold))
                        .foregroundStyle(Color(hex: "#2B8BDA"))
                    Spacer()
                }
                .padding(.bottom, 6)
                .textCase(nil)
            }

            Section("캘린더") {
                ForEach($categories) { $cat in
                    Toggle(isOn: $cat.enabled) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(hex: cat.colorHex))
                                .frame(width: 10, height: 10)
                            Text(cat.name)
                                .font(.calenCaption)
                                .foregroundStyle(Color.calenPrimary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Color(hex: "#2B8BDA"))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("탐색")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedNav ?? .today {
        case .today:
            HomeViewV2()
        case .calendar:
            iPadCalendarPlaceholder()
        case .tasks:
            iPadComingSoon(title: "할 일", icon: "checkmark.square")
        case .hermes:
            ChatTabView()
        case .voice:
            iPadComingSoon(title: "Voice", icon: "mic")
        case .review:
            ReviewTabView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("선택된 일정")
                .font(.calenCaption)
                .foregroundStyle(Color.calenSecondary)
                .textCase(.uppercase)

            Text("일정을 선택하면\n여기에 상세가 표시됩니다")
                .font(.calenBody)
                .foregroundStyle(Color.calenSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            // AI 인사이트 카드 (placeholder — Sprint C 에서 Hermes 연동)
            VStack(alignment: .leading, spacing: 6) {
                Text("HERMES · AI")
                    .font(.calenCaption)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .tracking(0.8)
                Text("오늘은 회의가 평균 대비 +30%, 14–17시는 집중 시간으로 비워둘까요?")
                    .font(.calenCaption)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#56C0F0"), Color(hex: "#2B8BDA")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Inspector")
    }
}

// MARK: - Placeholder views

private struct iPadCalendarPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Color(hex: "#2B8BDA"))
            Text("월간 캘린더")
                .font(.calenTitle)
            Text("Sprint C 에서 시안 톤 월간 뷰가 채워집니다")
                .font(.calenCaption)
                .foregroundStyle(Color.calenSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("캘린더")
    }
}

private struct iPadComingSoon: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Color.calenSecondary)
            Text(title)
                .font(.calenTitle)
            Text("준비 중")
                .font(.calenCaption)
                .foregroundStyle(Color.calenSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle(title)
    }
}

// MARK: - Preview

#Preview("iPad — 3-column") {
    iPadRootView()
        .environmentObject(AppState())
        .environmentObject(iOSThemeService.shared)
}
#endif
