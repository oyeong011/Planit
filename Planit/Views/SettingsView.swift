import SwiftUI

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable {
    case profile       = "프로필"
    case schedule      = "스케줄"
    case ai            = "AI 설정"
    case integrations  = "연동"
    case notifications = "알림"
    case advanced      = "고급"

    var icon: String {
        switch self {
        case .profile:       return "person.circle"
        case .schedule:      return "clock"
        case .ai:            return "sparkles"
        case .integrations:  return "link"
        case .notifications: return "bell"
        case .advanced:      return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var goalService: GoalService
    @ObservedObject var authManager: GoogleAuthManager
    @ObservedObject var aiService: AIService
    @ObservedObject var viewModel: CalendarViewModel
    var onDismiss: () -> Void

    @State private var selectedSection: SettingsSection = .profile
    @State private var profile: UserProfile

    init(goalService: GoalService, authManager: GoogleAuthManager, aiService: AIService,
         viewModel: CalendarViewModel, onDismiss: @escaping () -> Void) {
        self.goalService = goalService
        self.authManager = authManager
        self.aiService = aiService
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self._profile = State(initialValue: goalService.profile)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            contentArea.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1150, height: 780)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("설정")
                    .font(.title2.bold())
                Spacer()
                Button { saveAndDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        sidebarItem(section)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }

            Spacer()

            Text("변경사항 자동 저장")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        Button { selectedSection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .frame(width: 20)
                    .foregroundStyle(selectedSection == section ? .purple : .secondary)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selectedSection == section ? Color.purple.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                switch selectedSection {
                case .profile:       profileSection
                case .schedule:      scheduleSection
                case .ai:            aiSection
                case .integrations:  integrationsSection
                case .notifications: notificationsSection
                case .advanced:      advancedSection
                }
            }
            .padding(30)
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader("프로필", subtitle: "개인 리듬과 일하는 방식을 설정합니다", icon: "person.circle")

            settingsCard("에너지 패턴") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("집중력이 가장 높은 시간대를 선택하세요. AI가 중요한 일을 해당 시간에 배치합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(EnergyType.allCases, id: \.self) { type in
                            energyTypeButton(type)
                        }
                    }
                }
            }

            settingsCard("스케줄 페이스") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI가 일정을 제안할 때 얼마나 적극적으로 채울지 결정합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 6) {
                        ForEach(Aggressiveness.allCases, id: \.self) { mode in
                            aggressivenessRow(mode)
                        }
                    }
                }
            }
        }
    }

    private func energyTypeButton(_ type: EnergyType) -> some View {
        Button {
            profile.energyType = type
            autosave()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: energyTypeIcon(type))
                    .font(.system(size: 18))
                    .foregroundStyle(profile.energyType == type ? .purple : .secondary)
                Text(type.rawValue)
                    .font(.system(size: 12, weight: profile.energyType == type ? .semibold : .regular))
                    .foregroundStyle(profile.energyType == type ? .primary : .secondary)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(profile.energyType == type ? Color.purple.opacity(0.12) : Color(nsColor: .controlColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(profile.energyType == type ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func energyTypeIcon(_ type: EnergyType) -> String {
        switch type {
        case .morning:  return "sunrise"
        case .evening:  return "moon.stars"
        case .balanced: return "sun.max"
        }
    }

    private func aggressivenessRow(_ mode: Aggressiveness) -> some View {
        Button {
            profile.aggressiveness = mode
            autosave()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: profile.aggressiveness == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(profile.aggressiveness == mode ? .purple : .secondary)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .medium))
                    Text(aggressivenessDesc(mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(profile.aggressiveness == mode ? Color.purple.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func aggressivenessDesc(_ mode: Aggressiveness) -> String {
        switch mode {
        case .manual:   return "모든 일정을 직접 관리합니다. AI는 조용합니다."
        case .assist:   return "AI가 제안만 합니다. 수락은 직접 결정합니다."
        case .semiAuto: return "승인된 제안을 자동으로 캘린더에 등록합니다."
        case .auto:     return "AI가 자동으로 최적 일정을 생성하고 등록합니다."
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader("스케줄", subtitle: "근무 시간과 일일 집중 가능 시간을 설정합니다", icon: "clock")

            settingsCard("근무 시간") {
                VStack(spacing: 16) {
                    HStack(spacing: 24) {
                        labeledHourPicker("출근", $profile.workStartHour, range: 5...12)
                        Text("→").foregroundStyle(.secondary)
                        labeledHourPicker("퇴근", $profile.workEndHour, range: 14...23)
                        Spacer()
                        Text("\(profile.workEndHour - profile.workStartHour)시간 근무")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                    HStack(spacing: 24) {
                        labeledHourPicker("점심 시작", $profile.lunchStartHour, range: 11...14)
                        Text("→").foregroundStyle(.secondary)
                        labeledHourPicker("점심 종료", $profile.lunchEndHour, range: 12...15)
                        Spacer()
                    }
                }
            }

            settingsCard("통근 시간") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("편도 통근 시간")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(profile.commuteMinutes)분")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.purple)
                    }
                    Slider(value: Binding(
                        get: { Double(profile.commuteMinutes) },
                        set: { profile.commuteMinutes = Int($0); autosave() }
                    ), in: 0...120, step: 5)
                    .accentColor(.purple)
                    Text("왕복 \(profile.commuteMinutes * 2)분 · 하루 집중 시간에서 자동 제외됩니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard("하루 집중 가능 시간") {
                VStack(spacing: 14) {
                    capacityRow("평일", value: $profile.weekdayCapacityMinutes)
                    Divider()
                    capacityRow("주말", value: $profile.weekendCapacityMinutes)
                }
            }
        }
    }

    private func capacityRow(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                let h = value.wrappedValue / 60
                let m = value.wrappedValue % 60
                Text(m == 0 ? "\(h)시간" : "\(h)시간 \(m)분")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.purple)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0); autosave() }
            ), in: 60...480, step: 30)
            .accentColor(.purple)
        }
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader("AI 설정", subtitle: "일정 분석과 계획에 사용할 AI를 선택합니다", icon: "sparkles")

            settingsCard("AI 엔진") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        aiProviderRow(provider)
                    }
                }
            }

            settingsCard("현재 상태") {
                VStack(spacing: 10) {
                    aiStatusRow("Claude CLI", available: aiService.claudeAvailable,
                                detail: aiService.claudeAvailable ? "설치됨 — 강력한 자연어 이해" : "설치 필요: brew install claude")
                    Divider()
                    aiStatusRow("Codex CLI", available: aiService.codexAvailable,
                                detail: aiService.codexAvailable ? "설치됨 — 코드 최적화 특화" : "설치 필요: npm install -g @openai/codex")
                }
            }

            settingsCard("저장하기") {
                Button {
                    aiService.saveSettings()
                } label: {
                    Text("AI 설정 저장")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func aiProviderRow(_ provider: AIProvider) -> some View {
        let isSelected = aiService.provider == provider
        let isAvailable: Bool = provider == .claude ? aiService.claudeAvailable : aiService.codexAvailable

        return Button {
            aiService.provider = provider
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? .purple : .secondary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(provider.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                        if isAvailable {
                            Text("설치됨")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.12)))
                        } else {
                            Text("미설치")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }
                    Text(providerDesc(provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(provider.defaultModel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.purple.opacity(0.08) : Color(nsColor: .controlColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.purple.opacity(0.35) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func providerDesc(_ provider: AIProvider) -> String {
        switch provider {
        case .claude: return "자연어 이해 능력이 뛰어납니다. 복잡한 일정 조정과 목표 분석에 적합합니다."
        case .codex:  return "코드 기반 최적화에 특화되어 있습니다. 빠른 규칙 기반 계획 생성에 유용합니다."
        }
    }

    private func aiStatusRow(_ name: String, available: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(available ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader("연동", subtitle: "외부 서비스와 캘린더 연결을 관리합니다", icon: "link")

            settingsCard("Google Calendar") {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(authManager.isAuthenticated ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: authManager.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(authManager.isAuthenticated ? .green : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(authManager.isAuthenticated ? "연결됨" : "연결되지 않음")
                                .font(.system(size: 14, weight: .semibold))
                            if let email = authManager.userEmail {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(authManager.isAuthenticated ? "이메일 정보 없음" : "Google 계정을 연결하면 일정을 동기화합니다")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if authManager.isAuthenticated {
                            Button("연결 해제") {
                                authManager.logout()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundStyle(.red)
                        } else {
                            Button("Google 로그인") {
                                Task { await authManager.startOAuthFlow() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("캘린더 데이터는 기기에만 저장됩니다. AI는 이벤트 제목과 시간만 참조합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            settingsCard("Apple 연동") {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Apple 캘린더 동기화")
                                .font(.system(size: 13, weight: .medium))
                            Text("기기의 Apple 캘린더 이벤트를 함께 표시합니다")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.appleCalendarEnabled },
                            set: { viewModel.appleCalendarEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Apple 미리 알림 가져오기")
                                .font(.system(size: 13, weight: .medium))
                            Text("미리 알림 항목을 할 일로 가져옵니다")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.appleRemindersEnabled },
                            set: { viewModel.appleRemindersEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
            }

            settingsCard("Google 없이 사용") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Google 로그인 건너뛰기")
                            .font(.system(size: 13, weight: .medium))
                        Text("Apple 캘린더나 캘린더 없이 AI 기능만 사용합니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "planit.skipGoogleAuth") },
                        set: { UserDefaults.standard.set($0, forKey: "planit.skipGoogleAuth") }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader("알림", subtitle: "아침 브리핑과 저녁 리뷰 알림 시간을 설정합니다", icon: "bell")

            settingsCard("아침 브리핑") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("아침 브리핑 시간")
                                .font(.system(size: 13, weight: .medium))
                            Text("오늘 일정 요약과 목표 진행 상황을 알려드립니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        hourPicker($profile.morningBriefHour, range: 5...11)
                    }
                }
            }

            settingsCard("저녁 리뷰") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("저녁 리뷰 시간")
                                .font(.system(size: 13, weight: .medium))
                            Text("오늘 완료된 일정을 리뷰하고 내일 계획을 세웁니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        hourPicker($profile.eveningReviewHour, range: 17...23)
                    }
                }
            }

            settingsCard("알림 권한") {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("시스템 알림 권한이 필요합니다")
                            .font(.system(size: 13, weight: .medium))
                        Text("macOS 시스템 설정 → 알림 → Calen 에서 허용하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("시스템 설정 열기") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader("고급", subtitle: "데이터 관리 및 앱 초기화 옵션입니다", icon: "wrench.and.screwdriver")

            settingsCard("온보딩") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("온보딩 재시작")
                            .font(.system(size: 13, weight: .medium))
                        Text("목표 설정 화면을 처음부터 다시 진행합니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("재시작") {
                        profile.onboardingDone = false
                        goalService.profile = profile
                        goalService.saveProfile()
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            settingsCard("데이터 초기화") {
                VStack(spacing: 14) {
                    dataResetRow(
                        title: "완료 기록 초기화",
                        detail: "모든 이벤트 완료/미완료 기록을 삭제합니다",
                        buttonLabel: "초기화",
                        action: {
                            goalService.completions = [:]
                            goalService.saveCompletions()
                        }
                    )
                    Divider()
                    dataResetRow(
                        title: "일일 리뷰 초기화",
                        detail: "오늘 완료된 리뷰를 초기화해 다시 표시합니다",
                        buttonLabel: "초기화",
                        action: {
                            UserDefaults.standard.removeObject(forKey: "calen.review.lastDailyKey")
                        }
                    )
                    Divider()
                    dataResetRow(
                        title: "목표 전체 삭제",
                        detail: "등록된 모든 목표를 삭제합니다. 되돌릴 수 없습니다.",
                        buttonLabel: "삭제",
                        isDestructive: true,
                        action: {
                            goalService.goals = []
                            goalService.saveGoals()
                        }
                    )
                }
            }

            settingsCard("앱 정보") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calen")
                            .font(.system(size: 14, weight: .semibold))
                        Text("버전 1.0 · 개인 AI 캘린더 어시스턴트")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private func dataResetRow(title: String, detail: String, buttonLabel: String,
                               isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonLabel, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(isDestructive ? .red : .orange)
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text(title)
                    .font(.title2.bold())
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    private func labeledHourPicker(_ label: String, _ binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            hourPicker(binding, range: range)
        }
    }

    private func hourPicker(_ binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker("", selection: binding) {
            ForEach(Array(range), id: \.self) { hour in
                Text("\(hour)시").tag(hour)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 76)
        .onChange(of: binding.wrappedValue) { _ in autosave() }
    }

    private func autosave() {
        goalService.profile = profile
        goalService.saveProfile()
    }

    private func saveAndDismiss() {
        autosave()
        onDismiss()
    }
}
