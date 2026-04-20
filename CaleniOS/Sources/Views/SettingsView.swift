#if os(iOS)
import SwiftUI
import UIKit

// MARK: - SettingsView
//
// 레퍼런스 `Calen-iOS/Calen/Features/Settings/SettingsView.swift` 포팅 (M2 UI v3).
// 적응 포인트(v0.1.0):
//  1. `UserProfile` 의존 제거 — Planit iOS v0.1.0 범위 밖. 표시 이름은 Google 계정
//     이메일(userEmail)로 대체하거나 "사용자"로 고정.
//  2. Google 로그인 UI → `iOSGoogleAuthManager`의 `startOAuthFlow()` / `logout()` 연결.
//  3. `ClaudeAPIKeychain` 기반 API 키 SecureField 섹션 **추가** — v0.1.0 핵심 기능.
//  4. `AIModelInfoView`는 레퍼런스 원문 유지(참고용 정적 문서). 모델명은 "Claude 3.5 Sonnet"로
//     표기 변경 (Planit은 Claude 사용).

struct SettingsView: View {

    @EnvironmentObject private var appState: AppState

    // Phase B M4-2: HomeViewModel과 동일 auth 인스턴스를 공유 → 로그인/로그아웃 상태 변화가
    // 세션 내에서 즉시 홈 탭에 반영된다. Shared singleton은 이미 MainActor에서 생성된 ObservableObject.
    @ObservedObject private var googleAuth = iOSGoogleAuthManager.shared

    // MARK: App Settings

    @AppStorage("notificationsEnabled")  private var notificationsEnabled: Bool = true
    @AppStorage("calendarSyncEnabled")   private var calendarSyncEnabled: Bool = false
    @AppStorage("preferredLanguage")     private var preferredLanguage: String = "ko"
    // v0.1 iCloud Hermes 메모리 sync — macOS MainView의 HermesMemorySync.startIfEnabled 도 같은 key 감시.
    // 이 토글이 UserDefaults.standard 에 저장되므로 같은 기기의 macOS 앱이 값 확인 가능.
    @AppStorage("planit.hermesCloudKitSyncEnabled") private var hermesCloudKitSyncEnabled: Bool = false

    // MARK: Auth sheets

    @State private var showGoogleClientIDSheet = false
    @State private var showClaudeAPIKeySheet = false

    // MARK: Alert state

    @State private var showResetAlert = false
    @State private var showPrivacySheet = false
    @State private var showContactSheet = false

    // MARK: Claude API key 상태
    //
    // v0.1.1: `ClaudeAPIKeychain.load()`는 I/O이므로 매 뷰 재평가마다 호출되면 성능/배터리 손해.
    // @State로 캐시해두고 시트 dismiss / 데이터 초기화 시 명시적으로 갱신한다.
    @State private var hasClaudeAPIKey: Bool = ClaudeAPIKeychain.load() != nil

    // MARK: Derived

    /// v0.1.0에서는 `UserProfile`이 없으므로 Google 이메일 또는 "사용자"로 표시.
    private var displayName: String {
        if let email = googleAuth.userEmail, !email.isEmpty { return email }
        return "사용자"
    }

    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    var body: some View {
        NavigationStack {
            List {
                profileSection
                accountSection
                aiSection
                appSettingsSection
                infoSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showGoogleClientIDSheet) {
            GoogleClientIDSheet { newID in
                googleAuth.setupCredentials(clientID: newID)
            }
        }
        .sheet(isPresented: $showClaudeAPIKeySheet, onDismiss: {
            // 시트 닫힐 때 Keychain 상태 재조회 → "설정됨/필요" 뱃지 동기화.
            hasClaudeAPIKey = ClaudeAPIKeychain.load() != nil
        }) {
            ClaudeAPIKeySheet()
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showContactSheet) {
            ContactView()
        }
        .alert("데이터 초기화", isPresented: $showResetAlert) {
            Button("초기화", role: .destructive) {
                googleAuth.logout()
                ClaudeAPIKeychain.remove()
                hasClaudeAPIKey = false
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("Google 로그인과 Claude API 키가 삭제됩니다.\n이 작업은 되돌릴 수 없습니다.")
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.calenBlue.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Text(displayName.prefix(1).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.calenBlue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)

                    Text(googleAuth.isAuthenticated ? "Google 계정 연결됨" : "Calen 사용자")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                }

                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Account Section (Google 로그인)

    private var accountSection: some View {
        Section("Google 계정") {
            // Client ID 설정
            Button {
                showGoogleClientIDSheet = true
            } label: {
                Label {
                    HStack {
                        Text("OAuth 클라이언트 ID")
                            .foregroundStyle(Color(.label))
                        Spacer()
                        Text(googleAuth.hasCredentials ? "설정됨" : "필요")
                            .font(.system(size: 13))
                            .foregroundStyle(googleAuth.hasCredentials ? Color(.secondaryLabel) : Color.orange)
                    }
                } icon: {
                    SettingsIconView(
                        systemName: "key.fill",
                        color: Color(red: 0.23, green: 0.51, blue: 0.96)
                    )
                }
            }

            // Sign in / out
            if googleAuth.isAuthenticated {
                Button(role: .destructive) {
                    googleAuth.logout()
                } label: {
                    Label {
                        Text("로그아웃")
                    } icon: {
                        SettingsIconView(
                            systemName: "rectangle.portrait.and.arrow.right",
                            color: Color(red: 0.96, green: 0.27, blue: 0.27)
                        )
                    }
                }
            } else {
                Button {
                    Task { await googleAuth.startOAuthFlow() }
                } label: {
                    Label {
                        Text("Google로 로그인")
                            .foregroundStyle(Color(.label))
                    } icon: {
                        SettingsIconView(
                            systemName: "person.crop.circle.badge.checkmark",
                            color: Color(red: 0.25, green: 0.78, blue: 0.52)
                        )
                    }
                }
                .disabled(!googleAuth.hasCredentials)
            }

            // 오류 메시지
            if let err = googleAuth.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - AI Section (Claude API)

    private var aiSection: some View {
        Section("AI 설정") {
            // Claude API key
            Button {
                showClaudeAPIKeySheet = true
            } label: {
                Label {
                    HStack {
                        Text("Claude API 키")
                            .foregroundStyle(Color(.label))
                        Spacer()
                        Text(hasClaudeAPIKey ? "저장됨" : "미저장")
                            .font(.system(size: 13))
                            .foregroundStyle(hasClaudeAPIKey ? Color(.secondaryLabel) : Color.orange)
                    }
                } icon: {
                    SettingsIconView(
                        systemName: "lock.shield.fill",
                        color: Color(red: 0.60, green: 0.36, blue: 0.91)
                    )
                }
            }

            // AI model info
            NavigationLink {
                AIModelInfoView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 모델 정보")
                        Text("Claude Opus 4.7")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                } icon: {
                    SettingsIconView(
                        systemName: "cpu",
                        color: Color(red: 0.60, green: 0.36, blue: 0.91)
                    )
                }
            }

            // Data reset
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label {
                    Text("데이터 초기화")
                } icon: {
                    SettingsIconView(
                        systemName: "trash.fill",
                        color: Color(red: 0.96, green: 0.27, blue: 0.27)
                    )
                }
            }
        }
    }

    // MARK: - App Settings Section

    private var appSettingsSection: some View {
        Section("앱 설정") {
            // Notifications toggle
            Toggle(isOn: $notificationsEnabled) {
                Label {
                    Text("알림 설정")
                } icon: {
                    SettingsIconView(systemName: "bell.fill", color: Color(red: 1.0, green: 0.58, blue: 0.0))
                }
            }
            .tint(Color.calenBlue)

            // Calendar sync toggle
            Toggle(isOn: $calendarSyncEnabled) {
                Label {
                    Text("캘린더 동기화")
                } icon: {
                    SettingsIconView(systemName: "calendar", color: Color(red: 0.96, green: 0.32, blue: 0.32))
                }
            }
            .tint(Color.calenBlue)

            // v0.1 iCloud Hermes memory sync (macOS writes → iOS reads)
            Toggle(isOn: $hermesCloudKitSyncEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud 동기화 (Hermes 기억)")
                        Text("Mac에서 학습된 AI 기억을 iPhone에서 조회")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIconView(systemName: "icloud.fill", color: Color(red: 0.23, green: 0.60, blue: 0.96))
                }
            }
            .tint(Color.calenBlue)

            // Language picker
            Picker(selection: $preferredLanguage) {
                Text("한국어").tag("ko")
                Text("English").tag("en")
            } label: {
                Label {
                    Text("언어")
                } icon: {
                    SettingsIconView(systemName: "globe", color: Color(red: 0.23, green: 0.51, blue: 0.96))
                }
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section("정보") {
            // Version
            HStack {
                Label {
                    Text("버전")
                } icon: {
                    SettingsIconView(systemName: "info.circle.fill", color: Color(.systemGray))
                }
                Spacer()
                Text(appVersion)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.secondaryLabel))
            }

            // Privacy policy
            Button {
                showPrivacySheet = true
            } label: {
                Label {
                    Text("개인정보처리방침")
                        .foregroundStyle(Color(.label))
                } icon: {
                    SettingsIconView(systemName: "hand.raised.fill", color: Color(red: 0.25, green: 0.78, blue: 0.52))
                }
            }

            // Contact
            Button {
                showContactSheet = true
            } label: {
                Label {
                    Text("문의하기")
                        .foregroundStyle(Color(.label))
                } icon: {
                    SettingsIconView(systemName: "envelope.fill", color: Color(red: 0.23, green: 0.51, blue: 0.96))
                }
            }
        }
    }
}

// MARK: - Settings Icon View

/// Rounded-rectangle icon cell, consistent with native iOS Settings style.
struct SettingsIconView: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 30, height: 30)

            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Google Client ID Sheet (Planit 적응)

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
                    Text("OAuth 클라이언트 ID")
                } footer: {
                    Text("Google Cloud Console에서 iOS 앱 OAuth 2.0 클라이언트 ID를 발급받아 입력하세요.\n`*.apps.googleusercontent.com` 형식이어야 합니다.")
                }
            }
            .navigationTitle("Google 클라이언트 ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
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

// MARK: - Claude API Key Sheet (Planit 적응)

private struct ClaudeAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var showSuccess = false
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
                    Text("API 키")
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
                                Text("저장된 키 삭제")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Claude API 키")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
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
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 0.60, green: 0.36, blue: 0.91).opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "cpu")
                                .font(.system(size: 26))
                                .foregroundStyle(Color(red: 0.60, green: 0.36, blue: 0.91))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Claude Opus 4.7")
                                .font(.system(size: 18, weight: .bold))
                            Text("Anthropic · 최신 버전")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.secondaryLabel))
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
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI 모델 정보")
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
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Privacy Policy View

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
            .navigationTitle("개인정보처리방침")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
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
                .foregroundStyle(Color(.secondaryLabel))
                .lineSpacing(4)
        }
    }
}

// MARK: - Contact View

private struct ContactView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.calenBlue)

                        Text("문의하기")
                            .font(.system(size: 20, weight: .bold))

                        Text("궁금하신 점이 있으신가요?\n아래 방법으로 문의해 주세요.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(.secondaryLabel))
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
                                .foregroundStyle(Color.calenBlue)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("문의하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environmentObject(AppState())
}
#endif
