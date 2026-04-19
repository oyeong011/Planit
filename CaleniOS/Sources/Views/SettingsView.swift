#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - SettingsView
//
// 3탭 레이아웃의 세 번째 탭("설정").
// 레퍼런스: `Calen-iOS/Calen/Features/Settings/SettingsView.swift` — section 카드 그룹 패턴.
// Planit v0.1.0 섹션 정의:
//   1. 계정       — Google 로그인 상태 + 로그인/로그아웃 Capsule 버튼
//   2. AI         — Claude API SecureField + 저장 (`ClaudeAPIKeychain.save` 실제 연결)
//   3. Hermes 메모리 — NavigationLink("기억 조회") → MemoryView + CloudKit 동기화 상태
//   4. 정보       — 버전 / 소스 코드 / 공식 사이트
struct SettingsView: View {

    // MARK: - State

    @State private var isLoggedIn: Bool = false
    @State private var userEmail: String? = nil

    /// Claude API 키 입력 필드.
    @State private var claudeAPIKey: String = ""
    /// Keychain 로드 후 상태 플래그.
    @State private var hasSavedKey: Bool = false
    /// 저장된 키의 마스킹된 preview (UI 전용; 평문 메모리 장기 보유 금지).
    @State private var savedKeyMasked: String = ""

    /// 마지막 CloudKit 동기화 시각 (SYNC 팀장 연결 전 placeholder).
    @AppStorage("calen-ios.hermes.lastSyncAt") private var lastSyncAt: Double = 0

    /// 포커스 제어 — SecureField.
    @FocusState private var apiKeyFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    section(title: "계정") { accountCard }
                    section(title: "AI") { claudeCard }
                    section(title: "Hermes 메모리") { memoryCard }
                    section(title: "정보") { infoCard }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .onAppear {
                refreshFromStorage()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text("Calen")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.calenBlue)
        }
        ToolbarItem(placement: .principal) {
            Text("설정")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.calenPrimary)
        }
    }

    // MARK: - Section container
    //
    // 타이틀(label) + 흰색 카드 그룹. 레퍼런스의 insetGrouped 리스트 룩을 카드로 재현.
    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.calenSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: CalenRadius.large, style: .continuous)
                )
                .calenCardShadow()
        }
    }

    // MARK: - 1. Account

    private var accountCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.calenBlueTint)
                        .frame(width: 44, height: 44)
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.calenBlue)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Google 계정")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.calenPrimary)

                    Text(accountStatusText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button(action: toggleLogin) {
                    Text(isLoggedIn ? "로그아웃" : "로그인")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isLoggedIn ? .red : Color.calenBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                (isLoggedIn ? Color.red : Color.calenBlue).opacity(0.10)
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var accountStatusText: String {
        if isLoggedIn {
            return userEmail ?? "연결됨"
        }
        return "연결되지 않음"
    }

    private func toggleLogin() {
        // v0.1.0 — AUTH 팀장이 실제 `iOSGoogleAuthManager.startOAuthFlow()` / `.logout()` 연결.
        // 여기서는 UI 상태 토글만 (Keychain 인증은 별도 세션).
        withAnimation(.easeInOut(duration: 0.2)) {
            isLoggedIn.toggle()
            userEmail = isLoggedIn ? nil : nil
        }
    }

    // MARK: - 2. Claude API key

    private var claudeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 상단 타이틀 + 배지
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.calenBlueTint)
                        .frame(width: 32, height: 32)
                    Image(systemName: "key.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.calenBlue)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude API 키")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.calenPrimary)
                    if hasSavedKey {
                        Text(savedKeyMasked)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("미저장")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                StatusBadge(isOn: hasSavedKey, onText: "저장됨", offText: "미저장")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Divider()
                .padding(.top, 12)

            SecureField("sk-ant-...", text: $claudeAPIKey)
                .focused($apiKeyFocused)
                .textContentType(.password)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            HStack(spacing: 12) {
                Button(action: saveKey) {
                    Text("저장")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                claudeAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.calenBlue.opacity(0.4)
                                    : Color.calenBlue
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(claudeAPIKey.trimmingCharacters(in: .whitespaces).isEmpty)

                if hasSavedKey {
                    Button(role: .destructive, action: deleteKey) {
                        Text("삭제")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color.red.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func saveKey() {
        let trimmed = claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 실제 Keychain 저장 — `ClaudeAPIKeychain`(iOS 전용).
        let ok = ClaudeAPIKeychain.save(trimmed)
        if ok {
            savedKeyMasked = Self.maskedPreview(of: trimmed)
            hasSavedKey = true
        }
        claudeAPIKey = ""
        apiKeyFocused = false
    }

    private func deleteKey() {
        _ = ClaudeAPIKeychain.remove()
        claudeAPIKey = ""
        savedKeyMasked = ""
        hasSavedKey = false
    }

    private func refreshFromStorage() {
        if let existing = ClaudeAPIKeychain.load(), !existing.isEmpty {
            hasSavedKey = true
            savedKeyMasked = Self.maskedPreview(of: existing)
        } else {
            hasSavedKey = false
            savedKeyMasked = ""
        }
    }

    private static func maskedPreview(of key: String) -> String {
        guard key.count > 11 else { return String(repeating: "•", count: max(key.count, 8)) }
        let prefix = key.prefix(7)
        let suffix = key.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    // MARK: - 3. Hermes Memory

    private var memoryCard: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: MemoryView()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.cardPersonal.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.cardPersonal)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("기억 조회")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.calenPrimary)
                        Text("Mac에서 학습된 Hermes 기억 목록")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 60)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.cardExercise.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "icloud")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.cardExercise)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CloudKit 동기화 상태")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.calenPrimary)
                    Text(lastSyncText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var lastSyncText: String {
        if lastSyncAt <= 0 { return "아직 동기화되지 않음" }
        let date = Date(timeIntervalSince1970: lastSyncAt)
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.unitsStyle = .full
        return "마지막 동기화 " + fmt.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - 4. About

    private var infoCard: some View {
        VStack(spacing: 0) {
            InfoRow(
                iconSystemName: "info.circle",
                iconTint: .secondary,
                title: "버전",
                trailing: "Calen iOS 0.1.0"
            )

            Divider().padding(.leading, 60)

            Link(destination: URL(string: "https://github.com/oyeong011/Planit")!) {
                InfoRow(
                    iconSystemName: "chevron.left.forwardslash.chevron.right",
                    iconTint: Color.calenBlue,
                    title: "소스 코드",
                    trailingSymbol: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 60)

            Link(destination: URL(string: "https://oyeong011.github.io/Planit/")!) {
                InfoRow(
                    iconSystemName: "globe",
                    iconTint: Color.cardMeal,
                    title: "공식 사이트",
                    trailingSymbol: "arrow.up.right.square"
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let isOn: Bool
    let onText: String
    let offText: String

    var body: some View {
        Text(isOn ? onText : offText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isOn ? Color.cardExercise : Color.calenSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    (isOn ? Color.cardExercise : Color.calenSecondary).opacity(0.15)
                )
            )
    }
}

// MARK: - InfoRow

private struct InfoRow: View {
    let iconSystemName: String
    let iconTint: Color
    let title: String
    var trailing: String? = nil
    var trailingSymbol: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconTint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: iconSystemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.calenPrimary)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
#endif
