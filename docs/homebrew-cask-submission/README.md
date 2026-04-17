# Homebrew Cask 정식 등록 준비

이 디렉터리는 `Homebrew/homebrew-cask` 저장소에 `calen-ai` cask를 제출하기 위한 작업 파일들입니다.

## 제출 전 체크리스트

### 자동 검증된 항목 ✓
- [x] `cask "calen-ai"` 블록 / `version` / `sha256`
- [x] `url` + `verified:`
- [x] `name`, `desc` (80자 이내), `homepage` (https)
- [x] `livecheck` (GitHub releases atom)
- [x] `auto_updates true` (Sparkle 사용 중)
- [x] `depends_on macos: ">= :sonoma"` (macOS 14+)
- [x] `app "Calen.app"`
- [x] `zap trash: [...]` (완전 제거 경로)

### 사용자 확보 필요 항목 (Notable 요건)
Homebrew-cask는 "notable" 프로젝트만 받습니다. 아래 셋 중 하나 이상 충족:
- [ ] GitHub **stars ≥ 30**
- [ ] GitHub **forks ≥ 30**
- [ ] GitHub **watchers ≥ 75**

현재: 0 stars / 0 forks. 공식 등록 전까지 **최소 30 stars** 확보 필요.

### 제출 전 해야 할 로컬 검증
```bash
# 1. Homebrew 최신화
brew update

# 2. Command Line Tools 업데이트 (현재 outdated)
sudo rm -rf /Library/Developer/CommandLineTools
sudo xcode-select --install

# 3. 로컬에서 설치 시뮬레이션
brew install --cask ./Casks/c/calen-ai.rb
brew uninstall --cask calen-ai

# 4. Lint + audit
brew style ./Casks/c/calen-ai.rb
brew audit --cask --new ./Casks/c/calen-ai.rb
```

## 제출 절차

```bash
# 1. homebrew-cask fork
gh repo fork Homebrew/homebrew-cask --clone=true
cd homebrew-cask

# 2. 새 branch
git checkout -b add-calen-ai

# 3. cask 파일 복사 (Casks/c/ 하위)
cp /Users/oy/Projects/Planit/docs/homebrew-cask-submission/Casks/c/calen-ai.rb Casks/c/

# 4. audit 통과 확인
brew audit --cask --new Casks/c/calen-ai.rb

# 5. PR 제출
git add Casks/c/calen-ai.rb
git commit -m "calen-ai 0.2.3 (new cask)"
gh pr create --title "calen-ai 0.2.3 (new cask)" \
  --body "AI-powered menu bar calendar app for macOS. Signed, notarized, Sparkle-enabled. \
         First cask submission."
```

Homebrew 리뷰어 피드백 1~7일 내 예상.

## 단계별 계획

1. **지금**: LICENSE 추가 완료, cask 스켈레톤 검증 완료
2. **다음**: 30 stars 확보 (홍보) — 이 기간에 버그 고치고 피드백 수집
3. **준비 완료 시**: 위 제출 절차 수행
