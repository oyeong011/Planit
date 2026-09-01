#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT_DIR/CaleniOS"
PROJECT_YML="$IOS_DIR/project.yml"
PROJECT_FILE="$IOS_DIR/CaleniOS.xcodeproj/project.pbxproj"
MAIN_ENTITLEMENTS="$IOS_DIR/Sources/Resources/CaleniOS.entitlements"
WIDGET_ENTITLEMENTS="$IOS_DIR/Widget/CaleniOSWidget.entitlements"
IOS_INFO="$IOS_DIR/Sources/Info.plist"
WIDGET_INFO="$IOS_DIR/Widget/Info.plist"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-ios-app.sh"
EXPORT_OPTIONS="$ROOT_DIR/scripts/ios-export-options.plist"
IOS_BUILD_GUIDE="$IOS_DIR/BUILD.md"

PASS_COUNT=0
FAIL_COUNT=0
BLOCKER_COUNT=0

file_mtime() {
    local file="$1"
    if stat -f "%m" "$file" >/dev/null 2>&1; then
        stat -f "%m" "$file"
    else
        stat -c "%Y" "$file"
    fi
}

emit_pass() {
    local msg="$1"
    echo "✅ PASS: $msg"
    PASS_COUNT=$((PASS_COUNT + 1))
}

emit_fail() {
    local msg="$1"
    echo "❌ FAIL: $msg"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

emit_blocker() {
    local msg="$1"
    echo "🚫 BLOCKER: $msg"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
}

check_file() {
    local file="$1"
    local label="$2"
    if [ -f "$file" ]; then
        emit_pass "$label exists: $file"
    else
        emit_fail "$label missing: $file"
    fi
}

check_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        emit_pass "command '$cmd' is available"
    else
        emit_fail "command '$cmd' is required for prerequisite checks"
    fi
}

check_text() {
    local pattern="$1"
    local file="$2"
    local label="$3"
    if [ -f "$file" ] && grep -Fq "$pattern" "$file"; then
        emit_pass "$label"
    else
        emit_fail "$label (missing pattern '$pattern' in $file)"
    fi
}

check_yaml_kv() {
    local key="$1"
    local expected="$2"
    local file="$3"
    local label="$4"
    if rg -n "^[[:space:]]*${key}:[[:space:]]*${expected}[[:space:]]*$" "$file" >/dev/null 2>&1; then
        emit_pass "$label"
    else
        emit_fail "$label (expected $key: $expected)"
    fi
}

check_project_freshness() {
    local before_ts="0"
    local after_ts="0"

    if [ -f "$PROJECT_FILE" ]; then
        before_ts="$(file_mtime "$PROJECT_FILE")"
    fi

    if (cd "$IOS_DIR" && xcodegen generate); then
        after_ts="$(file_mtime "$PROJECT_FILE")"
    else
        emit_fail "xcodegen generate failed in $IOS_DIR"
        return
    fi

    if [ -f "$PROJECT_FILE" ] && [ "$before_ts" -eq 0 ]; then
        emit_pass "generated project created by xcodegen"
    elif [ "$after_ts" -ge "$before_ts" ]; then
        emit_pass "generated project is refreshed by xcodegen"
    else
        emit_fail "generated project did not refresh; expected newer project after generate"
    fi
}

echo "🔎 Verifying iOS release readiness (CaleniOS)"
echo ""

check_file "$PROJECT_YML" "Project spec"
check_file "$BUILD_SCRIPT" "Release build script"
check_file "$IOS_INFO" "iOS Info.plist"
check_file "$WIDGET_INFO" "Widget Info.plist"
check_file "$MAIN_ENTITLEMENTS" "Main app entitlements"
check_file "$WIDGET_ENTITLEMENTS" "Widget entitlements"
check_file "$IOS_BUILD_GUIDE" "iOS build guide"
check_file "$EXPORT_OPTIONS" "iOS export options plist"

echo ""

check_command "xcodegen"
check_command "xcodebuild"

echo ""

if [ -f "$PROJECT_YML" ] && command -v xcodegen >/dev/null 2>&1; then
    check_project_freshness
fi

if [ -f "$PROJECT_YML" ]; then
    check_yaml_kv "bundleIdPrefix" "com.oy.planit" "$PROJECT_YML" "project.yml bundleIdPrefix is com.oy.planit"
    check_yaml_kv "PRODUCT_BUNDLE_IDENTIFIER" "com.oy.planit.ios" "$PROJECT_YML" "main bundle ID is com.oy.planit.ios"
    check_text "PRODUCT_BUNDLE_IDENTIFIER: com.oy.planit.ios.widget" "$PROJECT_YML" "widget bundle ID is com.oy.planit.ios.widget"
    check_text "PRODUCT_NAME: CaleniOSWidget" "$PROJECT_YML" "widget product name is set"
fi

if [ -f "$MAIN_ENTITLEMENTS" ]; then
    check_text "com.apple.security.application-groups" "$MAIN_ENTITLEMENTS" "main app app group entitlement key present"
    check_text "group.com.oy.planit" "$MAIN_ENTITLEMENTS" "main app app group value includes group.com.oy.planit"
    check_text "com.apple.developer.icloud-container-identifiers" "$MAIN_ENTITLEMENTS" "main app iCloud container entitlement key present"
    check_text "iCloud.com.oy.planit" "$MAIN_ENTITLEMENTS" "main app iCloud container value includes iCloud.com.oy.planit"
    check_text "keychain-access-groups" "$MAIN_ENTITLEMENTS" "main app keychain access group key present"
    check_text '$(AppIdentifierPrefix)group.com.oy.planit' "$MAIN_ENTITLEMENTS" "main app keychain group placeholder includes AppIdentifierPrefix"
    check_text "com.apple.developer.icloud-services" "$MAIN_ENTITLEMENTS" "main app iCloud service entitlement key present"
    check_text "CloudKit" "$MAIN_ENTITLEMENTS" "main app iCloud service includes CloudKit"
fi

if [ -f "$WIDGET_ENTITLEMENTS" ]; then
    check_text "com.apple.security.application-groups" "$WIDGET_ENTITLEMENTS" "widget app group entitlement key present"
    check_text "group.com.oy.planit" "$WIDGET_ENTITLEMENTS" "widget app group value includes group.com.oy.planit"
fi

echo ""

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    emit_blocker "DEVELOPMENT_TEAM is required for signing/archiving. Export with: export DEVELOPMENT_TEAM=ABCD1234EF"
else
    if [[ "${DEVELOPMENT_TEAM}" =~ ^[A-Z0-9]{10}$ ]]; then
        emit_pass "DEVELOPMENT_TEAM format is valid: ${DEVELOPMENT_TEAM}"
    else
        emit_fail "DEVELOPMENT_TEAM format is invalid (expected 10-char Apple Team ID): ${DEVELOPMENT_TEAM}"
    fi
fi

if [ -f "$PROJECT_FILE" ] && command -v xcodebuild >/dev/null 2>&1; then
    if xcodebuild -project "$IOS_DIR/CaleniOS.xcodeproj" -scheme CaleniOS -list >/tmp/.verify-ios-release-scheme.txt 2>/tmp/.verify-ios-release-scheme.err; then
        if grep -q "CaleniOS" /tmp/.verify-ios-release-scheme.txt; then
            emit_pass "xcodebuild recognizes CaleniOS scheme"
        else
            emit_fail "xcodebuild scheme output does not include CaleniOS"
        fi
    else
        emit_fail "xcodebuild -list failed for CaleniOS.xcodeproj"
    fi
    rm -f /tmp/.verify-ios-release-scheme.txt /tmp/.verify-ios-release-scheme.err
fi

if [ -f "$EXPORT_OPTIONS" ]; then
    check_text "development" "$EXPORT_OPTIONS" "ios export options contains development export method"
fi

if [ -f "$IOS_BUILD_GUIDE" ]; then
    if rg -n "현재 파이프라인은 \\*\\*로컬 \\.ipa 생성까지만\\*\\* 수행한다|TestFlight 업로드는 Xcode Organizer" "$IOS_BUILD_GUIDE" >/dev/null 2>&1; then
        emit_pass "manual TestFlight gap documented in CaleniOS/BUILD.md"
    else
        emit_fail "CaleniOS/BUILD.md does not document the current manual TestFlight upload gap"
    fi
else
    emit_fail "CaleniOS/BUILD.md is missing; cannot verify documented TestFlight gap"
fi

echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "🎉 READY: PASS"
    exit 0
elif [ "$BLOCKER_COUNT" -gt 0 ]; then
    echo "🛑 READY: FAIL (BLOCKER present)"
    exit 1
else
    echo "🛑 READY: FAIL"
    exit 1
fi
