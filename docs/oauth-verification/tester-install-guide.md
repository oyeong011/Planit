# Calen OAuth 검증 영상 촬영 가이드

이 문서는 **영상 촬영을 대신해 주시는 분**에게 공유하는 설치/조작 가이드입니다.

촬영 시간: **2~3분**
파일 형식: mp4 (QuickTime 기본 출력 그대로 OK)
해상도: Retina 네이티브 그대로 (1440p 이상 권장)

---

## 1. 준비 (촬영 시작 전)

### A. 기존 Calen 제거 (설치되어 있다면)
```bash
brew uninstall --cask calen-ai
rm -rf ~/Library/Application\ Support/Planit
rm -rf ~/Library/Caches/com.oy.planit
```

### B. 화면 정리
- 메뉴바에서 macOS 기본 "Calendar.app"은 **종료**해 주세요 (달력 아이콘이 둘 겹치면 안 됩니다)
- 바탕화면을 깨끗하게 (개인 파일/알림 배너 없게)
- 브라우저 탭 정리 (촬영 중 새 창 뜰 때 민감 정보 보이지 않게)

### C. Google 계정
- **테스트용 Google 계정**으로 로그인해 주세요 (개인 메일 말고)
- 해당 계정의 Google Calendar에 이벤트 **2~3개** 미리 만들어 두세요 (시연용)

### D. 화면 녹화 세팅
1. `QuickTime Player` 실행
2. 메뉴 → **File → New Screen Recording**
3. 🎤 마이크 켜기 (내레이션 영어 또는 한국어)
4. "전체 화면 녹화" 선택
5. 녹화 시작

---

## 2. 촬영 순서 (2~3분)

각 단계 아래에 **화면에서 해야 할 것**과 **내레이션 예시**를 적어 두었습니다.

### Step 1 — GitHub 홈 (0:00 ~ 0:10)
**화면:** 브라우저에서 `https://github.com/oyeong011/Planit` 열기
**내레이션:**
> "Calen is an open-source macOS menu bar calendar app."

---

### Step 2 — 설치 (0:10 ~ 0:25)
**화면:** 터미널에서 아래 명령 입력 → 설치 완료 로그 보이기
```bash
brew install --cask oyeong011/calen/calen-ai
```
**내레이션:**
> "Install via Homebrew tap."

---

### Step 3 — 앱 실행 (0:25 ~ 0:35)
**화면:** 메뉴바 상단의 달력 아이콘 **클릭** → 팝오버 뜨는 모습
**내레이션:**
> "Click the menu bar icon to open the popover."

---

### Step 4 — ⚠️ 가장 중요: Google 로그인 + 동의 화면 (0:35 ~ 0:55)
**화면:**
1. 팝오버에서 **"Google로 로그인"** 버튼 클릭
2. 브라우저가 열리며 Google 동의 화면이 나옵니다
3. **동의 화면에서 3초 이상 멈춰 주세요** (3개의 권한이 또렷이 보이게)
    - `Calendar list 읽기`
    - `Calendar 이벤트 읽기/쓰기`
    - `이메일 주소 확인`
4. "허용" 클릭 → 앱으로 돌아오기

**내레이션:**
> "On sign-in, the user explicitly consents to three scopes: read calendar list, read and edit events, and read email."

🚨 **이 장면이 영상에서 가장 중요합니다. 동의 화면의 권한 리스트가 반드시 읽을 수 있게 잡혀야 해요.**

---

### Step 5 — 캘린더 이벤트 표시 (0:55 ~ 1:10)
**화면:** 로그인 후 팝오버가 캘린더로 전환되며 **기존 Google Calendar 이벤트들이 표시**됨
**내레이션:**
> "Events are displayed from Google Calendar."

---

### Step 6 — 이벤트 생성 (1:10 ~ 1:30)
**화면:**
1. 팝오버 왼쪽 채팅 탭 클릭
2. 입력창에 **"내일 3시 회의 추가"** 입력 후 전송
3. AI가 생성 제안을 카드로 표시 → **"실행"** 클릭
4. 우측 캘린더에 새 이벤트가 나타나는 것 확인

**내레이션:**
> "Users can create new events. The app uses the calendar.events scope for this write operation."

---

### Step 7 — 이벤트 수정 (1:30 ~ 1:50)
**화면:**
1. 방금 만든 이벤트 클릭 → 상세 화면
2. 제목 또는 시간 바꾸고 **저장**
3. 캘린더에서 바뀐 정보 확인

**내레이션:**
> "Existing events can be updated. Each destructive action requires explicit user confirmation."

---

### Step 8 — 이벤트 삭제 (1:50 ~ 2:10)
**화면:**
1. 이벤트 우클릭 → **삭제**
2. **삭제 확인 모달**이 뜨면 화면에 2~3초 멈추기
3. "삭제" 클릭 → 이벤트 사라짐 확인

**내레이션:**
> "Delete requires explicit confirmation before proceeding."

---

### Step 9 — 로그아웃 (2:10 ~ 2:25)
**화면:**
1. 팝오버 우측 하단 **⚙️ 설정** 버튼
2. 사이드바 **"연동"** 섹션
3. **"Google 로그아웃"** 클릭
4. 로그인 화면으로 돌아가는 것 확인

**내레이션:**
> "On sign-out, OAuth tokens are removed from the macOS Keychain."

---

### Step 10 — 마무리 (2:25 ~ 2:40)
**화면:** GitHub URL `github.com/oyeong011/Planit` 브라우저에 다시 표시
**내레이션:**
> "Source at github.com/oyeong011/Planit. MIT licensed."

---

## 3. 촬영 끝난 후

1. QuickTime에서 녹화 정지 → `cmd + S` 로 `Calen-OAuth-Demo.mov` 저장
2. 파일을 **의뢰인(oyeong011)에게 전달**해 주세요
3. 의뢰인이 YouTube(Unlisted)에 업로드 후 Google 검증 팀에 제출합니다

---

## 주의사항 (보안)

- 🔒 **본인의 개인 계정 로그인 금지** — 테스트용 Google 계정만 사용
- 🔒 화면에 본인의 **이메일, 연락처, 주민번호** 등 민감 정보가 비치지 않게 주의
- 🔒 Slack / 카카오톡 / iMessage 알림 끄고 촬영
- 🔒 영상은 **의뢰인에게만** 전달. 본인이 직접 YouTube에 올리지 마세요

---

## 문제 해결

### "Developer cannot be verified" 경고가 뜨면
첫 실행에 한해 나타나며, 검증 팀에게는 자연스러운 현상입니다. 그대로 촬영 진행하세요:
```
시스템 설정 → 개인정보 보호 및 보안 → 하단 "그래도 열기"
```

### 설치가 멈추면
```bash
brew update
brew install --cask oyeong011/calen/calen-ai --force
```

### 메뉴바 아이콘이 안 보이면
- Bartender 같은 메뉴바 정리 앱이 숨겼을 수 있음 → 잠시 꺼 주세요
- 그래도 안 보이면 재실행: `open -a Calen`

---

## 궁금한 점

의뢰인(oyeong011@gmail.com)에게 바로 연락해 주세요. 촬영 도중 막히는 부분이 있으면 **녹화 중단 → 질문 → 재시작**이 가장 안전합니다.

감사합니다 🙏
