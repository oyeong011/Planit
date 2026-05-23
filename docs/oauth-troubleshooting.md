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

## 코드 변경이 필요한 시나리오

위 1~4 모두 해당 없는데 여전히 실패하면 다음 점검:
- `BundledCredentials.clientID`가 실제 빌드에 embed됐는지: `nm -gU /Applications/Calen.app/Contents/MacOS/Calen | grep client`
- 정식 빌드의 codesign이 entitlements를 제대로 포함하는지: `codesign -d --entitlements - /Applications/Calen.app`
  (`com.apple.security.network.client` 필요)
