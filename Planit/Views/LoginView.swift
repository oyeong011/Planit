import SwiftUI

struct LoginView: View {
    @ObservedObject var authManager: GoogleAuthManager
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Calen")
                    .font(.system(size: 28, weight: .bold))

                Text(String(localized: "login.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 48)

            // 번들에 자격증명이 항상 포함되어 있으므로 Google 로그인 버튼만 표시
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
                        Text(String(localized: "login.google.signin"))
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
            }

            Spacer()

            Button {
                UserDefaults.standard.set(true, forKey: "planit.skipGoogleAuth")
                authManager.objectWillChange.send()
            } label: {
                Text(String(localized: "login.skip.google"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(width: 880, height: 700)
        .background(Color.platformWindowBackground)
    }
}
