#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Calen"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="Calen-${VERSION}-universal.dmg"
ZIP_NAME="Calen-${VERSION}-universal.zip"

# 코드 서명/공증 환경변수 (CI/CD 또는 로컬에서 export 후 실행)
# export DEVELOPER_ID="Developer ID Application: 권오영 (TEAM_ID)"
# export NOTARIZE_TEAM_ID="XXXXXXXXXX"
# export NOTARIZE_APPLE_ID="you@example.com"
# export NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password
SIGN="${DEVELOPER_ID:-}"
TEAM_ID="${NOTARIZE_TEAM_ID:-}"
APPLE_ID="${NOTARIZE_APPLE_ID:-}"
APP_PWD="${NOTARIZE_PASSWORD:-}"

echo "=== Building Calen v${VERSION} ==="

# 1. Release build — arch별 개별 빌드 후 lipo로 합치기
#    (최신 Xcode SwiftBuild에서 `--arch arm64 --arch x86_64` 동시 호출이 hang하는 이슈 회피)
cd "$PROJECT_DIR"
echo "→ Building release binary (arm64)..."
swift build -c release --arch arm64
echo "→ Building release binary (x86_64)..."
swift build -c release --arch x86_64

mkdir -p "$BUILD_DIR"
echo "→ Creating universal binary via lipo..."
lipo -create \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/Calen" \
    "$PROJECT_DIR/.build/x86_64-apple-macosx/release/Calen" \
    -output "$BUILD_DIR/Calen"

# 2. Create .app bundle
echo "→ Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# VERSION="1.2.3" → BUILD_NUMBER=10203 (각 성분 2자리 고정, 단조 증가 보장)
read MAJOR MINOR PATCH < <(echo "$VERSION" | awk -F. '{printf "%d %d %d\n", $1+0, $2+0, $3+0}')
BUILD_NUMBER=$((MAJOR * 10000 + MINOR * 100 + PATCH))

cp "$BUILD_DIR/Calen" "$APP_BUNDLE/Contents/MacOS/Calen"
cp "$PROJECT_DIR/Planit/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Planit/Info.plist" "$APP_BUNDLE/Contents/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "$PROJECT_DIR/Planit/Resources/PrivacyInfo.xcprivacy" ]; then
    cp "$PROJECT_DIR/Planit/Resources/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/"
fi
cp "$PROJECT_DIR/Planit/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
RBUNDLE="$PROJECT_DIR/.build/arm64-apple-macosx/release/Calen_Calen.bundle"
if [ -d "$RBUNDLE" ]; then
    cp -R "$RBUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi
# lproj를 소스에서 직접 복사 → Bundle.main이 찾을 수 있도록
for lproj in "$PROJECT_DIR/Planit/Resources"/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
done

# Sparkle.framework 번들링 (자동 업데이트)
SPARKLE_SRC="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    echo "→ Embedding Sparkle.framework..."
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    rm -rf "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    ditto "$SPARKLE_SRC" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
else
    echo "⚠️  Sparkle.framework 아티팩트 없음 — swift build 먼저 실행하세요"
fi

echo "→ .app bundle created at: $APP_BUNDLE"

# 3. 코드 서명 (Sparkle은 inside-out 순서 필수)
if [ -n "$SIGN" ]; then
    echo "→ Code signing with: $SIGN"
    SPARKLE_FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE_FW" ]; then
        # XPC services → Autoupdate → Updater.app → framework 순서
        for xpc in "$SPARKLE_FW/Versions/B/XPCServices"/*.xpc; do
            [ -d "$xpc" ] && codesign --force --options runtime --timestamp \
                --preserve-metadata=identifier,entitlements,flags \
                --sign "$SIGN" "$xpc"
        done
        codesign --force --options runtime --timestamp --sign "$SIGN" \
            "$SPARKLE_FW/Versions/B/Autoupdate"
        codesign --force --options runtime --timestamp --sign "$SIGN" \
            "$SPARKLE_FW/Versions/B/Updater.app"
        codesign --force --options runtime --timestamp --sign "$SIGN" "$SPARKLE_FW"
    fi
    # 메인 앱 마지막
    codesign --force --options runtime \
        --entitlements "$PROJECT_DIR/Planit/Planit.entitlements" \
        --sign "$SIGN" \
        --timestamp \
        "$APP_BUNDLE"
    echo "→ Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    spctl --assess --type execute --verbose "$APP_BUNDLE" 2>&1 || true
else
    echo "⚠️  DEVELOPER_ID not set — skipping code signing (unsigned build)"
fi

# 4. Create zip (공증 제출용)
echo "→ Creating zip..."
cd "$BUILD_DIR"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME"
echo "→ Zip: $BUILD_DIR/$ZIP_NAME"

# 5. 공증(Notarization)
if [ -n "$SIGN" ] && [ -n "$TEAM_ID" ] && [ -n "$APPLE_ID" ] && [ -n "$APP_PWD" ]; then
    echo "→ Submitting for notarization..."
    xcrun notarytool submit "$BUILD_DIR/$ZIP_NAME" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PWD" \
        --team-id "$TEAM_ID" \
        --wait
    echo "→ Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"
    # 스테이플된 앱으로 zip 재생성
    cd "$BUILD_DIR"
    rm -f "$ZIP_NAME"
    ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME"
    echo "→ Notarization complete and stapled."
else
    echo "⚠️  Notarization env vars not set — skipping notarization"
    echo "   Set DEVELOPER_ID, NOTARIZE_TEAM_ID, NOTARIZE_APPLE_ID, NOTARIZE_PASSWORD"
fi

# 6. Create DMG
echo "→ Creating DMG..."
rm -f "$BUILD_DIR/$DMG_NAME"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Calen" -srcfolder "$STAGING" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"
rm -rf "$STAGING"

# DMG도 공증 스테이플
if [ -n "$SIGN" ] && [ -n "$TEAM_ID" ] && [ -n "$APPLE_ID" ] && [ -n "$APP_PWD" ]; then
    xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
fi

echo "→ DMG: $BUILD_DIR/$DMG_NAME"

# 7. SHA256 (Homebrew 포뮬러용)
echo ""
echo "=== SHA256 Checksums (Homebrew 포뮬러에 사용) ==="
ZIP_SHA=$(shasum -a 256 "$BUILD_DIR/$ZIP_NAME" | awk '{print $1}')
DMG_SHA=$(shasum -a 256 "$BUILD_DIR/$DMG_NAME" | awk '{print $1}')
echo "zip: $ZIP_SHA  $BUILD_DIR/$ZIP_NAME"
echo "dmg: $DMG_SHA  $BUILD_DIR/$DMG_NAME"

echo ""
echo "=== Homebrew Cask 업데이트 방법 ==="
echo "1. GitHub Release v${VERSION} 에 $ZIP_NAME 업로드"
echo "2. Casks/calen.rb의 version, sha256, url 수정:"
echo "   version  \"${VERSION}\""
echo "   sha256   \"${ZIP_SHA}\""
echo "   url      \"https://github.com/YOUR_ORG/calen/releases/download/v${VERSION}/${ZIP_NAME}\""

echo ""
echo "=== Done! ==="
