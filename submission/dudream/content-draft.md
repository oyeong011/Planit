# 두드림 프로젝트 최종 제출 — 콘텐츠 초안

**제출 마감**: 2026-06-05(금)
**프로젝트**: Calen (Planit)
**팀장**: 권오영

---

## 1. 프로젝트명

> **Calen — 메뉴바에서 동작하는, 기억하는 AI 캘린더**

(부제 후보)
- 사용자 본인의 AI 구독으로 돌아가는 macOS 일정 관리 도구
- Google · Apple Calendar + Claude/Codex CLI를 하나의 팝오버에서

---

## 2. 개요 (배너용 2~3문장)

Calen은 macOS 메뉴바에서 Google Calendar · Apple Calendar · Reminders를 한 화면에 모아 보고, 사용자 본인이 이미 구독 중인 **Claude Code / Codex CLI**로 일정을 자동 제안받는 오픈소스 도구입니다.
별도 서버나 API 비용 없이 모든 데이터가 로컬에 머무르며, 메뉴바라는 가벼운 표면을 통해 *항상 켜져 있지만 방해하지 않는* AI 비서 경험을 제공합니다.

### 핵심 가치 (PPT용 bullet)
- **개발자 API 비용 $0** — 사용자 본인의 AI 구독을 그대로 활용
- **로컬 우선** — 일정·메모리·컨텍스트는 모두 기기에 저장 (Keychain + 마크다운)
- **기억하는 AI** — Hermes Agent로 세션 간 사용자 패턴을 누적 학습
- **플랫폼 연속성** — macOS → iOS/iPad 확장 로드맵 진행 중

---

## 3. 프로젝트 경과 (타임라인)

| 시기 | 마일스톤 |
|---|---|
| 2026.04 초 | MVP 출시 (v0.1) — Google Calendar 연동, 메뉴바 NSStatusItem + NSPopover UI |
| 2026.04 중순 | AI 채팅 기능 — Claude Code / Codex CLI 연동, 이미지·PDF 첨부 지원 |
| 2026.04 말 | SmartScheduler — 빈 슬롯 자동 탐색 및 Todo 자동 배치 |
| 2026.05 초 | Apple Calendar / Reminders EventKit 통합, 일간·주간 AI 리뷰 |
| 2026.05 중순 | v0.2.x 배포 — Homebrew tap (`brew install --cask calen-ai`), Sparkle 자동 업데이트, 코드 서명·노터라이즈 |
| 2026.05 말 | 랜딩 페이지 개편 + GitHub MIT 오픈소스 공개 |
| 진행 중 | **PRD v2.0** — Hermes Agent 통합(기억하는 AI), iOS/iPad 멀티플랫폼 확장, CloudKit 동기화 |

### 정량 성과 (현재 시점, 실측치)
- 오픈소스 공개 (MIT) — GitHub Releases · Homebrew Cask 배포
- 코드베이스: Swift Package, **24,875 LOC · 58 파일 · 32 Service 모듈** (AIService 1,905줄)
- 활동: **700+ commits** (2026.04 ~ 현재)
- 통합 캘린더: Google Calendar / Apple Calendar / Reminders **3개 소스**
- 지원: macOS 14+ Universal Binary (Apple Silicon + Intel)
- Google OAuth 인증 진행 중

---

## 4. 마무리 소감 (배너용 단문 + PPT용 장문)

### 배너용 (2~3문장)
"AI는 별도의 채팅창이 아니라, 사용자가 이미 신뢰하는 도구의 자연스러운 연장이어야 한다는 것을 배웠습니다. 사용자 구독으로 돌아가는 로컬 우선 아키텍처가 **비용·프라이버시·반응성**을 동시에 만족시킨다는 것을 실증했고, 14주 멀티플랫폼 확장 로드맵으로 다음 단계를 준비하고 있습니다."

### PPT용 (장문, 3 단락)
1. **배운 점 — 도구는 도구 옆에 있어야 한다.**
   메뉴바와 CLI는 개발자가 가장 가깝게 두는 표면입니다. 그 표면 위에 AI를 얹는 순간, 별도 앱을 띄울 마찰이 사라지고 "오늘 일정 정리해줘" 같은 짧은 요청이 일상에 녹아들었습니다. 별도 채팅 앱을 만드는 대신, 이미 있는 도구에 침투하는 전략의 힘을 직접 검증했습니다.

2. **느낀 점 — 개발자 비용 $0 모델의 가능성.**
   사용자 본인의 Claude Code · Codex CLI 구독을 그대로 활용하는 구조는, 제품 입장에서 API 비용을 0으로 만들고 사용자 입장에서는 별도 결제 없이 자기 구독의 가치를 확장시킵니다. 동시에 일정 데이터가 외부 서버로 나가지 않아 프라이버시 우려를 원천 차단합니다. 이 "구독 위에 얹는" 모델은 다른 개발자 도구로도 확장될 수 있다는 확신을 얻었습니다.

3. **다음 단계 — 기억하는 AI, 그리고 모바일.**
   Hermes Agent 로컬 메모리 레이어를 통합해 "처음 만나는 것처럼" 대화가 리셋되는 문제를 해소하고, iOS/iPad에 Mac Bridge·CloudKit 동기화로 같은 AI 경험을 확장합니다. 두드림에서 검증한 가설을 바탕으로 14주 로드맵 (M1: Hermes, M2: iOS, M3: iPad+동기화, M4: 배포)을 가동 중입니다.

---

## 5. 사용할 이미지 (배너 + PPT)

| 파일 | 용도 |
|---|---|
| `docs/hero.png` | 메인 — 캘린더 그리드 + 사이드 패널 풀샷 |
| `docs/chat.png` | AI 채팅 + 캘린더 통합 화면 |
| `docs/review.png` | 일간/주간 리뷰 화면 |
| `calen-landing-desktop.png` | 랜딩 페이지 데스크탑 뷰 |
| `calen-landing-mobile.png` | 랜딩 페이지 모바일 뷰 |
| `docs/calen-product-mock.png` | 제품 목업 |

→ **배너에는 `hero.png` + `chat.png` 2장 배치** (양식 요건 충족)
→ **PPT에는 6장 모두 활용**
