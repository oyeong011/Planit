# Git Branch Strategy

## 브랜치 구조

```
main         ← 릴리즈 전용 (App Store / 배포본)
develop      ← 일상 개발 기준 브랜치 ★ 여기서 작업 시작
feature/*    ← 신기능 개발 (develop에서 분기)
fix/*        ← 버그 수정 (develop에서 분기)
hotfix/*     ← 프로덕션 긴급 패치 (main에서 분기)
release/*    ← 릴리즈 준비 (develop → main으로 머지 전)
```

## 일상 워크플로우

### 1. 새 기능 개발
```bash
git checkout develop
git pull origin develop
git checkout -b feature/your-feature-name

# ... 작업 ...

git push -u origin feature/your-feature-name
gh pr create --base develop --title "feat: ..." --body "..."
```

### 2. 버그 수정
```bash
git checkout develop
git pull origin develop
git checkout -b fix/issue-description

# ... 작업 ...

git push -u origin fix/issue-description
gh pr create --base develop --title "fix: ..."
```

### 3. 릴리즈
```bash
git checkout develop
git pull origin develop
git checkout -b release/v1.x.x

# 버전 번호 업데이트, 최종 테스트

git checkout main
git merge --no-ff release/v1.x.x
git tag -a v1.x.x -m "Release v1.x.x"
git push origin main --tags

git checkout develop
git merge --no-ff release/v1.x.x
git branch -d release/v1.x.x
git push origin develop
```

### 3-1. Sparkle 자동 업데이트 릴리스

배포 후 기존 사용자가 재설치 없이 업데이트 받을 수 있게 하는 절차.

**최초 1회 — 키 생성 (이 작업은 한 번만):**
```bash
swift build               # Sparkle 아티팩트 내려받기
.build/artifacts/sparkle/Sparkle/bin/generate_keys
# 출력된 공개키(SUPublicEDKey)를 Planit/Info.plist에 붙여넣기
# 개인키는 macOS Keychain에 자동 저장됨 — 절대 커밋·공유 금지
```

**매 릴리스:**
```bash
# 1. 서명/공증 환경변수 준비
export DEVELOPER_ID="Developer ID Application: ... (TEAM_ID)"
export NOTARIZE_TEAM_ID="..."
export NOTARIZE_APPLE_ID="..."
export NOTARIZE_PASSWORD="..."

# 2. 빌드 + EdDSA 서명 + appcast.xml 갱신
scripts/release-sparkle.sh 0.1.26 "릴리스 노트 내용"

# 3. GitHub Release 생성 + zip/dmg 업로드
gh release create v0.1.26 \
    .build/apple/Products/Release/Calen-0.1.26-universal.zip \
    .build/apple/Products/Release/Calen-0.1.26-universal.dmg \
    --title "v0.1.26" --notes "릴리스 노트"

# 4. appcast 커밋 & 푸시 → GitHub Pages 반영
git add docs/appcast.xml
git commit -m "release: v0.1.26 appcast"
git push
```

기존 사용자는 앱 실행 중 Sparkle이 백그라운드로 `docs/appcast.xml`을 확인하고 "업데이트가 있습니다" 다이얼로그를 띄운 뒤 다운로드·설치·자동 재시작까지 처리합니다.

### 4. 핫픽스 (프로덕션 긴급 패치)
```bash
git checkout main
git pull origin main
git checkout -b hotfix/critical-bug

# ... 수정 ...

git checkout main
git merge --no-ff hotfix/critical-bug
git tag -a v1.x.1 -m "Hotfix v1.x.1"
git push origin main --tags

git checkout develop
git merge --no-ff hotfix/critical-bug
git push origin develop
```

## 커밋 메시지 컨벤션

```
feat: 새 기능
fix: 버그 수정
refactor: 코드 개선 (기능 변화 없음)
style: UI/스타일 변경
docs: 문서
test: 테스트
chore: 빌드, 설정 등
```

예시:
```
feat: add drag-and-drop for todo items
fix: prevent duplicate events after Google Calendar sync
refactor: extract drag handle into reusable component
```

## 브랜치 보호 규칙

| 브랜치 | 직접 push | force push | 삭제 |
|--------|-----------|------------|------|
| `main` | ❌ PR 필요 | ❌ | ❌ |
| `develop` | ✅ 허용 | ❌ | ❌ |
| `feature/*` | ✅ 허용 | ✅ 허용 | ✅ 허용 |
| `fix/*` | ✅ 허용 | ✅ 허용 | ✅ 허용 |

## 네이밍 예시

```
feature/image-paste-support
feature/evening-review-ui
fix/duplicate-events-on-add
fix/drag-gesture-conflict
hotfix/crash-on-startup
release/v1.1.0
```
