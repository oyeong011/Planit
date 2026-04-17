#!/bin/bash
# Planit/Calen 릴리스 전 과정을 안전하게 수행
#
# 사용법:   scripts/release.sh 0.2.3
#
# 이 스크립트가 강제하는 절차:
#   1. develop에서 origin과 동기화 확인 (ahead/behind 없음)
#   2. 작업 트리 clean 확인
#   3. Info.plist 버전 bump (CFBundleShortVersionString + CFBundleVersion 고정폭)
#   4. main 체크아웃 + pull + release 브랜치 머지 (conflict 시 Info.plist 자동 해결)
#   5. 로컬 swift build 통과 확인 (빌드 실패면 중단)
#   6. main push (실패 시 중단)
#   7. push 성공한 후에만 tag 생성/push — orphan commit에 tag 붙는 일 방지

set -euo pipefail

VERSION="${1:?사용법: $0 VERSION — 예: scripts/release.sh 0.2.3}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# 의미 있는 semver인지 검증
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ VERSION must be X.Y.Z (got: $VERSION)" >&2
    exit 1
fi

echo "=== Planit release v${VERSION} ==="

# 1. develop 동기화 + 작업 트리 clean
echo "→ Verifying develop is clean and up-to-date..."
git fetch origin develop main
CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT" != "develop" ]; then
    echo "✗ release.sh must run on develop (current: $CURRENT)" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "✗ working tree is dirty — commit or stash first" >&2
    git status --short >&2
    exit 1
fi
AHEAD=$(git rev-list origin/develop..HEAD --count)
BEHIND=$(git rev-list HEAD..origin/develop --count)
if [ "$AHEAD" -ne 0 ] || [ "$BEHIND" -ne 0 ]; then
    echo "✗ develop diverged from origin/develop (ahead=$AHEAD, behind=$BEHIND)" >&2
    exit 1
fi

# 같은 버전 태그가 이미 있으면 중단
if git rev-parse "v$VERSION" >/dev/null 2>&1 || \
   git ls-remote --tags origin | grep -q "refs/tags/v$VERSION\$"; then
    echo "✗ tag v$VERSION already exists (local or remote)" >&2
    exit 1
fi

# 2. 버전 bump — 고정폭 빌드 번호 (MM*10000 + mm*100 + pp)
read V_MAJOR V_MINOR V_PATCH < <(echo "$VERSION" | awk -F. '{printf "%d %d %d\n", $1+0, $2+0, $3+0}')
BUILD_NUMBER=$((V_MAJOR * 10000 + V_MINOR * 100 + V_PATCH))
RELEASE_BRANCH="release/v${VERSION}"

echo "→ Creating $RELEASE_BRANCH and bumping Info.plist → $VERSION / $BUILD_NUMBER"
git checkout -b "$RELEASE_BRANCH"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Planit/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Planit/Info.plist
git add Planit/Info.plist
git commit -m "chore: bump version to $VERSION"

# 3. main 체크아웃 + 병합 (Info.plist 충돌은 release 쪽 값으로 해결)
echo "→ Merging into main..."
git checkout main
git pull --ff-only
if ! git merge --no-ff "$RELEASE_BRANCH" -m "Release v${VERSION}"; then
    # Info.plist 충돌만 허용 — 다른 충돌은 수동 해결
    CONFLICTS=$(git diff --name-only --diff-filter=U)
    if [ "$CONFLICTS" = "Planit/Info.plist" ]; then
        echo "→ auto-resolving Info.plist conflict (keep release version)"
        git checkout --theirs Planit/Info.plist
        git add Planit/Info.plist
        git commit --no-edit
    else
        echo "✗ unexpected merge conflicts — resolve manually:" >&2
        echo "$CONFLICTS" >&2
        exit 1
    fi
fi

# 4. 빌드 검증 — 푸시/태깅 전에 컴파일 실패를 잡는다
echo "→ Verifying release builds locally..."
if ! swift build -c release --arch arm64 >/dev/null 2>&1; then
    echo "✗ swift build failed — abort, do not push" >&2
    exit 1
fi

# 5. main push — 성공해야만 태그 생성
echo "→ Pushing main..."
git push origin main

# 6. 태그 생성 + push (main push 성공한 뒤에만)
echo "→ Tagging v${VERSION} at $(git rev-parse --short HEAD)"
git tag -a "v${VERSION}" -m "Release v${VERSION}"
git push origin "v${VERSION}"

# 7. develop로 돌아가서 main 역머지 (Info.plist 버전 싱크)
echo "→ Syncing main back to develop..."
git checkout develop
git merge --no-ff main -m "Merge main — sync v${VERSION} version bump"
git push origin develop

# 정리
git branch -d "$RELEASE_BRANCH"

echo ""
echo "✅ Release v${VERSION} pushed. GitHub Actions will build, sign, notarize, and upload."
echo "   Run: gh run watch"
