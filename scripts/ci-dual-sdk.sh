#!/usr/bin/env bash
#
# ci-dual-sdk.sh — Calen dual-SDK (macOS + iOS) CI 체크
#
# 수행 순서:
#   1) swift build               (macOS Debug)      — fail → exit 1
#   2) swift build -c release    (macOS Release)    — fail → exit 2
#   3) swift test                (CalenTests)       — fail → exit 3
#   4) xcodebuild CaleniOS       (iOS Simulator)    — fail → exit 4
#
# 사용:
#   bash scripts/ci-dual-sdk.sh
#   또는 make ci-ios
#
# 주의: 이 스크립트는 프로젝트 루트(`Package.swift` 위치)에서 실행된다는 가정.

set -u
set -o pipefail

# 레포 루트로 이동 (이 스크립트가 scripts/ 아래에 있다는 가정)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

echo "=== Calen dual-SDK CI start ==="
echo "repo: ${REPO_ROOT}"
echo "swift: $(swift --version | head -1)"
echo "xcodebuild: $(xcodebuild -version | head -1)"
echo ""

# ---------------------------------------------------------------------------
echo "=== Step 1: swift build (macOS Debug) ==="
if ! swift build; then
    echo "[FAIL] Step 1: macOS Debug build failed" >&2
    exit 1
fi
echo "=== Step 1: OK ==="
echo ""

# ---------------------------------------------------------------------------
echo "=== Step 2: swift build -c release (macOS Release) ==="
if ! swift build -c release; then
    echo "[FAIL] Step 2: macOS Release build failed" >&2
    exit 2
fi
echo "=== Step 2: OK ==="
echo ""

# ---------------------------------------------------------------------------
echo "=== Step 3: swift test (CalenTests) ==="
if ! swift test; then
    echo "[FAIL] Step 3: swift test failed" >&2
    exit 3
fi
echo "=== Step 3: OK ==="
echo ""

# ---------------------------------------------------------------------------
echo "=== Step 4: xcodebuild CaleniOS (generic/platform=iOS Simulator) ==="
if ! xcodebuild \
        -scheme CaleniOS \
        -destination 'generic/platform=iOS Simulator' \
        -configuration Debug \
        build; then
    echo "[FAIL] Step 4: iOS Simulator build failed" >&2
    exit 4
fi
echo "=== Step 4: OK ==="
echo ""

echo "✅ All dual-SDK checks passed"
