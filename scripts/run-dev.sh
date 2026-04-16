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

# Info.plist 생성
cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.oy.planit</string>
    <key>CFBundleName</key>
    <string>Calen</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Calen</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 개발 빌드 서명 (키체인 프롬프트 방지)
# DEVELOPER_ID 환경변수 없으면 로컬 키체인에서 자동 감지
DEV_SIGN="${DEVELOPER_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/')}"
if [ -n "$DEV_SIGN" ]; then
    echo "✍️  Signing with: $DEV_SIGN"
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
