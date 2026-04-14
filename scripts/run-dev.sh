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

# lproj 파일을 Contents/Resources/ 루트에 복사 (Bundle.main이 직접 접근)
for lproj in "$BUILD_DIR/Calen_Calen.bundle"/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# 기타 리소스
cp "$BUILD_DIR/Calen_Calen.bundle/AppIcon.icns" "$APP/Contents/Resources/" 2>/dev/null || true
cp "$BUILD_DIR/Calen_Calen.bundle/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/" 2>/dev/null || true

# Info.plist 생성
cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.calen.app</string>
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

echo "🔄 Restarting Calen..."
pkill -f "Calen.app/Contents/MacOS/Calen" 2>/dev/null || true
sleep 0.3
open "$APP"

echo "✅ Calen launched from $APP"
