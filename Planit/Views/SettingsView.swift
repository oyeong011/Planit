import SwiftUI

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable {
    case profile       = "profile"
    case ai            = "ai"
    case schedule      = "schedule"
    case context       = "context"
    case integrations  = "integrations"
    case notifications = "notifications"
    case appearance    = "appearance"
    case advanced      = "advanced"

    var localizedTitle: String { NSLocalizedString("settings.section.\(rawValue)", comment: "") }

    var icon: String {
        switch self {
        case .profile:       return "person.circle"
        case .schedule:      return "clock"
        case .ai:            return "sparkles"
        case .context:       return "brain.head.profile"
        case .integrations:  return "link"
        case .notifications: return "bell"
        case .appearance:    return "paintpalette"
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
    @ObservedObject var userContextService: UserContextService
    @ObservedObject var hermesMemoryService: HermesMemoryService
    var onDismiss: () -> Void

    @State private var selectedSection: SettingsSection = .profile
    @State private var profile: UserProfile
    @ObservedObject private var appearance = AppearanceService.shared
    @ObservedObject private var calendarThemeService = CalendarThemeService.shared

    init(goalService: GoalService, authManager: GoogleAuthManager, aiService: AIService,
         viewModel: CalendarViewModel, userContextService: UserContextService,
         hermesMemoryService: HermesMemoryService,
         onDismiss: @escaping () -> Void) {
        self.goalService = goalService
        self.authManager = authManager
        self.aiService = aiService
        self.viewModel = viewModel
        self.userContextService = userContextService
        self.hermesMemoryService = hermesMemoryService
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
        .background(Color.platformWindowBackground)
        .overlay(alignment: .topTrailing) {
            Button { saveAndDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "settings.title"))
                    .font(.title2.bold())
                Spacer()
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

            Text(String(localized: "settings.autosave"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .background(Color.platformControlBackground)
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        Button { selectedSection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .frame(width: 20)
                    .foregroundStyle(selectedSection == section ? calendarThemeService.current.accent : .secondary)
                Text(section.localizedTitle)
                    .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selectedSection == section ? calendarThemeService.current.accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
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
                case .ai:            aiSection
                case .schedule:      scheduleSection
                case .context:       contextSection
                case .integrations:  integrationsSection
                case .notifications: notificationsSection
                case .appearance:    appearanceSection
                case .advanced:      advancedSection
                }
            }
            .padding(30)
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(String(localized: "settings.section.profile"), subtitle: String(localized: "settings.profile.subtitle"), icon: "person.circle")

            settingsCard(String(localized: "settings.energy.card")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "settings.energy.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(EnergyType.allCases, id: \.self) { type in
                            energyTypeButton(type)
                        }
                    }
                }
            }

            settingsCard(String(localized: "settings.pace.card")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "settings.pace.desc"))
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
                    .foregroundStyle(profile.energyType == type ? calendarThemeService.current.accent : .secondary)
                Text(type.localizedTitle)
                    .font(.system(size: 12, weight: profile.energyType == type ? .semibold : .regular))
                    .foregroundStyle(profile.energyType == type ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(profile.energyType == type ? calendarThemeService.current.accent.opacity(0.12) : Color.platformControl)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(profile.energyType == type ? calendarThemeService.current.accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
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
                    .foregroundStyle(profile.aggressiveness == mode ? calendarThemeService.current.accent : .secondary)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.localizedTitle)
                        .font(.system(size: 13, weight: .medium))
                    Text(aggressivenessDesc(mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(profile.aggressiveness == mode ? calendarThemeService.current.accent.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func aggressivenessDesc(_ mode: Aggressiveness) -> String {
        switch mode {
        case .manual:   return String(localized: "settings.aggressiveness.manual.desc")
        case .assist:   return String(localized: "settings.aggressiveness.assist.desc")
        case .semiAuto: return String(localized: "settings.aggressiveness.semiauto.desc")
        case .auto:     return String(localized: "settings.aggressiveness.auto.desc")
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(String(localized: "settings.section.schedule"), subtitle: String(localized: "settings.schedule.subtitle"), icon: "clock")

            settingsCard(String(localized: "settings.work.card")) {
                VStack(spacing: 16) {
                    HStack(spacing: 24) {
                        labeledHourPicker(String(localized: "settings.work.start.label"), $profile.workStartHour, range: 5...12)
                        Text("→").foregroundStyle(.secondary)
                        labeledHourPicker(String(localized: "settings.work.end.label"), $profile.workEndHour, range: 14...23)
                        Spacer()
                        Text(verbatim: String(format: String(localized: "settings.work.hours.format"), profile.workEndHour - profile.workStartHour))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                    HStack(spacing: 24) {
                        labeledHourPicker(String(localized: "settings.lunch.start.label"), $profile.lunchStartHour, range: 11...14)
                        Text("→").foregroundStyle(.secondary)
                        labeledHourPicker(String(localized: "settings.lunch.end.label"), $profile.lunchEndHour, range: 12...15)
                        Spacer()
                    }
                }
            }

            settingsCard(String(localized: "settings.commute.card")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "settings.commute.label"))
                            .font(.system(size: 13))
                        Spacer()
                        Text(verbatim: String(format: String(localized: "settings.commute.minutes.format"), profile.commuteMinutes))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(calendarThemeService.current.accent)
                    }
                    Slider(value: Binding(
                        get: { Double(profile.commuteMinutes) },
                        set: { profile.commuteMinutes = Int($0); autosave() }
                    ), in: 0...120, step: 5)
                    .accentColor(calendarThemeService.current.accent)
                    Text(verbatim: String(format: String(localized: "settings.commute.roundtrip.format"), profile.commuteMinutes * 2))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard(String(localized: "settings.capacity.card")) {
                VStack(spacing: 14) {
                    capacityRow(String(localized: "settings.capacity.weekday"), value: $profile.weekdayCapacityMinutes)
                    Divider()
                    capacityRow(String(localized: "settings.capacity.weekend"), value: $profile.weekendCapacityMinutes)
                }
            }

            settingsCard(String(localized: "settings.focus.windows.card")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.focus.windows.title"))
                            .font(.system(size: 13, weight: .medium))
                        Text(String(localized: "settings.focus.windows.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { profile.usesFocusWindowsForAI },
                        set: { profile.usesFocusWindowsForAI = $0; autosave() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
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
                Text(verbatim: m == 0 ? String(format: String(localized: "settings.capacity.hours.format"), h) : String(format: String(localized: "settings.capacity.hours.minutes.format"), h, m))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(calendarThemeService.current.accent)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0); autosave() }
            ), in: 60...480, step: 30)
            .accentColor(calendarThemeService.current.accent)
        }
    }

    // MARK: - AI Section

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(String(localized: "settings.section.ai"), subtitle: String(localized: "settings.ai.subtitle"), icon: "sparkles")

            settingsCard(String(localized: "settings.ai.engine.card")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        aiProviderRow(provider)
                    }
                }
            }

            settingsCard(String(localized: "settings.ai.tone.card")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AITone.allCases, id: \.self) { tone in
                        aiToneRow(tone)
                    }
                }
            }

            settingsCard(String(localized: "settings.ai.status.card")) {
                VStack(spacing: 10) {
                    aiStatusRow("Claude CLI", available: aiService.claudeAvailable,
                                detail: aiService.claudeAvailable ? String(localized: "settings.ai.claude.installed.detail") : String(localized: "settings.ai.claude.install.hint"))
                    Divider()
                    aiStatusRow("Codex CLI", available: aiService.codexAvailable,
                                detail: aiService.codexAvailable ? String(localized: "settings.ai.codex.installed.detail") : String(localized: "settings.ai.codex.install.hint"))
                }
            }
        }
    }

    private func aiProviderRow(_ provider: AIProvider) -> some View {
        let isSelected = aiService.provider == provider
        let isAvailable: Bool = provider == .claude ? aiService.claudeAvailable : aiService.codexAvailable

        return Button {
            aiService.provider = provider
            aiService.saveSettings()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? calendarThemeService.current.accent : .secondary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(provider.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                        if isAvailable {
                            Text(String(localized: "settings.ai.installed.badge"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.12)))
                        } else {
                            Text(String(localized: "settings.ai.not.installed.badge"))
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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? calendarThemeService.current.accent.opacity(0.08) : Color.platformControl.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? calendarThemeService.current.accent.opacity(0.35) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func aiToneRow(_ tone: AITone) -> some View {
        let isSelected = aiService.tone == tone

        return Button {
            aiService.tone = tone
            aiService.saveSettings()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? calendarThemeService.current.accent : .secondary)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tone.localizedTitle)
                        .font(.system(size: 13, weight: .medium))
                    Text(tone.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? calendarThemeService.current.accent.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func providerDesc(_ provider: AIProvider) -> String {
        switch provider {
        case .claude: return String(localized: "settings.ai.claude.desc")
        case .codex:  return String(localized: "settings.ai.codex.desc")
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
            sectionHeader(String(localized: "settings.section.integrations"), subtitle: String(localized: "settings.integrations.subtitle"), icon: "link")

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
                            Text(authManager.isAuthenticated ? String(localized: "settings.google.connected") : String(localized: "settings.google.not.connected"))
                                .font(.system(size: 14, weight: .semibold))
                            if let email = authManager.userEmail {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(authManager.isAuthenticated ? String(localized: "settings.google.no.email") : String(localized: "settings.google.connect.hint"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if authManager.isAuthenticated {
                            Button(String(localized: "settings.google.disconnect.button")) {
                                authManager.logout()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundStyle(.red)
                        } else {
                            Button(String(localized: "settings.google.login.button")) {
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
                        Text(String(localized: "settings.google.privacy"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            settingsCard(String(localized: "settings.apple.card")) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.apple.calendar.title"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "settings.apple.calendar.desc"))
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
                            Text(String(localized: "settings.apple.reminders.title"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "settings.apple.reminders.desc"))
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
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(String(localized: "settings.section.notifications"), subtitle: String(localized: "settings.notifications.subtitle"), icon: "bell")

            settingsCard(String(localized: "settings.morning.card")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.morning.time.title"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "settings.morning.time.desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        hourPicker($profile.morningBriefHour, range: 5...11)
                    }
                }
            }

            settingsCard(String(localized: "settings.evening.card")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.evening.time.title"))
                                .font(.system(size: 13, weight: .medium))
                            Text(String(localized: "settings.evening.time.desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        hourPicker($profile.eveningReviewHour, range: 17...23)
                    }
                }
            }

            settingsCard(String(localized: "settings.notifications.permission.card")) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.notifications.permission.title"))
                            .font(.system(size: 13, weight: .medium))
                        Text(String(localized: "settings.notifications.permission.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.notifications.open.system")) {
                        openURL(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Advanced Section

    // MARK: - 사용자 컨텍스트 섹션

    @State private var contextEditMode: Bool = false

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(String(localized: "settings.context.title"),
                          subtitle: String(localized: "settings.context.subtitle"),
                          icon: "brain.head.profile")

            // 현재 파악된 정보 요약
            settingsCard(String(localized: "settings.context.card.my.info")) {
                VStack(alignment: .leading, spacing: 12) {
                    if userContextService.contextSummary.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text(String(localized: "settings.context.empty.hint"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(userContextService.contextSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineLimit(8)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        Button {
                            openURL(URL(fileURLWithPath: userContextService.contextFilePath))
                        } label: {
                            Label(String(localized: "settings.context.open.file"), systemImage: "doc.text")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            #if os(macOS)
                            NSWorkspace.shared.selectFile(userContextService.contextFilePath, inFileViewerRootedAtPath: "")
                            #endif
                        } label: {
                            Label(String(localized: "settings.context.show.finder"), systemImage: "folder")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Text(userContextService.contextFilePath.components(separatedBy: "/").last ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            // 외부 검색 지원 목록
            settingsCard(String(localized: "settings.context.card.exams")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.context.exams.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    let exams = localizedExamList()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 6) {
                        ForEach(exams, id: \.self) { exam in
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue)
                                Text(exam)
                                    .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.blue.opacity(0.06)))
                        }
                    }
                }
            }

            // 작동 방식 안내
            settingsCard(String(localized: "settings.context.card.how")) {
                VStack(alignment: .leading, spacing: 8) {
                    contextHowItWorksRow(icon: "message", color: .blue,
                        title: String(localized: "settings.context.how.chat"),
                        desc: String(localized: "settings.context.how.chat.desc"))
                    contextHowItWorksRow(icon: "magnifyingglass.circle", color: .orange,
                        title: String(localized: "settings.context.how.search"),
                        desc: String(localized: "settings.context.how.search.desc"))
                    contextHowItWorksRow(icon: "brain", color: calendarThemeService.current.accent,
                        title: String(localized: "settings.context.how.recommend"),
                        desc: String(localized: "settings.context.how.recommend.desc"))
                    contextHowItWorksRow(icon: "checkmark.square", color: .green,
                        title: String(localized: "settings.context.how.style"),
                        desc: String(localized: "settings.context.how.style.desc"))
                }
            }

            // Hermes 장기 기억 카드
            hermesMemoryCard
        }
        .padding(24)
    }

    // MARK: - Hermes 기억 카드

    private var hermesMemoryCard: some View {
        settingsCard("🧠 Hermes 장기 기억") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .font(.system(size: 13))
                    Text("대화와 행동에서 학습한 사용자 패턴 (\(hermesMemoryService.facts.count)개)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if !hermesMemoryService.facts.isEmpty {
                        Button(role: .destructive) {
                            hermesMemoryService.clearAll()
                        } label: {
                            Label("전체 삭제", systemImage: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if hermesMemoryService.facts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("아직 기억된 패턴이 없습니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("채팅에서 '아침에 집중이 잘 돼요', '저녁엔 못해요', '30분 단위 블록 선호' 같은 문장을 말하면 자동으로 학습합니다.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                } else {
                    Divider()
                    ForEach(hermesMemoryService.facts) { fact in
                        hermesMemoryRow(fact)
                    }
                }

                if !hermesMemoryService.decisions.isEmpty {
                    Divider()
                    Text("최근 계획 결정")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(hermesMemoryService.decisions.prefix(5)) { decision in
                        HStack(spacing: 8) {
                            Text(decision.intent)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.blue)
                            Text(decision.summary)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer()
                            Text(decision.outcome.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(decision.outcome == .accepted ? .green : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func hermesMemoryRow(_ fact: MemoryFact) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(fact.category.displayName)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.purple.opacity(0.12)))
                .foregroundStyle(.purple)
                .frame(minWidth: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(fact.key)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text(fact.value)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(fact.confidence * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(confidenceColor(fact.confidence))
                Text(relativeDate(fact.updatedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Button {
                hermesMemoryService.forget(id: fact.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("이 기억 삭제")
        }
        .padding(.vertical, 4)
    }

    private func confidenceColor(_ c: Double) -> Color {
        if c >= 0.75 { return .green }
        if c >= 0.5 { return .orange }
        return .secondary
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// 현재 로케일에 맞는 시험/자격증 목록 반환
    private func localizedExamList() -> [String] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        switch lang {
        case "ko":
            return ["정보처리기사 (정처기)", "TOEIC (토익)", "TOEFL (토플)",
                    "공무원 시험", "한국사능력검정", "SQLD", "정보보안기사",
                    "리눅스마스터", "수능", "AWS 자격증", "CPA", "세무사"]
        case "ja":
            return ["基本情報技術者", "TOEIC", "TOEFL", "AWS 資格",
                    "情報処理安全確保支援士", "日商簿記", "FP技能士", "IELTS", "英検", "PMP"]
        case "zh":
            return ["TOEIC", "TOEFL", "IELTS", "AWS 認證", "PMP",
                    "CPA", "雅思", "托福", "GRE", "CFA"]
        default:
            return ["TOEIC", "TOEFL", "IELTS", "AWS Certification", "PMP",
                    "GRE", "GMAT", "CPA", "CFA", "CompTIA A+", "Scrum Master", "PMP"]
        }
    }

    private func contextHowItWorksRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(String(localized: "settings.section.advanced"), subtitle: String(localized: "settings.advanced.subtitle"), icon: "wrench.and.screwdriver")

            settingsCard(String(localized: "settings.apple.diagnostics.card")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        Text(mirrorFilterStatsLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(mirrorFilterAccessibilityLabel)

                    Text(String(localized: "settings.apple.diagnostics.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard(String(localized: "settings.onboarding.card")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.onboarding.restart.title"))
                            .font(.system(size: 13, weight: .medium))
                        Text(String(localized: "settings.onboarding.restart.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.onboarding.restart.button")) {
                        profile.onboardingDone = false
                        goalService.profile = profile
                        goalService.saveProfile()
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            settingsCard(String(localized: "settings.data.reset.card")) {
                VStack(spacing: 14) {
                    dataResetRow(
                        title: String(localized: "settings.completions.reset.title"),
                        detail: String(localized: "settings.completions.reset.desc"),
                        buttonLabel: String(localized: "settings.completions.reset.button"),
                        action: {
                            goalService.completions = [:]
                            goalService.saveCompletions()
                        }
                    )
                    Divider()
                    dataResetRow(
                        title: String(localized: "settings.review.reset.title"),
                        detail: String(localized: "settings.review.reset.desc"),
                        buttonLabel: String(localized: "settings.review.reset.button"),
                        action: {
                            UserDefaults.standard.removeObject(forKey: "calen.review.lastDailyKey")
                            UserDefaults.standard.removeObject(forKey: ReviewService.lastEveningKeyName)
                        }
                    )
                    Divider()
                    dataResetRow(
                        title: String(localized: "settings.goals.delete.title"),
                        detail: String(localized: "settings.goals.delete.desc"),
                        buttonLabel: String(localized: "settings.goals.delete.button"),
                        isDestructive: true,
                        action: {
                            goalService.goals = []
                            goalService.saveGoals()
                        }
                    )
                }
            }

            languageCard

            settingsCard(String(localized: "settings.app.info.card")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calen")
                            .font(.system(size: 14, weight: .semibold))
                        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                        Text("v\(bundleVersion) (\(buildNumber)) · Personal AI Calendar Assistant")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
                        let subject = "Calen v\(version) 피드백"
                        let body = "\n\n---\n앱 버전: \(version)\nmacOS: \(osVersion)"
                        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "mailto:oyeong011@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("피드백 보내기", systemImage: "envelope")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var mirrorFilterStatsLine: String {
        let stats = viewModel.lastMirrorFilterStats
        return String(
            format: NSLocalizedString("settings.apple.diagnostics.summary", comment: ""),
            stats.extCount,
            stats.fingerprintCount,
            stats.suppressCount,
            mirrorFilterLastUpdatedText
        )
    }

    private var mirrorFilterAccessibilityLabel: String {
        let stats = viewModel.lastMirrorFilterStats
        return String(
            format: NSLocalizedString("settings.apple.diagnostics.accessibility", comment: ""),
            stats.extCount,
            stats.fingerprintCount,
            stats.suppressCount,
            mirrorFilterLastUpdatedText
        )
    }

    private var mirrorFilterLastUpdatedText: String {
        guard let lastUpdated = viewModel.lastMirrorFilterStats.lastUpdated else {
            return String(localized: "settings.apple.diagnostics.never")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: lastUpdated)
    }

    // MARK: - Language Card

    @ObservedObject private var languageManager = LanguageManager.shared

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeader(
                String(localized: "settings.section.appearance"),
                subtitle: String(localized: "settings.appearance.subtitle", defaultValue: "앱 표시 방식과 캘린더 색상을 설정합니다"),
                icon: "paintpalette"
            )

            appearanceCard
            calendarThemeCard
        }
    }

    private var appearanceCard: some View {
        settingsCard(String(localized: "settings.appearance.card", defaultValue: "외관")) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "settings.appearance.title", defaultValue: "테마"))
                        .font(.system(size: 13, weight: .medium))
                    Text(String(localized: "settings.appearance.desc", defaultValue: "라이트/다크 모드 또는 시스템 설정을 따릅니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $appearance.mode) {
                    ForEach(AppearanceService.Mode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }

    private var calendarThemeCard: some View {
        settingsCard(String(localized: "settings.calendar.theme.card", defaultValue: "캘린더 테마")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "settings.calendar.theme.desc", defaultValue: "캘린더 그리드, 선택 상태, 이벤트 강조색에 적용됩니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let columns = [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(calendarThemeService.themes) { theme in
                        CalendarThemeTile(
                            theme: theme,
                            isSelected: calendarThemeService.current.id == theme.id
                        ) {
                            calendarThemeService.selectTheme(theme)
                        }
                    }
                }
            }
        }
    }

    private var languageCard: some View {
        settingsCard(String(localized: "settings.language.card")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "settings.language.desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let cols = [GridItem(.adaptive(minimum: 180), spacing: 8)]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(LanguageManager.supported) { lang in
                        let isCurrent = languageManager.currentLanguageCode == lang.id
                        Button {
                            languageManager.setLanguage(lang.id)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lang.localName)
                                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                                    Text(lang.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(calendarThemeService.current.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isCurrent ? calendarThemeService.current.accent.opacity(0.12) : Color.platformControl)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isCurrent ? calendarThemeService.current.accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
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
                    .foregroundStyle(calendarThemeService.current.accent)
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
                        .fill(Color.platformControlBackground)
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
                Text(verbatim: String(format: String(localized: "settings.hour.format"), hour)).tag(hour)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 76)
        .onChange(of: binding.wrappedValue) { autosave() }
    }

    private func autosave() {
        goalService.profile = profile
        aiService.scheduler.apply(profile: profile)
        goalService.saveProfile()
    }

    private func saveAndDismiss() {
        autosave()
        onDismiss()
    }
}

private struct CalendarThemeTile: View {
    let theme: CalendarTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(theme.primaryHex)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                }

                HStack(spacing: 4) {
                    ForEach(theme.swatchHexes, id: \.self) { hex in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: hex) ?? .secondary)
                            .frame(height: 18)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.backgroundOverlay.opacity(0.7) : Color.platformControl.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accent.opacity(0.55) : Color.secondary.opacity(0.12), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) calendar theme")
    }
}
