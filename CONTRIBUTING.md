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
