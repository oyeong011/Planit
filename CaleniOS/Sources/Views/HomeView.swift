#if os(iOS)
import SwiftUI

// MARK: - HomeView (deprecated — v0.1.0 3탭 구조로 폐기)
//
// 이전 Home 탭의 "오늘의 Hermes" 요약 + 빠른 액션은 `CalendarTabView`에 통합됨.
// 파일 삭제 대신 placeholder로 남겨 두어 외부 참조가 남아있어도 빌드가 깨지지
// 않도록 한다. 다음 릴리즈에서 완전 제거 예정.
@available(*, deprecated, message: "v0.1.0: 3탭 구조로 전환. CalendarTabView / TodoTabView / SettingsView 사용.")
struct HomeView: View {
    var body: some View {
        EmptyView()
    }
}
#endif
