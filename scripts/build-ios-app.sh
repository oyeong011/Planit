#!/bin/bash
# iOS Calen .ipa 로컬 빌드 파이프라인 (RELEASE 팀장, M3).
#
# 전제:
#   - macOS + Xcode 설치 (xcodebuild 사용 가능)
#   - xcodegen 설치: `brew install xcodegen`
#   - DEVELOPMENT_TEAM 환경변수: Apple Developer Team ID (10자리)
#
# 사용법:
#   export DEVELOPMENT_TEAM=ABCD1234EF
#   scripts/build-ios-app.sh 0.1.0
#
# 결과:
#   .build/ios-archive/CaleniOS-<VERSION>.xcarchive
#   .build/ios-ipa/CaleniOS.ipa
#
# TestFlight 업로드:
#   Xcode Organizer 로 수동 진행 (본 스크립트 범위 밖).

set -euo pipefail

VERSION="${1:-0.1.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$PROJECT_DIR/CaleniOS"
ARCHIVE_DIR="$PROJECT_DIR/.build/ios-archive"
IPA_DIR="$PROJECT_DIR/.build/ios-ipa"
ARCHIVE_PATH="$ARCHIVE_DIR/CaleniOS-${VERSION}.xcarchive"
EXPORT_OPTIONS="$PROJECT_DIR/scripts/ios-export-options.plist"
EXPORT_OPTIONS_RESOLVED="$PROJECT_DIR/.build/ios-ipa/export-options-resolved.plist"

# VERSION=X.Y.Z 검증
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ VERSION must be X.Y.Z (got: $VERSION)" >&2
    exit 1
fi

echo "=== Building CaleniOS v${VERSION} (.ipa) ==="

# 1. xcodegen 체크
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "✗ xcodegen 을 찾을 수 없습니다." >&2
    echo "   설치:  brew install xcodegen" >&2
    exit 1
fi

# 2. DEVELOPMENT_TEAM 체크
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    echo "⚠️  DEVELOPMENT_TEAM 환경변수가 설정되지 않았습니다." >&2
    echo "   Apple Developer Team ID 를 설정해야 서명/아카이브가 성공합니다." >&2
    echo "   예:  export DEVELOPMENT_TEAM=ABCD1234EF" >&2
    echo "" >&2
    echo "   계속 진행하지만 xcodebuild 단계에서 실패할 가능성이 큽니다." >&2
fi

# 3. xcodegen 으로 .xcodeproj 생성 (idempotent)
echo "→ Generating CaleniOS.xcodeproj via xcodegen..."
cd "$IOS_DIR"
xcodegen generate

# 4. xcodebuild archive
echo "→ Archiving CaleniOS (Release, generic iOS)..."
mkdir -p "$ARCHIVE_DIR"
rm -rf "$ARCHIVE_PATH"

xcodebuild \
    -project "$IOS_DIR/CaleniOS.xcodeproj" \
    -scheme CaleniOS \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
    archive

# 5. export-options.plist 의 $(DEVELOPMENT_TEAM) placeholder 치환
echo "→ Exporting .ipa..."
mkdir -p "$IPA_DIR"
rm -rf "$IPA_DIR"/*.ipa "$IPA_DIR"/Packaging.log 2>/dev/null || true

# $(DEVELOPMENT_TEAM) 을 실제 값으로 치환한 사본 생성
python3 - "$EXPORT_OPTIONS" "$EXPORT_OPTIONS_RESOLVED" "${DEVELOPMENT_TEAM:-}" <<'PY'
import sys, re, pathlib
src, dst, team = sys.argv[1], sys.argv[2], sys.argv[3]
text = pathlib.Path(src).read_text()
text = text.replace("$(DEVELOPMENT_TEAM)", team)
pathlib.Path(dst).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(dst).write_text(text)
PY

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$IPA_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_RESOLVED"

# 6. 결과 출력
IPA_FILE="$(ls -t "$IPA_DIR"/*.ipa 2>/dev/null | head -n 1 || true)"
if [ -z "$IPA_FILE" ]; then
    echo "✗ .ipa 생성 실패 — $IPA_DIR 확인" >&2
    exit 1
fi

echo ""
echo "=== Done! ==="
echo "archive: $ARCHIVE_PATH"
echo "ipa:     $IPA_FILE"
echo ""
echo "TestFlight 업로드는 Xcode Organizer 에서 수동 진행하세요."
