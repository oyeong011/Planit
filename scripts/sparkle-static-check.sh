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

if [ -z "$STATIC_CHECK" ]; then
    echo "✗ Sparkle staticCheck tool not found under $SPARKLE_ROOT" >&2
    exit 1
fi

echo "→ Running Sparkle staticCheck..."
"$STATIC_CHECK" "$APP_BUNDLE"
