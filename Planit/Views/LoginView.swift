import SwiftUI

struct LoginView: View {
    @ObservedObject var authManager: GoogleAuthManager
    @State private var isLoading = false
    @State private var showSetup = false
    @State private var inputClientID = ""
    @State private var inputClientSecret = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Calen")
                    .font(.system(size: 28, weight: .bold))

                Text("Google 캘린더와 연동하여\n일정을 관리하세요")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 48)

            if !authManager.hasCredentials || showSetup {
                // First-time setup: need credentials
                VStack(alignment: .leading, spacing: 12) {
                    Text("Google API 설정")
                        .font(.system(size: 14, weight: .bold))

                    Text("Google Cloud Console에서 OAuth 클라이언트를 생성하고 입력하세요.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Google Cloud Console")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    TextField("Client ID", text: $inputClientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    SecureField("Client Secret", text: $inputClientSecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button {
                        authManager.setupCredentials(
                            clientID: inputClientID.trimmingCharacters(in: .whitespaces),
                            clientSecret: inputClientSecret.trimmingCharacters(in: .whitespaces)
                        )
                        showSetup = false
                    } label: {
                        Text("저장")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(
                                inputClientID.isEmpty || inputClientSecret.isEmpty ? Color.gray : Color.blue
                            ))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputClientID.isEmpty || inputClientSecret.isEmpty)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .padding(.horizontal, 60)
            } else {
                // Credentials exist → show login button
                VStack(spacing: 16) {
                    Button {
                        isLoading = true
                        Task {
                            await authManager.startOAuthFlow()
                            isLoading = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 18))
                            }
                            Text("Google 계정으로 로그인")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 280)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 40)
                    }

                    Button { showSetup = true } label: {
                        Text("자격증명 변경")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button {
                UserDefaults.standard.set(true, forKey: "planit.skipGoogleAuth")
                authManager.objectWillChange.send()
            } label: {
                Text("Google 없이 시작 (로컬 캘린더 사용)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(width: 880, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
