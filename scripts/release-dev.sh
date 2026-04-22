#!/bin/bash
# 개발 배포 스크립트 — 본배포 전 내부 테스트용
# appcast-dev.xml에만 올라가고 GitHub Release는 pre-release로 생성됨
#
# 사용법:
#   scripts/release-dev.sh 0.4.56-beta1 "테스트할 내용"

set -euo pipefail

VERSION="${1:?사용법: $0 VERSION [릴리스노트]}"
NOTES_INPUT="${2:-}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
ZIP_NAME="Calen-${VERSION}-universal.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
SPARKLE_BIN="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"
APPCAST="$PROJECT_DIR/docs/appcast-dev.xml"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)[0-9]*)?$ ]]; then
    echo "✗ VERSION must be X.Y.Z or X.Y.Z-beta1 (got: $VERSION)" >&2
    exit 1
fi

# 1) Info.plist 버전 업데이트
BASE_VERSION="${VERSION%%-*}"
read MAJOR MINOR PATCH < <(echo "$BASE_VERSION" | awk -F. '{printf "%d %d %d\n", $1+0, $2+0, $3+0}')
BUILD_NUMBER=$((MAJOR * 10000 + MINOR * 100 + PATCH))

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PROJECT_DIR/Planit/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PROJECT_DIR/Planit/Info.plist"

# 2) 빌드
bash "$PROJECT_DIR/scripts/build-app.sh" "$VERSION" || {
    if [ ! -f "$ZIP_PATH" ]; then
        echo "✗ build-app.sh 실패 — ZIP 없음" >&2
        exit 1
    fi
    echo "⚠️  build-app.sh 부분 실패 (ZIP은 생성됨) — 계속 진행"
}

# 3) EdDSA 서명
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo "✗ sign_update 없음. swift build 후 재시도" >&2
    exit 1
fi
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH")
ED_SIG=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

# 4) appcast-dev.xml 없으면 생성
if [ ! -f "$APPCAST" ]; then
    cat > "$APPCAST" <<'EOF'
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>Calen Dev</title>
        <link>https://oyeong011.github.io/Planit/appcast-dev.xml</link>
        <description>Calen development builds</description>
        <language>en</language>
    </channel>
</rss>
EOF
fi

# 5) appcast-dev.xml에 항목 추가
if [ -f "$NOTES_INPUT" ]; then
    NOTES=$(cat "$NOTES_INPUT")
else
    NOTES="$NOTES_INPUT"
fi
NOTES_CDATA="${NOTES//]]>/]]]]><![CDATA[>}"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/oyeong011/Planit/releases/download/v${VERSION}/${ZIP_NAME}"

TMP=$(mktemp)
awk -v item="\
        <item>\n\
            <title>v${VERSION} [DEV]</title>\n\
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>\n\
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>\n\
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n\
            <pubDate>${PUB_DATE}</pubDate>\n\
            <enclosure\n\
                url=\"${DOWNLOAD_URL}\"\n\
                sparkle:edSignature=\"${ED_SIG}\"\n\
                length=\"${LENGTH}\"\n\
                type=\"application/octet-stream\" />\n\
            <description><![CDATA[[DEV] ${NOTES_CDATA}]]></description>\n\
        </item>" \
    '/<\/channel>/ && !done { printf "%s\n", item; done=1 }
     { print }
    ' "$APPCAST" > "$TMP"
mv "$TMP" "$APPCAST"

# 6) GitHub pre-release 생성
gh release create "v${VERSION}" "$ZIP_PATH" \
    --title "v${VERSION} [DEV]" \
    --notes "[개발 빌드] ${NOTES}" \
    --prerelease

# 7) 커밋 & 푸시
git add "$APPCAST" "$PROJECT_DIR/Planit/Info.plist"
git commit -m "dev: v${VERSION}"
git push

echo ""
echo "✓ 개발 빌드 v${VERSION} 배포 완료"
echo "  테스트 후 이상 없으면: scripts/release-sparkle.sh 로 본배포"
