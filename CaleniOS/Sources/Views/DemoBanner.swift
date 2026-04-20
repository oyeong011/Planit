#if os(iOS)
import SwiftUI

// MARK: - DemoBanner
//
// v6 주 시트에서 사용되는 "데모 데이터" 고지 배너.
// FakeEventRepository 주입 상태에서 사용자가 실 Google Calendar 데이터로 착각하는 것을 방지.
//
// - 높이 32pt, horizontal 16pt / vertical 6pt padding
// - 배경 calenBlue 12% opacity + foreground calenBlue primary
// - 시트 상단 주 네비게이션 아래, 요일 헤더 위에 배치
// - Phase B에서 실 repository 주입 시 `showsDemoBanner = false`로 감춤

struct DemoBanner: View {

    /// 본문 문구. 기본은 한국어 고지.
    var message: String = "데모 데이터 — Google Calendar 연동 준비 중"

    /// UX Critic fix: 사용자가 한 번 숨기면 같은 세션 내 재표시 금지.
    /// UserDefaults로 영속화 — 로그인 상태에서 repo.isFakeRepo=false 가 되면 자연히 숨김.
    @AppStorage("calen-ios.demo-banner-dismissed") private var dismissed: Bool = false

    var body: some View {
        if dismissed {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.calenBlue)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.calenBlue)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.calenBlue.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("배너 닫기")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(Color.calenBlue.opacity(0.12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("데모 데이터 배너. Google Calendar 연동이 준비 중입니다.")
        }
    }
}

// MARK: - Preview

#Preview("DemoBanner") {
    VStack(spacing: 0) {
        DemoBanner()
        Spacer()
    }
    .background(Color.calenCream)
}
#endif
