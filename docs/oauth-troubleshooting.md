# Google OAuth "취소" 문제 진단 가이드

배포 .app(서명/공증된 정식 빌드)에서 Google 로그인 버튼을 눌렀을 때 동의 화면이 뜨자마자
"취소"되어 돌아오는 경우의 점검 항목.

## 가장 흔한 원인 (확인 순서대로)

### 1. Google OAuth 동의 화면이 "테스트" 상태
- Google Cloud Console → `APIs & Services` → `OAuth consent screen`
- **Publishing status**가 **Testing**이면 등록된 테스트 사용자(`Test users`)만 로그인 가능.
- 그 외 사용자가 시도하면 "확인되지 않은 앱" 또는 "Google에서 이 앱을 차단했습니다" 화면이
  뜨고, 사용자가 닫으면 loopback server는 `code` 없이 stream만 받아 `noCodeReceived`로 실패한다.
- **해결**: Publishing status를 **In production**으로 게시. (앱 검증이 필요할 수 있음.)

### 2. OAuth client type이 Desktop이 아님
- 같은 Console → `Credentials` → 사용 중인 OAuth 2.0 Client ID 확인
- **Application type**이 반드시 **Desktop app**이어야 한다.
- Web client로 만들었으면 `http://127.0.0.1:<random>` redirect_uri를 사전 등록할 수 없어서
  `redirect_uri_mismatch` 400 에러로 실패한다. (현재 코드는 loopback 동적 포트 사용)

### 3. Bundled credentials 누락
- `Planit/Services/BundledCredentials.local.swift` 파일이 있어야 정식 빌드에 client_id/secret가
  들어간다 (`Package.swift`가 파일 존재 시 `HAS_BUNDLED_CREDENTIALS` 플래그 자동 활성화).
- CI/CD 빌드라면 GitHub Secret으로 이 파일이 자동 생성되는지 확인.
- 누락 시 앱은 "자격증명이 없습니다" 에러 표시.

### 4. 90초 타임아웃 만료
- `Planit/Services/GoogleAuthManager.swift:301` — 사용자가 90초 안에 동의 안 하면 loopback
  server가 자동 close. 사용자에게는 "취소"처럼 보임.
- 사용자가 다른 Google 계정으로 로그인 중이거나, 2FA 절차에 시간이 걸리면 만료 가능.

## 디버깅 명령

```bash
# 정식 빌드 실행 후 Console.app에서 Calen 프로세스 로그 확인
log stream --predicate 'process == "Calen"' --info --debug

# 또는 직접 실행해서 stderr 확인
/Applications/Calen.app/Contents/MacOS/Calen
```

`exchangeCodeForTokens` 단계에서 발생하는 에러는 `AuthError.tokenExchangeFailed`로 매핑되며,
`redirect_uri_mismatch` 또는 `400` 포함 시 사용자에게 한국어 안내 메시지가 표시된다
(`auth.error.redirect.mismatch` 키).

## 코드 수정 후에도 재로그인이 필요한 경우

Google Calendar 연동은 앱이 refresh 실패를 더 정확히 분류하더라도 Google 쪽 정책이나 사용자
조치 때문에 다시 로그인이 필요할 수 있다. Google 공식 문서는 refresh token이 다음과 같은
이유로 더 이상 동작하지 않을 수 있다고 설명한다:

- 사용자가 Google 계정에서 앱 접근 권한을 revoked 처리한 경우.
- token이 장기간 사용되지 않았거나, 계정/관리자 정책/발급 한도/시간 제한 접근 정책의 영향을 받은 경우.
- OAuth consent screen이 external 앱의 **Testing** 상태인 경우. 이 상태에서 발급된 refresh token은
  요청 scope가 기본 프로필 scope만인 예외를 제외하면 **7-day** 만료가 적용될 수 있다.

운영 판단 기준:

- `permanentRevocation`으로 분류된 진짜 만료/철회(`invalid_grant` 등)는 앱이 복구할 수 없으므로
  사용자가 다시 Google 로그인을 해야 한다.
- retryable 또는 configuration-degraded 오류는 즉시 재로그인으로 몰지 말고 네트워크, Google 응답,
  OAuth client 설정, consent screen 상태를 재시도/조사한다.
- 버그 리포트에는 Console 로그의 에러 종류와 상태만 공유한다. 토큰, client credential, HTTP
  Authorization 헤더, Keychain 값은 붙여 넣지 않는다.
- 앱은 Google의 Testing-mode 7-day 만료, 사용자 revoked 처리, Google 계정/관리자 정책에 따른
  refresh token 만료를 방지할 수 없다.

공식 문서:

- https://developers.google.com/identity/protocols/oauth2
- https://developers.google.com/identity/protocols/oauth2/resources/best-practices
- https://developers.google.com/google-ads/api/docs/get-started/common-errors

## 코드 변경이 필요한 시나리오

위 1~4 모두 해당 없는데 여전히 실패하면 다음 점검:
- `BundledCredentials.clientID`가 실제 빌드에 embed됐는지: `nm -gU /Applications/Calen.app/Contents/MacOS/Calen | grep client`
- 정식 빌드의 codesign이 entitlements를 제대로 포함하는지: `codesign -d --entitlements - /Applications/Calen.app`
  (`com.apple.security.network.client` 필요)
