#if os(iOS)
import Foundation

// MARK: - iOSGoogleAuthManager.shared
//
// Phase B M4-2: HomeViewModel / GoogleCalendarRepository / SettingsView가 동일한 auth
// 인스턴스를 공유해야 로그인/로그아웃 상태 변화를 일관되게 감지할 수 있다.
//
// `iOSGoogleAuthManager.swift` 본체는 수정 금지 제약이 있어 여기 extension으로
// process-wide singleton을 제공한다. `@StateObject var googleAuth = iOSGoogleAuthManager()`
// 패턴을 쓰는 기존 호출부도 계속 동작 — 이 singleton은 **opt-in** 이다.

extension iOSGoogleAuthManager {
    /// 앱 전역에서 공유되는 기본 인스턴스. SettingsView 등에서 이걸 사용하면
    /// HomeViewModel의 auth state 구독과 동일 인스턴스를 바라본다.
    @MainActor
    public static let shared: iOSGoogleAuthManager = iOSGoogleAuthManager()
}
#endif
