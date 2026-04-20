#!/bin/bash
set -euo pipefail

APP_BUNDLE="${1:?usage: $0 /path/to/App.app}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_ROOT="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "✗ app bundle not found: $APP_BUNDLE" >&2
    exit 1
fi

STATIC_CHECK=""
for candidate in \
    "$SPARKLE_ROOT/bin/staticCheck" \
    "$SPARKLE_ROOT/bin/staticcheck"
do
    if [ -x "$candidate" ]; then
        STATIC_CHECK="$candidate"
        break
    fi
done

if [ -z "$STATIC_CHECK" ]; then
    STATIC_CHECK="$(find "$SPARKLE_ROOT" -type f \( -name staticCheck -o -name staticcheck \) -perm -111 2>/dev/null | head -n 1 || true)"
fi

if [ -n "$STATIC_CHECK" ]; then
    echo "→ Running Sparkle staticCheck..."
    "$STATIC_CHECK" "$APP_BUNDLE"
    exit 0
fi

echo "→ Sparkle staticCheck tool not found; running bundled static checks..."

PLIST="$APP_BUNDLE/Contents/Info.plist"
SPARKLE_FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

if [ ! -f "$PLIST" ]; then
    echo "✗ Info.plist missing from app bundle" >&2
    exit 1
fi

PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" 2>/dev/null || true)
FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$PLIST" 2>/dev/null || true)

if [ -z "$PUBLIC_KEY" ]; then
    echo "✗ SUPublicEDKey missing from Info.plist" >&2
    exit 1
fi

if ! printf '%s' "$PUBLIC_KEY" | /usr/bin/base64 --decode >/dev/null 2>&1; then
    echo "✗ SUPublicEDKey is not valid base64" >&2
    exit 1
fi

case "$FEED_URL" in
    https://*) ;;
    *)
        echo "✗ SUFeedURL must be https: $FEED_URL" >&2
        exit 1
        ;;
esac

if [ ! -d "$SPARKLE_FW" ]; then
    echo "✗ Sparkle.framework is not embedded" >&2
    exit 1
fi

if codesign --verify "$APP_BUNDLE" >/dev/null 2>&1; then
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
    echo "ℹ︎ App bundle is unsigned; skipping codesign verification"
fi

echo "✓ Sparkle static checks passed"
