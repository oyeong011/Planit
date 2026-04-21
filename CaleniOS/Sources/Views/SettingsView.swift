#if os(iOS)
import SwiftUI
import UIKit

// MARK: - SettingsView (v0.1.2 Brand Card Redesign)
//
// v0.1.1까지의 iOS 기본 `.insetGrouped` List 를 버리고 macOS 브랜드 감각에 맞춘
// ScrollView + 카드 섹션 레이아웃으로 재구성했다.
//
// 구성:
//  - BrandHeader: 앱 아이콘 + 이름 + 버전
//  - ProfileCard: 아바타 + 이름 + Google 상태
//  - AccountCard: OAuth 클라이언트 ID / 로그인·로그아웃
//  - AISection: Claude API 키 / 모델 정보 / 데이터 초기화
//  - AppearanceCard: 테마 picker + 언어 picker (v0.1.2 핵심 — 테마/i18n)
//  - AppCard: 알림 / 캘린더 동기화 / iCloud Hermes 동기화
//  - AboutCard: 버전 / 개인정보 / 문의
//
// 공통 패턴:
//  - `SectionHeader`: 섹션 제목(.footnote, .secondary)
//  - `SettingsCard`: rounded corner 20, 카드 내부 RowGroup 레이아웃
//  - `Row`/`ToggleRow`/`ButtonRow`: 아이콘(30×30 square) + 텍스트 + trailing 액션
//  - 모든 아이콘 배경/강조 색상은 활성 `iOSThemeService.current`에서 파생

struct SettingsView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: iOSThemeService
    @EnvironmentObject private var language: iOSLanguageService

    @ObservedObject private var googleAuth = iOSGoogleAuthManager.shared

    // MARK: App toggles

    @AppStorage("notificationsEnabled")                private var notificationsEnabled: Bool = true
    @AppStorage("calendarSyncEnabled")                 private var calendarSyncEnabled: Bool = false
    @AppStorage("planit.hermesCloudKitSyncEnabled")    private var hermesCloudKitSyncEnabled: Bool = false

    // MARK: Sheets / alerts

    @State private var showGoogleClientIDSheet = false
    @State private var showClaudeAPIKeySheet   = false
    @State private var showResetAlert          = false
    @State private var showPrivacySheet        = false
    @State private var showContactSheet        = false

    /// API 키 Keychain 캐시 — 매 렌더 I/O 방지.
    @State private var hasClaudeAPIKey: Bool = ClaudeAPIKeychain.load() != nil

    // MARK: Derived

    private var displayName: String {
        if let email = googleAuth.userEmail, !email.isEmpty { return email }
        return NSLocalizedString("settings.user.default", comment: "")
    }

    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                backgroundLayer
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        brandHeader
                        profileCard
                        appearanceCard
                        accountCard
                        aiCard
                        appCard
                        aboutCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 140)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showGoogleClientIDSheet) {
            GoogleClientIDSheet { newID in
                googleAuth.setupCredentials(clientID: newID)
            }
        }
        .sheet(isPresented: $showClaudeAPIKeySheet, onDismiss: {
            hasClaudeAPIKey = ClaudeAPIKeychain.load() != nil
        }) {
            ClaudeAPIKeySheet()
        }
        .sheet(isPresented: $showPrivacySheet) { PrivacyPolicyView() }
        .sheet(isPresented: $showContactSheet) { ContactView() }
        .alert(Text("settings.reset.alert.title"), isPresented: $showResetAlert) {
            Button(NSLocalizedString("settings.reset.button", comment: ""), role: .destructive) {
                googleAuth.logout()
                ClaudeAPIKeychain.remove()
                hasClaudeAPIKey = false
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text("settings.reset.alert.message")
        }
    }

    // MARK: - Background

    /// 테마 cardTint 를 아주 옅게 깔아 일반 리스트 배경 대비 브랜드 감 부여.
    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                theme.current.surface.opacity(0.5),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.current.gradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: theme.current.accent.opacity(0.35), radius: 18, x: 0, y: 10)

                Text("C")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 2) {
                Text("Calen")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("v\(appVersion)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        SettingsCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(theme.current.primary.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text(displayName.prefix(1).uppercased())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.current.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(googleAuth.isAuthenticated
                         ? NSLocalizedString("settings.google.connected", comment: "")
                         : NSLocalizedString("settings.user.default", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Appearance Card (Theme + Language)

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(key: "settings.section.appearance")

            SettingsCard {
                VStack(spacing: 0) {
                    themePickerRow
                    Divider().padding(.leading, 58)
                    languagePickerRow
                }
            }
        }
    }

    private var themePickerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconSquare(systemName: "paintpalette.fill", tint: theme.current.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.theme.title")
                        .font(.system(size: 15, weight: .semibold))
                    Text("settings.theme.subtitle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(theme.current.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(theme.themes) { t in
                        ThemeSwatch(theme: t, isSelected: t.id == theme.current.id) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                theme.select(t)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var languagePickerRow: some View {
        HStack(spacing: 12) {
            IconSquare(systemName: "globe", tint: theme.current.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.language.title")
                    .font(.system(size: 15, weight: .semibold))
                Text("settings.language.subtitle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { language.current },
                set: { language.select($0) }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 156)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    // MARK: - Account Card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(key: "settings.section.account")

            SettingsCard {
                VStack(spacing: 0) {
                    ButtonRow(
                        icon: "key.fill",
                        tint: theme.current.primary,
                        titleKey: "settings.google.clientid",
                        trailing: .badge(googleAuth.hasCredentials
                                         ? NSLocalizedString("settings.google.configured", comment: "")
                                         : NSLocalizedString("settings.google.needed", comment: ""),
                                         warning: !googleAuth.hasCredentials),
                        action: { showGoogleClientIDSheet = true }
                    )

                    Divider().padding(.leading, 58)

                    if googleAuth.isAuthenticated {
                        ButtonRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            tint: Color.red,
                            titleKey: "settings.google.signout",
                            role: .destructive,
                            action: { googleAuth.logout() }
                        )
                    } else {
                        ButtonRow(
                            icon: "person.crop.circle.badge.checkmark",
                            tint: Color.green,
                            titleKey: "settings.google.signin",
                            action: { Task { await googleAuth.startOAuthFlow() } },
                            disabled: !googleAuth.hasCredentials
                        )
                    }

                    if let err = googleAuth.errorMessage, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    // MARK: - AI Card

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(key: "settings.section.ai")

            SettingsCard {
                VStack(spacing: 0) {
                    ButtonRow(
                        icon: "lock.shield.fill",
                        tint: Color(red: 0.60, green: 0.36, blue: 0.91),
                        titleKey: "settings.ai.claude.key",
                        trailing: .badge(hasClaudeAPIKey
                                         ? NSLocalizedString("settings.ai.saved", comment: "")
                                         : NSLocalizedString("settings.ai.not.saved", comment: ""),
                                         warning: !hasClaudeAPIKey),
                        action: { showClaudeAPIKeySheet = true }
                    )

                    Divider().padding(.leading, 58)

                    NavigationLinkRow(
                        icon: "cpu",
                        tint: Color(red: 0.60, green: 0.36, blue: 0.91),
                        titleKey: "settings.ai.model.info",
                        subtitle: "Claude Opus 4.7",
                        destination: { AIModelInfoView() }
                    )

                    Divider().padding(.leading, 58)

                    ButtonRow(
                        icon: "trash.fill",
                        tint: Color.red,
                        titleKey: "settings.ai.reset",
                        role: .destructive,
                        action: { showResetAlert = true }
                    )
                }
            }
        }
    }

    // MARK: - App Card

    private var appCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(key: "settings.section.app")

            SettingsCard {
                VStack(spacing: 0) {
                    ToggleRow(
                        icon: "bell.fill",
                        tint: Color.orange,
                        titleKey: "settings.app.notifications",
                        isOn: $notificationsEnabled,
                        tintOverride: theme.current.primary
                    )
                    Divider().padding(.leading, 58)

                    ToggleRow(
                        icon: "calendar",
                        tint: Color.red,
                        titleKey: "settings.app.calsync",
                        isOn: $calendarSyncEnabled,
                        tintOverride: theme.current.primary
                    )
                    Divider().padding(.leading, 58)

                    ToggleRow(
                        icon: "icloud.fill",
                        tint: Color(red: 0.23, green: 0.60, blue: 0.96),
                        titleKey: "settings.app.icloud.hermes",
                        subtitleKey: "settings.app.icloud.hermes.hint",
                        isOn: $hermesCloudKitSyncEnabled,
                        tintOverride: theme.current.primary
                    )
                }
            }
        }
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(key: "settings.section.info")

            SettingsCard {
                VStack(spacing: 0) {
                    Row(
                        icon: "info.circle.fill",
                        tint: Color.gray,
                        titleKey: "settings.info.version",
                        trailing: .plain(appVersion)
                    )
                    Divider().padding(.leading, 58)

                    ButtonRow(
                        icon: "hand.raised.fill",
                        tint: Color.green,
                        titleKey: "settings.info.privacy",
                        action: { showPrivacySheet = true }
                    )
                    Divider().padding(.leading, 58)

                    ButtonRow(
                        icon: "envelope.fill",
                        tint: theme.current.primary,
                        titleKey: "settings.info.contact",
                        action: { showContactSheet = true }
                    )
                }
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let key: LocalizedStringKey

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 14)
    }
}

// MARK: - SettingsCard

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 4)
    }
}

// MARK: - Icon Square

private struct IconSquare: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint)
                .frame(width: 32, height: 32)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Row primitives

private enum RowTrailing {
    case none
    case plain(String)
    case badge(String, warning: Bool)
    case chevron
}

private struct Row: View {
    let icon: String
    let tint: Color
    let titleKey: LocalizedStringKey
    var subtitleKey: LocalizedStringKey? = nil
    var trailing: RowTrailing = .none
    var role: ButtonRole? = nil

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemName: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(role == .destructive ? .red : .primary)
                if let subtitleKey {
                    Text(subtitleKey)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            switch trailing {
            case .none:
                EmptyView()
            case .plain(let text):
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            case .badge(let text, let warning):
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(warning ? .orange : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(warning ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.10))
                    )
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct ButtonRow: View {
    let icon: String
    let tint: Color
    let titleKey: LocalizedStringKey
    var subtitleKey: LocalizedStringKey? = nil
    var trailing: RowTrailing = .chevron
    var role: ButtonRole? = nil
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(role: role, action: action) {
            Row(
                icon: icon,
                tint: tint,
                titleKey: titleKey,
                subtitleKey: subtitleKey,
                trailing: trailing,
                role: role
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
    }
}

private struct NavigationLinkRow<Destination: View>: View {
    let icon: String
    let tint: Color
    let titleKey: LocalizedStringKey
    var subtitle: String? = nil
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                IconSquare(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToggleRow: View {
    let icon: String
    let tint: Color
    let titleKey: LocalizedStringKey
    var subtitleKey: LocalizedStringKey? = nil
    @Binding var isOn: Bool
    let tintOverride: Color

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitleKey {
                    Text(subtitleKey)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tintOverride)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Theme Swatch

private struct ThemeSwatch: View {
    let theme: CalenTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.gradient)
                        .frame(width: 54, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2.5)
                        )
                        .shadow(color: theme.accent.opacity(isSelected ? 0.35 : 0.15),
                                radius: isSelected ? 10 : 5,
                                x: 0,
                                y: isSelected ? 4 : 2)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Text(theme.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(theme.name))
    }
}

// MARK: - Google Client ID Sheet (unchanged logic, brand styling retained)

private struct GoogleClientIDSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void

    @State private var clientID: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("123-abc.apps.googleusercontent.com", text: $clientID)
                        .focused($isFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("settings.google.clientid")
                } footer: {
                    Text("Google Cloud Console에서 iOS 앱 OAuth 2.0 클라이언트 ID를 발급받아 입력하세요.\n`*.apps.googleusercontent.com` 형식이어야 합니다.")
                }
            }
            .navigationTitle(Text("settings.google.clientid"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.save", comment: "")) {
                        onSave(clientID.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - Claude API Key Sheet (unchanged)

private struct ClaudeAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-api03-...", text: $apiKey)
                        .focused($isFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("settings.ai.claude.key")
                } footer: {
                    Text("`console.anthropic.com`에서 발급받은 `sk-ant-` 형식의 키를 입력하세요.\n키는 기기 Keychain에만 저장되며 서버로 전송되지 않습니다.")
                }

                if ClaudeAPIKeychain.load() != nil {
                    Section {
                        Button(role: .destructive) {
                            ClaudeAPIKeychain.remove()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("common.delete", comment: ""))
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("settings.ai.claude.key"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.save", comment: "")) {
                        if ClaudeAPIKeychain.save(apiKey) {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

// MARK: - AI Model Info View

private struct AIModelInfoView: View {
    @EnvironmentObject private var theme: iOSThemeService

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme.current.accent.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "cpu")
                                .font(.system(size: 26))
                                .foregroundStyle(theme.current.accent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Claude Opus 4.7")
                                .font(.system(size: 18, weight: .bold))
                            Text("Anthropic · 최신 버전")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("기능") {
                InfoRow(icon: "calendar.badge.clock", title: "스마트 일정 분석", description: "일정 패턴을 분석하여 최적의 시간을 제안합니다.")
                InfoRow(icon: "mic.fill", title: "음성 인식", description: "자연어 음성 명령으로 일정을 추가하고 관리합니다.")
                InfoRow(icon: "brain", title: "AI 추천", description: "사용자 습관을 학습하여 맞춤형 일정을 추천합니다.")
            }

            Section("데이터 처리") {
                Text("AI 처리에 사용되는 데이터는 암호화되어 전송되며, Anthropic의 개인정보처리방침에 따라 관리됩니다.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("settings.ai.model.info"))
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.calenBlue)
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Privacy / Contact (unchanged)

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("개인정보처리방침")
                        .font(.system(size: 22, weight: .bold))

                    policyBlock(
                        title: "1. 수집하는 개인정보",
                        body: "Calen은 서비스 제공을 위해 다음과 같은 개인정보를 수집합니다: Google 계정 이메일, 일정 정보. 이 정보는 앱 내에서만 사용되며 외부로 전송되지 않습니다."
                    )
                    policyBlock(
                        title: "2. 개인정보의 이용",
                        body: "수집된 정보는 맞춤형 일정 관리 서비스 제공, AI 모델 학습 개선, 사용자 경험 향상을 위해 활용됩니다."
                    )
                    policyBlock(
                        title: "3. 개인정보 보호",
                        body: "모든 데이터는 기기 내 Keychain에 안전하게 저장되며, Apple의 보안 프레임워크를 통해 보호됩니다."
                    )
                    policyBlock(
                        title: "4. 문의",
                        body: "개인정보 처리와 관련된 문의는 support@calen.app으로 연락해 주세요."
                    )
                }
                .padding(24)
            }
            .navigationTitle(Text("settings.info.privacy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.close", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func policyBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }
}

private struct ContactView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: iOSThemeService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(theme.current.primary)

                        Text("문의하기")
                            .font(.system(size: 20, weight: .bold))

                        Text("궁금하신 점이 있으신가요?\n아래 방법으로 문의해 주세요.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section("연락처") {
                    Label("support@calen.app", systemImage: "envelope")
                    Label("월–금, 오전 9시–오후 6시", systemImage: "clock")
                }

                Section {
                    Button {
                        if let url = URL(string: "mailto:support@calen.app") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("이메일 보내기")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.current.primary)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("settings.info.contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.close", comment: "")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Settings v0.1.2") {
    NavigationStack {
        SettingsView()
            .environmentObject(AppState())
            .environmentObject(iOSThemeService.shared)
            .environmentObject(iOSLanguageService.shared)
    }
}
#endif
