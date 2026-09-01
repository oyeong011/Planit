#!/bin/bash
# reauth-cli.sh — Codex / Claude CLI 인증 상태 점검 및 재로그인 가이드.
#
# 배경:
#   Calen 개발 흐름에서 Codex CLI 또는 Claude Code CLI를 자주 위임 호출하는데,
#   ChatGPT 계정으로 codex login 한 경우 gpt-5 / gpt-5-codex 모델 호출이
#   거부된다. 이런 상황을 빠르게 진단하고 다음 액션을 안내하기 위한 헬퍼.
#
# Usage:
#   scripts/reauth-cli.sh                 # 진단만
#   scripts/reauth-cli.sh --fix           # 실패 시 재로그인까지 시도 (대화형)
#   scripts/reauth-cli.sh --codex-api-key # OPENAI_API_KEY로 codex 강제 재로그인
#
# Exit codes:
#   0 — 모두 OK
#   1 — codex 문제
#   2 — claude 문제
#   3 — 둘 다 문제

set -uo pipefail

# ANSI colors
if [ -t 1 ]; then
    R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[2m'; X=$'\033[0m'
else
    R=""; G=""; Y=""; B=""; D=""; X=""
fi

ok()    { echo "${G}✓${X} $*"; }
warn()  { echo "${Y}!${X} $*"; }
fail()  { echo "${R}✗${X} $*"; }
note()  { echo "${D}  $*${X}"; }
hr()    { echo "${B}────────────────────────────────────────${X}"; }

MODE_FIX=false
MODE_CODEX_APIKEY=false
for arg in "$@"; do
    case "$arg" in
        --fix) MODE_FIX=true ;;
        --codex-api-key) MODE_CODEX_APIKEY=true; MODE_FIX=true ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) fail "알 수 없는 인자: $arg"; exit 64 ;;
    esac
done

CODEX_FAIL=0
CLAUDE_FAIL=0

# ───────────────────────────────────────── Codex ─────────────────────────────────────────
hr
echo "${B}Codex CLI${X}"
hr

if ! command -v codex >/dev/null 2>&1; then
    fail "codex 미설치"
    note "설치: npm i -g @openai/codex   또는   brew install codex"
    CODEX_FAIL=1
else
    ok "binary: $(command -v codex) ($(codex --version 2>/dev/null | head -1))"

    STATUS=$(codex login status 2>&1 || true)
    echo "  ${D}login status:${X} $STATUS"

    # ChatGPT 계정인지 감지 — gpt-5 모델 사용 불가의 가장 흔한 원인
    if echo "$STATUS" | grep -qi "ChatGPT"; then
        warn "ChatGPT 계정으로 로그인됨 → gpt-5 / gpt-5-codex 호출 시 400 에러"
        note "해결: API key 모드로 전환 (--codex-api-key 옵션)"
        CODEX_FAIL=1
    elif echo "$STATUS" | grep -qiE "not logged|no auth|none"; then
        fail "로그인 안 됨"
        CODEX_FAIL=1
    fi

    # 실제 호출 가능성 빠른 테스트 — gpt-5에 ping (전체 라운드 트립 X, --help가 아닌
    # 가장 가벼운 실제 호출). 실패하면 exit code 캐치.
    echo "  ${D}probe: codex exec -m gpt-5 ...${X}"
    PROBE_OUT=$(printf '%s' 'reply with the single word OK' | \
        codex exec -m gpt-5 --sandbox read-only --skip-git-repo-check 2>&1 | tail -20 || true)
    if echo "$PROBE_OUT" | grep -qiE "not supported|invalid_request|Unauthorized|401|403"; then
        fail "gpt-5 호출 거부 — 계정/플랜이 해당 모델을 허용하지 않음"
        echo "$PROBE_OUT" | grep -iE "error|message" | head -3 | sed 's/^/    /'
        CODEX_FAIL=1
    elif echo "$PROBE_OUT" | grep -qi "OK"; then
        ok "gpt-5 호출 OK"
    else
        warn "gpt-5 호출 결과 모호 — 수동 확인 권장"
        echo "$PROBE_OUT" | tail -5 | sed 's/^/    /'
    fi
fi

if [ "$CODEX_FAIL" = "1" ] && [ "$MODE_FIX" = "true" ]; then
    hr
    if [ "$MODE_CODEX_APIKEY" = "true" ]; then
        echo "${Y}→ codex API key 모드로 재로그인${X}"
        if [ -z "${OPENAI_API_KEY:-}" ]; then
            fail "OPENAI_API_KEY 환경변수 미설정"
            note "export OPENAI_API_KEY=sk-... 후 다시 실행"
        else
            codex logout 2>/dev/null || true
            printf '%s' "$OPENAI_API_KEY" | codex login --with-api-key
            ok "codex login --with-api-key 완료. 다시 진단 실행:"
            note "  scripts/reauth-cli.sh"
        fi
    else
        echo "${Y}→ codex 대화형 재로그인${X}"
        note "팁: ChatGPT 계정이 gpt-5 거부하는 경우 --codex-api-key 옵션 사용"
        codex logout 2>/dev/null || true
        codex login
    fi
fi

# ───────────────────────────────────────── Claude ────────────────────────────────────────
hr
echo "${B}Claude Code CLI${X}"
hr

if ! command -v claude >/dev/null 2>&1; then
    fail "claude 미설치"
    note "설치: npm i -g @anthropic-ai/claude-code"
    CLAUDE_FAIL=1
else
    ok "binary: $(command -v claude) ($(claude --version 2>/dev/null | head -1))"

    # claude는 별도 login subcommand가 안정적이지 않으므로 실제 호출로 검증.
    # -p (prompt 모드, non-interactive) + 작은 입력.
    echo "  ${D}probe: claude -p ...${X}"
    PROBE_OUT=$(claude -p "reply with the single word OK" 2>&1 | tail -10 || true)
    if echo "$PROBE_OUT" | grep -qiE "unauthorized|invalid.*token|please.*log|sign.*in|api.*key.*not"; then
        fail "Claude CLI 인증 실패"
        echo "$PROBE_OUT" | tail -5 | sed 's/^/    /'
        CLAUDE_FAIL=1
    elif echo "$PROBE_OUT" | grep -qi "OK"; then
        ok "claude 호출 OK"
    else
        warn "claude 호출 결과 모호 — 수동 확인 권장"
        echo "$PROBE_OUT" | tail -5 | sed 's/^/    /'
    fi
fi

if [ "$CLAUDE_FAIL" = "1" ] && [ "$MODE_FIX" = "true" ]; then
    hr
    echo "${Y}→ Claude 재로그인 안내${X}"
    note "1. claude /logout  (또는 ~/.claude 삭제)"
    note "2. claude         (대화형 → 'Login' 선택)"
    note "또는 환경변수: export ANTHROPIC_API_KEY=sk-ant-..."
fi

# ───────────────────────────────────────── Summary ───────────────────────────────────────
hr
EXIT=0
if [ "$CODEX_FAIL" = "0" ]; then ok "Codex CLI: OK"; else fail "Codex CLI: 문제 있음"; EXIT=$((EXIT | 1)); fi
if [ "$CLAUDE_FAIL" = "0" ]; then ok "Claude CLI: OK"; else fail "Claude CLI: 문제 있음"; EXIT=$((EXIT | 2)); fi

if [ "$EXIT" != "0" ] && [ "$MODE_FIX" = "false" ]; then
    note ""
    note "재로그인 시도: $0 --fix"
    note "Codex API key 모드: OPENAI_API_KEY=... $0 --codex-api-key"
fi

exit $EXIT
