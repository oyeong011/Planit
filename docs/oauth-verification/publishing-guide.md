# Google OAuth — In Production 전환 + 검증 제출 가이드

## 현재 상태 → 목표 상태

| 항목 | 현재 | 목표 |
|---|---|---|
| Publishing status | Testing | **In production** |
| Verification | Unverified | Verified (3~6주 후) |
| 사용자 수 제한 | 100 (testers only) | 무제한 |
| 경고 화면 | 테스터는 안 보임 | 처음엔 있음 → 검증 후 제거 |

## Step 1. 전환 전 준비 (완료됨 ✅)

- [x] Privacy Policy: https://oyeong011.github.io/Planit/privacy.html
- [x] Terms of Service: https://oyeong011.github.io/Planit/terms.html
- [x] Homepage: https://github.com/oyeong011/Planit
- [x] Support email: beetleboy_@naver.com
- [x] Scope justification 문서 (`docs/oauth-verification/scope-justification.md`)
- [ ] 도메인 소유 증명 (Google Search Console)
- [ ] 앱 로고 120x120 PNG

## Step 2. In Production 전환 (5분)

https://console.cloud.google.com/apis/credentials/consent 접속 후:

1. **OAuth consent screen** 탭
2. 상단의 **"Publish app"** 버튼 클릭
3. "Will be pushed to production" 경고 확인 → **"Confirm"**
4. Publishing status가 **"In production"** 으로 변경됨

⚠️ **변경 즉시 효과**:
- 누구나 `brew install --cask calen-ai` → Google 로그인 가능
- 하지만 로그인 시 **"Google hasn't verified this app"** 경고가 표시됨
- 사용자는 "Advanced" → "Go to Calen (unsafe)" 로 우회 가능

## Step 3. 검증 제출 (Step 2 이후 곧바로)

### 3-1. OAuth consent screen 정보 채우기

같은 페이지에서 "Edit App" → 모든 필드 작성:
- **App name**: Calen
- **User support email**: beetleboy_@naver.com
- **App logo**: 120x120 PNG 업로드 (준비 필요)
- **App domain** 섹션:
  - **Application home page**: https://github.com/oyeong011/Planit
  - **Application privacy policy link**: https://oyeong011.github.io/Planit/privacy.html
  - **Application terms of service link**: https://oyeong011.github.io/Planit/terms.html
- **Authorized domains**:
  - `oyeong011.github.io`
  - `github.com`
- **Developer contact**: beetleboy_@naver.com
- **Scopes**: 3개 모두 추가 (justification 아래 참조)

### 3-2. 도메인 소유 증명

`oyeong011.github.io` 를 Google Search Console에 등록:
1. https://search.google.com/search-console 접속
2. "URL prefix" 속성 추가 → `https://oyeong011.github.io/Planit/`
3. 소유권 확인 파일(`googleXXXXXXXX.html`)을 `docs/` 디렉터리에 업로드
4. 이미 `docs/googled122f53a03ac8dbf.html` 존재 — 해당 코드로 인증됨

### 3-3. Scope justification 제출

OAuth consent screen → "Scopes" 탭:
- 각 scope 항목에 `docs/oauth-verification/scope-justification.md` 내용 붙여넣기
- "Justification for the scope" 필드에 요약 300자 이내

### 3-4. 데모 영상

준비되지 않은 유일한 항목. 아래 세그먼트 2~3분 영상:
1. 앱 설치 (brew install)
2. 메뉴바 아이콘 → Google 로그인 버튼
3. OAuth 동의 화면 (3개 scope 표시)
4. 로그인 후 캘린더 뷰
5. 이벤트 생성/수정/삭제 시연
6. 설정 → 로그아웃 → 토큰 제거

화면 녹화 후 YouTube unlisted 업로드 → URL 제출.

### 3-5. 제출

모든 정보 채운 뒤 "Submit for verification" 클릭.
Google 응답: 1~3주 내 이메일 피드백. 추가 정보 요청 올 수 있음.

## Step 4. 사용자 안내 (검증 완료 전까지)

README에 다음 섹션 추가:

> ### 로그인 시 "앱이 확인되지 않았습니다" 경고가 뜨는 경우
> Calen은 Google OAuth 검증 대기 중입니다 (1~6주 예상). 그 동안:
> 1. 경고 화면에서 **"고급"** 클릭
> 2. **"Calen(으)로 이동(안전하지 않음)"** 클릭
> 3. 정상 동의 진행
>
> 이는 일시적 제약이며, 앱 자체는 서명+공증된 정상 빌드입니다.

## 체크리스트

- [ ] Publishing status: Testing → In production 전환
- [ ] OAuth consent screen 모든 필드 작성
- [ ] 앱 로고 120x120 PNG 업로드
- [ ] Search Console 도메인 증명 확인
- [ ] Scope justification 붙여넣기
- [ ] 데모 영상 녹화 + YouTube 업로드
- [ ] "Submit for verification" 클릭
- [ ] README에 경고 안내 추가
