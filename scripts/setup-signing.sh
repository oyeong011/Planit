#!/bin/bash
# 로컬 서명/공증 환경변수 설정 스크립트
# 사용법: source scripts/setup-signing.sh

echo "=== Calen 코드 서명 환경 확인 ==="

echo ""
echo "▸ 등록된 Developer ID 인증서:"
security find-identity -v -p codesigning | grep "Developer ID" || echo "  (없음 — Xcode > Settings > Accounts에서 다운로드)"

echo ""
echo "▸ Team ID: QLNL47XVL9"
echo "▸ Developer ID: Developer ID Application: Oyeong Gwon (QLNL47XVL9)"

echo ""
echo "=== 환경변수 설정 (아래 값을 export 하세요) ==="
cat << 'ENV'
export DEVELOPER_ID="Developer ID Application: Oyeong Gwon (QLNL47XVL9)"
export NOTARIZE_TEAM_ID="QLNL47XVL9"
export NOTARIZE_APPLE_ID="your@apple.id"           # 실제 Apple ID로 교체
export NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx"    # appleid.apple.com > App-Specific Passwords
ENV

echo ""
echo "=== 빌드 실행 ==="
echo "  scripts/build-app.sh 0.1.0"

echo ""
echo "=== GitHub Secrets 등록 방법 ==="
echo "  1. .p12 인증서 내보내기: Keychain Access > 인증서 우클릭 > Export"
echo "  2. base64 인코딩: base64 -i cert.p12 | pbcopy"
echo "  3. github.com/oyeong011/Planit/settings/secrets/actions 에 등록:"
echo "     DEVELOPER_ID              = 'Developer ID Application: Oyeong Gwon (QLNL47XVL9)'"
echo "     DEVELOPER_ID_CERT_P12     = (base64 인코딩된 .p12)"
echo "     DEVELOPER_ID_CERT_PASSWORD = (p12 내보낼 때 설정한 비밀번호)"
echo "     NOTARIZE_APPLE_ID         = (Apple ID 이메일)"
echo "     NOTARIZE_PASSWORD         = (App-specific password)"
echo "     NOTARIZE_TEAM_ID          = QLNL47XVL9"
echo "     TAP_REPO_TOKEN            = (homebrew-calen repo write 권한 PAT)"
