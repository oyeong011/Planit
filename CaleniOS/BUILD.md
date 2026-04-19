# CaleniOS 빌드 가이드 (M3 RELEASE)

iOS Calen 앱(`com.oy.planit.ios`)의 로컬 .ipa 빌드 파이프라인.

## 사전 준비

1. **Xcode** 설치 (App Store) — iOS 17 SDK 포함.
2. **xcodegen** 설치:
   ```bash
   brew install xcodegen
   ```
3. **Apple Developer Team ID** 환경변수:
   ```bash
   export DEVELOPMENT_TEAM=ABCD1234EF   # 본인 Team ID (10자리)
   ```
   - Team ID 는 [Apple Developer Account](https://developer.apple.com/account) → Membership 에서 확인.
   - 자동 서명(Automatic)을 사용하므로 별도 provisioning profile 준비 불필요.

## 빌드

```bash
scripts/build-ios-app.sh 0.1.0
```

스크립트가 수행하는 단계:
1. `xcodegen generate` — `CaleniOS/CaleniOS.xcodeproj` 를 `CaleniOS/project.yml` 로부터 동적 생성.
2. `xcodebuild archive` — Release 구성으로 generic iOS 아카이브 생성.
3. `xcodebuild -exportArchive` — `scripts/ios-export-options.plist` 기반으로 development method .ipa 생성.

결과:
- Archive: `.build/ios-archive/CaleniOS-<VERSION>.xcarchive`
- IPA:     `.build/ios-ipa/CaleniOS.ipa`

## TestFlight 업로드 (수동)

현재 파이프라인은 **로컬 .ipa 생성까지만** 수행한다. TestFlight 배포는 사용자가:

1. Xcode → **Window → Organizer** 열기.
2. 방금 생성된 `xcarchive` 선택.
3. **Distribute App → App Store Connect → Upload** 클릭.
4. App Store Connect 에서 internal testers 추가 후 TestFlight 심사 진행.

## 주의사항

- 생성된 `CaleniOS.xcodeproj` 는 **.gitignore 대상**. 매번 `xcodegen generate` 로 재생성.
- Entitlements 의 `keychain-access-groups` prefix `$(AppIdentifierPrefix)` 는 Xcode 자동 서명이 채운다 — 수동 수정 불필요.
- macOS 앱 빌드 (`scripts/build-app.sh`) 와는 완전히 독립. 서로 영향 없음.
- Google OAuth 연동을 위해서는 `CaleniOS/Sources/Info.plist` 의 `CFBundleURLSchemes` placeholder (`REPLACE_WITH_REVERSED_CLIENT_ID`) 를 실제 reversed-client-ID 로 교체해야 한다.
