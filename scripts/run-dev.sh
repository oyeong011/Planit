#!/bin/bash
# Calen 개발 빌드 + 실행 스크립트
# lproj 파일을 Bundle.main이 찾을 수 있는 위치에 배치
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SWIFT=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift

echo "🔨 Building..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    $SWIFT build --package-path "$PROJECT_DIR" -c release 2>&1 | grep -E "error:|warning:|Build complete"

BUILD_DIR="$PROJECT_DIR/.build/release"
APP=/tmp/Calen.app

echo "📦 Creating app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# 바이너리 복사
cp "$BUILD_DIR/Calen" "$APP/Contents/MacOS/Calen"
chmod +x "$APP/Contents/MacOS/Calen"

# lproj를 소스에서 직접 복사 → Bundle.main이 찾을 수 있도록
for lproj in "$PROJECT_DIR/Planit/Resources"/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# 기타 리소스
cp "$BUILD_DIR/Calen_Calen.bundle/AppIcon.icns" "$APP/Contents/Resources/" 2>/dev/null || true
cp "$BUILD_DIR/Calen_Calen.bundle/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/" 2>/dev/null || true
cp "$PROJECT_DIR/Planit/Planit.entitlements" "$APP/Contents/Resources/" 2>/dev/null || true

# Sparkle.framework 임베드 (없으면 @rpath 로드 실패로 런타임 크래시)
SPARKLE_SRC="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
    ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"
    # SPM 기본 rpath에는 @executable_path/../Frameworks가 없음 — 추가해야 dyld가 임베드된 Sparkle을 찾는다
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Calen" 2>/dev/null || true
fi

# Info.plist — 실제 Planit/Info.plist 사용해 dev 빌드도 올바른 버전을 표시
# 하드코딩 1.0 대신 소스의 CFBundleShortVersionString 를 그대로 반영
cp "$PROJECT_DIR/Planit/Info.plist" "$APP/Contents/Info.plist"
# dev 빌드 식별용 suffix (CFBundleVersion 뒤에 -dev 붙이지 않음 — Sparkle 비교 정확성 유지)
DEV_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
echo "   Info.plist version: $DEV_VERSION"

# 개발 빌드 서명 (키체인 프롬프트 방지)
# DEVELOPER_ID 환경변수 없으면 로컬 키체인에서 자동 감지
DEV_SIGN="${DEVELOPER_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/')}"
if [ -n "$DEV_SIGN" ]; then
    echo "✍️  Signing with: $DEV_SIGN"
    SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE_FW" ]; then
        # inside-out: XPC → Autoupdate → Updater.app → framework → main app
        for xpc in "$SPARKLE_FW/Versions/B/XPCServices"/*.xpc; do
            [ -d "$xpc" ] && codesign --force --options runtime \
                --preserve-metadata=identifier,entitlements,flags \
                --sign "$DEV_SIGN" "$xpc" 2>/dev/null || true
        done
        codesign --force --options runtime --sign "$DEV_SIGN" \
            "$SPARKLE_FW/Versions/B/Autoupdate" 2>/dev/null || true
        codesign --force --options runtime --sign "$DEV_SIGN" \
            "$SPARKLE_FW/Versions/B/Updater.app" 2>/dev/null || true
        codesign --force --options runtime --sign "$DEV_SIGN" "$SPARKLE_FW" 2>/dev/null || true
    fi
    codesign --force --options runtime \
        --entitlements "$PROJECT_DIR/Planit/Planit-dev.entitlements" \
        --sign "$DEV_SIGN" \
        "$APP" 2>/dev/null && echo "   Signed OK" || echo "   Sign failed (continuing unsigned)"
else
    echo "⚠️  No Developer ID found — running unsigned (키체인 프롬프트 발생)"
fi

echo "🔄 Restarting Calen..."
pkill -f "Calen.app/Contents/MacOS/Calen" 2>/dev/null || true
sleep 0.3
open "$APP"

echo "✅ Calen launched from $APP"
