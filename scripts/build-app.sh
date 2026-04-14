#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Calen"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="Calen-${VERSION}-universal.dmg"
ZIP_NAME="Calen-${VERSION}-universal.zip"

echo "=== Building Calen v${VERSION} ==="

# 1. Release build
echo "→ Building release binary..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64

# 2. Create .app bundle
echo "→ Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary (SPM target name is "Calen")
cp "$BUILD_DIR/Calen" "$APP_BUNDLE/Contents/MacOS/Calen"

# Copy Info.plist
cp "$PROJECT_DIR/Planit/Info.plist" "$APP_BUNDLE/Contents/Resources/Info.plist"
# Also place at Contents/Info.plist (macOS expects it here)
cp "$PROJECT_DIR/Planit/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Update version in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Copy entitlements (for reference, not enforced without signing)
cp "$PROJECT_DIR/Planit/Planit.entitlements" "$APP_BUNDLE/Contents/Resources/"

# Copy PrivacyInfo
if [ -f "$PROJECT_DIR/Planit/Resources/PrivacyInfo.xcprivacy" ]; then
    cp "$PROJECT_DIR/Planit/Resources/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy app icon
cp "$PROJECT_DIR/Planit/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Copy bundled resources from SPM build
if [ -d "$BUILD_DIR/Calen_Calen.bundle" ]; then
    cp -R "$BUILD_DIR/Calen_Calen.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

echo "→ .app bundle created at: $APP_BUNDLE"

# 3. Create zip
echo "→ Creating zip..."
cd "$BUILD_DIR"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME"
echo "→ Zip: $BUILD_DIR/$ZIP_NAME"

# 4. Create DMG
echo "→ Creating DMG..."
rm -f "$BUILD_DIR/$DMG_NAME"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Calen" -srcfolder "$STAGING" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"
rm -rf "$STAGING"
echo "→ DMG: $BUILD_DIR/$DMG_NAME"

# 5. Print SHA256 for Homebrew
echo ""
echo "=== SHA256 Checksums ==="
shasum -a 256 "$BUILD_DIR/$ZIP_NAME"
shasum -a 256 "$BUILD_DIR/$DMG_NAME"

echo ""
echo "=== Done! ==="
echo "Upload $BUILD_DIR/$ZIP_NAME to GitHub Release v${VERSION}"
