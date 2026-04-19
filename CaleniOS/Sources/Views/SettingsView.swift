#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - SettingsView
//
// 3탭 레이아웃의 세 번째 탭("설정").
// v0.1.0 P0 섹션:
//   1. 계정       — Google 로그인 (placeholder; AUTH 팀장이 iOSGoogleAuthManager 연결)
//   2. Claude API — SecureField (placeholder; AI 팀장이 ClaudeAPIKeychain 연결)
//   3. Hermes 기억 — MemoryView 네비게이션 (SYNC 팀장이 데이터 연결)
//   4. 정보       — 버전 / 공식 사이트
struct SettingsView: View {
    // MARK: Account (placeholder state)
    @State private var isLoggedIn: Bool = false

    // MARK: Claude API key (placeholder)
    // 실제 보안 저장은 AI 팀장의 `ClaudeAPIKeychain`에 위임. 여기서는 입력 필드만 노출.
    @State private var claudeAPIKey: String = ""
    // 저장된 키가 있는지 여부를 대략 표시하기 위한 마스킹된 플래그(placeholder).
    @AppStorage("calen-ios.settings.claudeAPIKey.masked") private var claudeKeyMasked: String = ""

    var body: some View {
        NavigationStack {
            List {
                accountSection
                claudeSection
                memorySection
                aboutSection
            }
            .navigationTitle("설정")
        }
    }

    // MARK: 1. 계정

    private var accountSection: some View {
        Section("계정") {
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isLoggedIn ? Color.accentColor : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google 계정")
                        .font(.body)
                    Text(isLoggedIn ? "연결됨" : "연결되지 않음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            Button {
                // TODO: AUTH 팀장이 iOSGoogleAuthManager.signIn / signOut() 연결 예정
                isLoggedIn.toggle()
            } label: {
                HStack {
                    Image(systemName: isLoggedIn ? "rectangle.portrait.and.arrow.right" : "arrow.right.circle")
                    Text(isLoggedIn ? "로그아웃" : "로그인")
                }
                .foregroundStyle(isLoggedIn ? Color.red : Color.accentColor)
            }
        }
    }

    // MARK: 2. Claude API 키

    private var claudeSection: some View {
        Section {
            SecureField("API 키 (sk-ant-...)", text: $claudeAPIKey)
                .textContentType(.password)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)

            Button {
                // TODO: AI 팀장이 ClaudeAPIKeychain.save(claudeAPIKey) 연결 예정
                let trimmed = claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                claudeKeyMasked = trimmed.isEmpty ? "" : maskedPreview(of: trimmed)
                claudeAPIKey = ""
            } label: {
                Text("저장")
            }
            .disabled(claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !claudeKeyMasked.isEmpty {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                    Text("저장된 키: \(claudeKeyMasked)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        // TODO: AI 팀장이 ClaudeAPIKeychain.delete() 연결 예정
                        claudeKeyMasked = ""
                    } label: {
                        Text("삭제").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Claude API 키")
        } footer: {
            Text("키는 기기 Keychain에 저장됩니다. 입력 후 \"저장\"을 누르세요.")
        }
    }

    // MARK: 3. Hermes 기억

    private var memorySection: some View {
        Section("Hermes 기억") {
            NavigationLink(destination: MemoryView()) {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .frame(width: 24)
                        .foregroundStyle(.purple)
                    Text("기억 조회")
                }
            }
            .accessibilityHint("Mac에서 학습된 Hermes 기억 목록 보기")
        }
    }

    // MARK: 4. 정보

    private var aboutSection: some View {
        Section("정보") {
            HStack {
                Image(systemName: "info.circle")
                    .frame(width: 24)
                Text("버전")
                Spacer()
                Text("Calen iOS 0.1.0")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://github.com/oyeong011/Planit")!) {
                HStack {
                    Image(systemName: "link")
                        .frame(width: 24)
                    Text("소스 코드")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: URL(string: "https://oyeong011.github.io/Planit/")!) {
                HStack {
                    Image(systemName: "globe")
                        .frame(width: 24)
                    Text("공식 사이트")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Helpers

    /// "sk-ant-xxxx...abcd" 형태로 앞 7자 + 말미 4자만 노출.
    private func maskedPreview(of key: String) -> String {
        guard key.count > 11 else { return String(repeating: "•", count: key.count) }
        let prefix = key.prefix(7)
        let suffix = key.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
#endif
