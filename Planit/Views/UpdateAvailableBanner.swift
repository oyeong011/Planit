import SwiftUI

/// 팝오버 하단에 뜨는 인라인 업데이트 알림.
/// Sparkle UpdaterService가 새 버전을 감지하면 `MainCalendarView`가 이 배너를 붙인다.
/// 메뉴바 우클릭 컨텍스트 메뉴가 최근 macOS에서 불안정해 인라인 경로를 기본으로 삼는다.
struct UpdateAvailableBanner: View {
    let currentVersion: String
    let latestVersion: String
    let onInstall: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "update.banner.title",
                            defaultValue: "새 버전 v\(latestVersion) 사용 가능"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(String(localized: "update.banner.subtitle",
                            defaultValue: "현재 v\(currentVersion) · 클릭 한 번으로 설치"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button(action: onInstall) {
                Text(String(localized: "update.banner.install", defaultValue: "지금 업데이트"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "update.banner.dismiss.help",
                         defaultValue: "이 버전 알림 닫기"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}
