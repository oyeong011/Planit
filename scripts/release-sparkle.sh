#!/bin/bash
# Sparkle 릴리스 헬퍼:
#   1) build-app.sh로 .app/.zip 생성 (서명+공증 권장)
#   2) sign_update로 zip에 EdDSA 서명 생성
#   3) docs/appcast.xml에 <item> 항목 추가
#
# 사전조건:
#   - Sparkle EdDSA 키 쌍 생성:  .build/artifacts/sparkle/Sparkle/bin/generate_keys
#     → 공개키는 Info.plist의 SUPublicEDKey 에, 개인키는 Keychain에 저장됨
#   - DEVELOPER_ID, NOTARIZE_* 환경변수 export
#
# 사용법:
#   scripts/release-sparkle.sh 0.1.26 "릴리스 노트 텍스트 또는 경로"

set -euo pipefail

VERSION="${1:?사용법: $0 VERSION [릴리스노트|경로]}"
NOTES_INPUT="${2:-}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
ZIP_NAME="Calen-${VERSION}-universal.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
SPARKLE_BIN="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"
APPCAST="$PROJECT_DIR/docs/appcast.xml"

# 1) 빌드
bash "$PROJECT_DIR/scripts/build-app.sh" "$VERSION"

# 2) EdDSA 서명
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo "✗ sign_update 바이너리를 찾을 수 없습니다. swift build 이후 재시도하세요." >&2
    exit 1
fi
echo "→ Signing $ZIP_NAME with Sparkle EdDSA key..."
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH")
# sign_update 출력 형식: sparkle:edSignature="..." length="..."
ED_SIG=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

if [ -z "$ED_SIG" ] || [ -z "$LENGTH" ]; then
    echo "✗ 서명 생성 실패: $SIGN_OUTPUT" >&2
    exit 1
fi

# 3) 릴리스 노트 로드
if [ -f "$NOTES_INPUT" ]; then
    NOTES=$(cat "$NOTES_INPUT")
else
    NOTES="$NOTES_INPUT"
fi

# 고정폭 단조 증가 빌드 번호 (major*10000 + minor*100 + patch)
# 예: 0.1.26 → 126, 1.0.0 → 10000, 1.2.3 → 10203 — Sparkle 버전 비교가 항상 올바름
read V_MAJOR V_MINOR V_PATCH < <(echo "$VERSION" | awk -F. '{printf "%d %d %d\n", $1+0, $2+0, $3+0}')
BUILD_NUMBER=$((V_MAJOR * 10000 + V_MINOR * 100 + V_PATCH))
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/oyeong011/Planit/releases/download/v${VERSION}/${ZIP_NAME}"

# 4) appcast.xml에 새 <item> 삽입 (</channel> 직전)
TMP=$(mktemp)
awk -v item="\
        <item>\n\
            <title>v${VERSION}</title>\n\
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>\n\
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>\n\
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n\
            <pubDate>${PUB_DATE}</pubDate>\n\
            <enclosure\n\
                url=\"${DOWNLOAD_URL}\"\n\
                sparkle:edSignature=\"${ED_SIG}\"\n\
                length=\"${LENGTH}\"\n\
                type=\"application/octet-stream\" />\n\
            <description><![CDATA[${NOTES}]]></description>\n\
        </item>" \
    '
        /<\/channel>/ && !done { printf "%s\n", item; done=1 }
        { print }
    ' "$APPCAST" > "$TMP"
mv "$TMP" "$APPCAST"

echo ""
echo "✓ appcast.xml 업데이트 완료"
echo ""
echo "다음 단계:"
echo "  1. GitHub Release v${VERSION} 생성 및 $ZIP_NAME / DMG 업로드"
echo "  2. git add docs/appcast.xml && git commit -m \"release: v${VERSION}\""
echo "  3. git push → GitHub Pages 반영 (몇 분)"
