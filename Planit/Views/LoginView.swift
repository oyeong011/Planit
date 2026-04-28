import SwiftUI

struct LoginView: View {
    @ObservedObject var authManager: GoogleAuthManager
    @State private var isLoading = false

    private let features: [(String, String)] = [
        ("calendar.badge.clock", "login.feature.menubar"),
        ("checklist", "login.feature.integration"),
        ("sparkles", "login.feature.ai"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 72, height: 72)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.blue)
                }

                Text(String(localized: "login.headline"))
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(localized: "login.subcopy"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 60)

            Spacer().frame(height: 36)

            // Feature pills
            HStack(spacing: 12) {
                ForEach(features, id: \.0) { icon, key in
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                        Text(String(localized: String.LocalizationValue(key)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.blue.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.blue.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
            }

            Spacer().frame(height: 40)

            // CTAs
            VStack(spacing: 12) {
                Button {
                    isLoading = true
                    Task {
                        await authManager.startOAuthFlow()
                        isLoading = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 16, weight: .medium))
                        }
                        Text(String(localized: "login.cta.primary"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 300)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue)
                            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                    )
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

            // 로컬 캘린더로 시작
            Button {
                UserDefaults.standard.set(true, forKey: "planit.skipGoogleAuth")
                authManager.objectWillChange.send()
            } label: {
                Text(String(localized: "login.cta.local"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
        .frame(width: 880, height: 700)
        .background(Color.platformWindowBackground)
    }
}
