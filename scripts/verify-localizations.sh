#!/bin/bash
# Localizable.strings 검증 — 각 언어 파일이 base(ko)의 모든 key를 갖고 있는지 확인
# 사용: scripts/verify-localizations.sh

set -euo pipefail
# sort/comm이 로케일 영향받지 않게 C 로케일 고정
export LC_ALL=C
cd "$(dirname "$0")/.."

BASE="Planit/Resources/ko.lproj/Localizable.strings"
if [ ! -f "$BASE" ]; then
    echo "❌ base 파일 없음: $BASE"
    exit 1
fi

# key만 추출하는 헬퍼 — "key" = "value"; 형식
extract_keys() {
    grep -oE '^"[^"]+"' "$1" | sort -u
}

BASE_KEYS=$(mktemp)
extract_keys "$BASE" > "$BASE_KEYS"
BASE_COUNT=$(wc -l < "$BASE_KEYS" | tr -d ' ')
echo "📘 Base (ko): $BASE_COUNT keys"
echo ""

TOTAL_MISSING=0
TOTAL_EXTRA=0
FAILED_LANGS=()

for lproj in Planit/Resources/*.lproj; do
    LANG=$(basename "$lproj" .lproj)
    if [ "$LANG" = "ko" ]; then continue; fi

    FILE="$lproj/Localizable.strings"
    if [ ! -f "$FILE" ]; then
        echo "❌ $LANG: 파일 없음"
        FAILED_LANGS+=("$LANG")
        continue
    fi

    LANG_KEYS=$(mktemp)
    extract_keys "$FILE" > "$LANG_KEYS"
    LANG_COUNT=$(wc -l < "$LANG_KEYS" | tr -d ' ')

    MISSING=$(comm -23 "$BASE_KEYS" "$LANG_KEYS")
    EXTRA=$(comm -13 "$BASE_KEYS" "$LANG_KEYS")
    # 빈 문자열이면 0, 아니면 line 개수
    if [ -z "$MISSING" ]; then MISSING_COUNT=0; else MISSING_COUNT=$(printf '%s\n' "$MISSING" | wc -l | tr -d ' '); fi
    if [ -z "$EXTRA" ]; then EXTRA_COUNT=0; else EXTRA_COUNT=$(printf '%s\n' "$EXTRA" | wc -l | tr -d ' '); fi

    if [ "$MISSING_COUNT" -eq 0 ] && [ "$EXTRA_COUNT" -eq 0 ]; then
        printf "✅ %-10s %4d keys\n" "$LANG" "$LANG_COUNT"
    else
        printf "⚠️  %-10s %4d keys  (missing: %d, extra: %d)\n" "$LANG" "$LANG_COUNT" "$MISSING_COUNT" "$EXTRA_COUNT"
        TOTAL_MISSING=$((TOTAL_MISSING + MISSING_COUNT))
        TOTAL_EXTRA=$((TOTAL_EXTRA + EXTRA_COUNT))
        FAILED_LANGS+=("$LANG")

        if [ "$MISSING_COUNT" -gt 0 ] && [ "$MISSING_COUNT" -le 10 ]; then
            echo "   누락된 키:"
            echo "$MISSING" | sed 's/^/     /'
        fi
    fi
    rm -f "$LANG_KEYS"
done

rm -f "$BASE_KEYS"

echo ""
echo "==============================="
if [ ${#FAILED_LANGS[@]} -eq 0 ]; then
    echo "✅ 모든 언어 완전 (29개)"
    exit 0
else
    echo "⚠️  문제 있는 언어: ${#FAILED_LANGS[@]}개 (누락 $TOTAL_MISSING, 불필요 $TOTAL_EXTRA)"
    echo "   ${FAILED_LANGS[*]}"
    exit 1
fi
