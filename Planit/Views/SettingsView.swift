import SwiftUI

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable {
    case profile       = "profile"
    case schedule      = "schedule"
    case ai            = "ai"
    case integrations  = "integrations"
    case notifications = "notifications"
    case advanced      = "advanced"

    var localizedTitle: String { NSLocalizedString("settings.section.\(rawValue)", comment: "") }

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
    @State private var apiKeyInput: String = ""
    @State private var apiKeySaved: Bool = false

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
                Text(String(localized: "settings.title"))
                    .font(.title2.bold())
                Spacer()
                Button { saveAndDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                        .frame(width: 24, height: 24)
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

            Text(String(localized: "settings.autosave"))
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
                Text(section.localizedTitle)
                    .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selectedSection == section ? Color.purple.opacity(0.12) : Color.clear)
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
                    .foregroundStyle(profile.energyType == type ? .purple : .secondary)
                Text(type.localizedTitle)
                    .font(.system(size: 12, weight: profile.energyType == type ? .semibold : .regular))
                    .foregroundStyle(profile.energyType == type ? .primary : .secondary)
            }
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
                    .foregroundStyle(profile.aggressiveness == mode ? .purple : .secondary)
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
                    .fill(profile.aggressiveness == mode ? Color.purple.opacity(0.08) : Color.clear)
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
                            .foregroundStyle(.purple)
                    }
                    Slider(value: Binding(
                        get: { Double(profile.commuteMinutes) },
                        set: { profile.commuteMinutes = Int($0); autosave() }
                    ), in: 0...120, step: 5)
                    .accentColor(.purple)
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
            sectionHeader(String(localized: "settings.section.ai"), subtitle: String(localized: "settings.ai.subtitle"), icon: "sparkles")

            settingsCard(String(localized: "settings.ai.engine.card")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        aiProviderRow(provider)
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

            settingsCard(String(localized: "settings.ai.apikey.card")) {
                apiKeySection
            }

            settingsCard(String(localized: "settings.ai.save.card")) {
                Button {
                    aiService.saveSettings()
                } label: {
                    Text(String(localized: "settings.ai.save.button"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func aiProviderRow(_ provider: AIProvider) -> some View {
        let isSelected = aiService.provider == provider
        let isAvailable: Bool = {
            switch provider {
            case .claude:    return aiService.claudeAvailable
            case .codex:     return aiService.codexAvailable
            case .claudeAPI: return !aiService.claudeAPIKey.isEmpty
            }
        }()

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
                    .fill(isSelected ? Color.purple.opacity(0.08) : Color(nsColor: .controlColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.purple.opacity(0.35) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func providerDesc(_ provider: AIProvider) -> String {
        switch provider {
        case .claude:    return String(localized: "settings.ai.claude.desc")
        case .codex:     return String(localized: "settings.ai.codex.desc")
        case .claudeAPI: return String(localized: "settings.ai.claudeapi.desc")
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
                Text(String(localized: "settings.ai.apikey.label"))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if !aiService.claudeAPIKey.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(String(localized: "settings.ai.apikey.set"))
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack(spacing: 8) {
                SecureField(String(localized: "settings.ai.apikey.placeholder"), text: $apiKeyInput)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        // 기존 키 표시 (일부만)
                        if !aiService.claudeAPIKey.isEmpty {
                            apiKeyInput = aiService.claudeAPIKey
                        }
                    }

                Button {
                    aiService.saveClaudeAPIKey(apiKeyInput)
                    apiKeySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { apiKeySaved = false }
                } label: {
                    Text(apiKeySaved ? String(localized: "common.saved") : String(localized: "common.save"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(apiKeySaved ? Color.green : Color.purple))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(String(localized: "settings.ai.apikey.hint"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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

            settingsCard(String(localized: "settings.google.skip.card")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "settings.google.skip.title"))
                            .font(.system(size: 13, weight: .medium))
                        Text(String(localized: "settings.google.skip.desc"))
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
            sectionHeader(String(localized: "settings.section.advanced"), subtitle: String(localized: "settings.advanced.subtitle"), icon: "wrench.and.screwdriver")

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
                        Text(String(localized: "settings.app.version"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Language Card

    @ObservedObject private var languageManager = LanguageManager.shared

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
                                        .foregroundStyle(.purple)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isCurrent ? Color.purple.opacity(0.12) : Color(nsColor: .controlColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isCurrent ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1.5)
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
                Text(verbatim: String(format: String(localized: "settings.hour.format"), hour)).tag(hour)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 76)
        .onChange(of: binding.wrappedValue) { autosave() }
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
