# Calen 랜딩페이지 리디자인 프롬프트

이 프롬프트를 Claude/ChatGPT에 넣어 풀 HTML 랜딩페이지를 받으세요.

---

## 프롬프트 시작

당신은 시니어 프로덕트 디자이너 + 프론트엔드 엔지니어입니다. **Calen** 앱의 랜딩페이지를 만들어 주세요.

### 제품 정체성

**Calen** — Personal AI Calendar Assistant for macOS
- macOS menu bar 앱 (Apple Silicon + Intel universal)
- Google Calendar + Apple Calendar 통합
- AI 채팅으로 일정 관리 (Claude CLI / Codex CLI 연동)
- **Hermes 장기 기억 시스템** — 사용자 선호/패턴 학습 → 빈 시간 자동 제안, 오늘 재계획, 미분류 일정 AI 분류
- Sparkle 자동 업데이트, 서명 + 공증 완료
- 오픈소스 (MIT), 무료

### 타겟 유저

주 타겟: 한국 개발자·프로덕트 매니저·디자이너 (macOS 사용)
부 타겟: 글로벌 productivity 관심 유저

### 요구 디자인 수준

**Raycast / Linear / Arc / Notion** 수준의 modern SaaS 랜딩.
투박한 wireframe이 아니라 **프로덕션급 완성도**:
- 세련된 타이포그래피 (Inter 또는 system-ui)
- 부드러운 그라데이션 + 미묘한 텍스처
- hover micro-interaction (CSS transform + transition)
- 다크 모드 기본 (#0b0b0f 톤)
- accent 색: `#7DD3FC` (하늘색) → `#6366F1` (인디고) 그라데이션
- 섹션 간 여유로운 여백 (vertical rhythm)
- mobile responsive

### 필수 섹션 (순서대로)

1. **Hero**
   - 큰 타이틀: "Your calendar, that remembers you."
   - subtitle: Hermes 장기 기억 언급 (한 줄)
   - CTA 버튼 2개: **Download .dmg** (primary) + **View on GitHub** (ghost)
   - 버튼 아래 미세 텍스트: "macOS 14+ · Universal · Signed & Notarized · Free"
   - 우측 또는 아래: 앱 스크린샷 mockup (실제 이미지는 placeholder로 `<img src="hero.png">`)

2. **"Why Calen"** — 3열 feature grid
   - 🧠 **Learns your patterns** — Hermes 장기 기억이 선호 시간·블록 길이·피로 패턴을 기억
   - ✨ **Plans with you** — "오늘 다시 짜기" · "빈 시간 채우기" · "미분류 자동 분류"
   - 🔗 **Connects everything** — Google Calendar + Apple Calendar + Todo + AI 하나로

3. **Deep dive** — 큰 feature 2~3개를 좌우 교차 레이아웃 (text ↔ screenshot)
   - Hermes Memory 시스템
   - AI Planning Actions
   - 카테고리 자동 분류

4. **How it works** — 3단계
   1. Install via Homebrew or .dmg
   2. Connect Google Calendar (OAuth)
   3. Chat with AI + Hermes learns

5. **Pricing** — 간결하게 "Free · Open source · MIT" 단일 카드

6. **Download CTA** (반복)
   - Hero와 같은 버튼 2개
   - 버튼 위에 현재 버전 (JS로 GitHub API fetch해 동적 표시)

7. **Footer**
   - GitHub / Privacy Policy / OAuth Verification / Homebrew Tap 링크
   - "Made by Oyeong Gwon · MIT Licensed"

### 기술 제약

- **단일 `index.html` 파일**만 (external CSS/JS 최소화)
- GitHub Pages static hosting (Jekyll 없이 — `.nojekyll` 이미 있음)
- external font는 `system-ui`로 대체 가능
- JS: **GitHub Releases API** 호출해 최신 asset URL 동적 연결 (아래 JS 스니펫 포함)
- 외부 의존성 없음 (CDN도 최소)

```js
// 필수 JS — Download 버튼 최신 asset으로 자동 연결
fetch('https://api.github.com/repos/oyeong011/Planit/releases/latest')
  .then(r => r.ok ? r.json() : Promise.reject())
  .then(release => {
    const dmg = release.assets.find(a => a.name.endsWith('.dmg'));
    const zip = release.assets.find(a => a.name.endsWith('.zip'));
    if (dmg) document.querySelectorAll('[data-download-dmg]').forEach(el => el.href = dmg.browser_download_url);
    if (zip) document.querySelectorAll('[data-download-zip]').forEach(el => el.href = zip.browser_download_url);
    document.querySelectorAll('[data-version]').forEach(el => el.textContent = release.tag_name);
  })
  .catch(() => {});
```

### 카피라이팅 톤

- **영어 주요 + 한국어 badge** 병행 (예: "한국어 지원" 뱃지)
- **"Assistant"보다 "Companion"** 선호 — Hermes 철학(동행자) 반영
- 과장 최소화 — "AI powered" 남발 금지. 대신 구체적 기능 명시

### 참고 URL (디자인 영감)
- raycast.com
- linear.app
- arc.net
- cron.com (now notion calendar)

### 완료 기준

한 번 Claude에 넣으면 **바로 `docs/index.html`에 덮어쓸 수 있는 완성된 HTML** 반환.
- `<!DOCTYPE html>` 부터 `</html>`까지 풀 코드
- CSS는 `<style>` 인라인
- JS는 `<script>` 인라인
- 실제 스크린샷은 `hero.png`, `memory.png` 등 placeholder 경로로 참조
- 세련되고 프로덕션급이어야 함

**지금 시작해 주세요.**

---

## 프롬프트 끝

### 사용 방법

1. 위 프롬프트를 그대로 Claude에 복사-붙여넣기
2. Claude가 반환한 HTML을 `docs/index.html`로 저장
3. 필요 시 스크린샷 `docs/hero.png`, `docs/memory.png` 등 준비
4. `git add docs/ && git commit -m "feat(site): 랜딩 리디자인" && git push origin main`
5. GitHub Pages 빌드 완료되면 사이트 갱신

### 팁

- Claude에 프롬프트 넣고 응답이 길면 "continue"로 이어 받기
- 한 번에 완성도 80% — 세부 텍스트는 직접 다듬기
- 스크린샷은 macOS에서 `⌘⇧5`로 앱 캡처 (메뉴바 제외)
