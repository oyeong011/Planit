# macOS Calen UI → iOS 적용 마스터 플랜

> 12개 병렬 codex(gpt-5.4 high) 분석 합의. `macOS 코드는 읽기만 — 수정 금지`.
> 로그 원본: `/tmp/calen-codex-parallel/*.log` (NN-영역명.log 12개)

## 우선순위 요약 (Quick Win → v0.1.1 → v0.2+)

| 티어 | 항목 | 근거 (log) |
|---|---|---|
| 🟢 Quick Win | DailyDetailCard 시간 rail + 얇은 색상 바 + 카테고리 pill | 03-daily-detail |
| 🟢 Quick Win | CRUDErrorInlineNotice → EventEditSheet.errorBanner로 치환 | 10-error-ux |
| 🟢 Quick Win | onboardingDone=true 스킵 정책 통일 | 08-onboarding |
| 🟡 v0.1.1 | ChatView 탭 — `AIService` published state + `ChatBubble` 재사용 | 04-chat-ui |
| 🟡 v0.1.1 | SuggestionPreviewSheet → 오늘 재계획 diff UX | 09-suggestion-preview |
| 🟡 v0.1.1 | SettingsView 섹션화 (7개) | 06-settings-ui |
| 🟡 v0.1.1 | Review Tab — 3탭(일/주/월) + 완료율 카드 + 잔디맵 | 05-review-ui |
| 🔵 v0.2 | AppearanceService Mode enum Shared 승격 | 07-theme-system |
| 🔵 v0.2 | LoginView "건너뛰기" CTA 패턴 | 12-login-ux |
| 🔵 v0.2 | CalendarGrid TabView(.page) 3슬롯 월 pager | 02-calendar-grid |

---

## 1. MainView 3단 → iPhone 1단 (01)

**원본 구조** (macOS, 1320×860 고정):
```
[leftPanel 280pt][CalendarGridView ∞][DailyDetail 330pt]
```

**iOS 대응**:
- `CalendarGridView` 하나를 `NavigationStack`에 배치, `.frame(maxWidth: .infinity)` 유연.
- `DailyDetailView (330pt)` → **DayDetailSheet** (이미 완료).
- `leftPanel (chat/review/onboarding)`:
  - `chat` → iOS 탭 (v0.1.1) 또는 우상단 `bubble` 버튼 sheet.
  - `review` → iOS 탭 (v0.1.1) 또는 배너 유도.
  - `onboarding` → `.fullScreenCover` (첫 실행만).
- `Divider` 제거 — 한 화면 안에서는 섹션 구분만 가로 divider 최소 사용.

**수치 조정 (iPhone)**:
- 월 제목 28pt → **22~24pt**
- 그리드 외곽 패딩 **16pt**, 셀 간격 8~12pt
- DailyDetailRow `rowSlotHeight=58pt` 유지 OK (터치 타깃 충분)

## 2. CalendarGrid 월 이동 (02)

**권장**: `TabView(.page)` + 3슬롯 (이전/현재/다음 월). 좌우 스와이프 = 월 이동. 현 MonthGridView(v7)에 래퍼만 씌우면 됨.

**DayDetailSheet 가로 드래그 = 날짜 이동** 이미 구현(gesture). 유지.

## 3. DailyDetailCard — 시간 rail + 카드 (03) ⭐ Quick Win

**현 iOS DayDetailSheet EventCard**는 "색상 바 + 제목 + 시간 아이콘 + 위치". macOS는 **왼쪽 시간 rail(고정 폭)** + 오른쪽 카드. 이식 제안:

```
┌────────┬───────────────────────────┐
│ 09:00  │ ▎팀 스탠드업               │
│        │   10:00 · 본사 3층         │
│ 09:15  │                           │
├────────┼───────────────────────────┤
│ 10:00  │ ▎기획 리뷰       ✓ / …    │
```

- 좌측 시간 컬럼 56pt 고정 (monospacedDigit 13pt)
- 우측 카드: 3pt 색상 바 + 제목 15pt semibold + 카테고리 pill 9pt + 오른쪽 완료 버튼
- Event + Todo 통합 `DayItem` 리스트 (macOS 패턴 그대로)
- 완료/미완료 체크 버튼 오른쪽 (swipe-to-complete 대체)

## 4. ChatView (04) — v0.1.1 핵심

**재사용 목록**:
- `AIService: ObservableObject` 의 `@Published` 상태 (chatMessages, isLoading, provider, pendingActions, externalContextPreview, planningInProgress, planningProgressText, planningLastError)
- `ChatBubble` — 사용자/AI/toolCall 3-way 분기
- `ChatMessage`, `ChatAttachment`, `AIProvider` 도메인 모델
- Markdown → AttributedString 캐시 (assistant 메시지)
- planning action state machine (pending → approve/reject)

**교체**:
- `Process`/CLI 경로 → `ClaudeAPIClient` HTTP (Feature Architect 1.1 제안)
- `.platformControlBackground` → `Color(.secondarySystemBackground)`
- macOS 파일 선택/붙여넣기 UI → iOS `PhotosPicker` + `.fileImporter`

## 5. Review (05) — v0.1.1

**3탭**: 일간/주간/월간 상단 segmented picker.

**카드 우선순위** (상위 5):
1. 완료율 Progress Card (총/완료/rate)
2. 카테고리별 시간 bar chart (색상 segment)
3. 습관 streak card (최근 7일 도트)
4. 잔디맵 (30일 또는 365일)
5. SuggestionCard (AI 제안 + accept/ignore)

**모든 카드**: `themeService.current.cardTint` 오버레이 패턴 유지. iOS에서도 CalendarThemeService Shared 포팅 후 적용.

## 6. Settings (06) — iPhone 섹션 7개

macOS 8섹션 중 iPhone 적합:
1. **프로필** (이름, 아바타, 목표 level)
2. **AI** (Claude API 키, provider 선택 — v0.1.1)
3. **캘린더/계정** (Google 로그인, 다중 캘린더 토글 — v0.2)
4. **알림** (아침 브리핑, 저녁 리뷰 — 권한 요청 포함)
5. **외관** (AppearanceMode, cardTint 테마 picker)
6. **iCloud/데이터** (Hermes sync 토글, 데이터 초기화 — 독립 섹션으로 분리 중요)
7. **정보** (버전, GitHub, 라이선스)

iPad split에만 필요 (iPhone 제외): `AI 컨텍스트` 관리 (v1.0)

## 7. Theme system (07)

**Shared 승격 후보**:
- `AppearanceService.Mode` enum (system/light/dark)
- UserDefaults persistence 로직

**플랫폼 분리 유지**:
- `apply()` — macOS는 `NSApp.appearance`, iOS는 `UIApplication.windows[].overrideUserInterfaceStyle`

**CalendarThemeService**: `current.accent/paneTint/cardTint` 전체를 Shared로. iOS Views는 같은 API 사용.

## 8. Onboarding (08)

**스킵 정책 통일**: "이번엔 건너뛰기" 1버튼. 스킵해도 `onboardingDone=true` 저장 → 재실행 시 재진입 없음.

**iOS 3단계**:
1. 언어 확인 (기본 시스템)
2. Google 로그인 (또는 스킵)
3. 첫 목표 1개 입력 (또는 스킵)

## 9. SuggestionPreview (09) — v0.1.1

**원본 패턴**: `ChatView`의 "오늘 다시 짜기" 클릭 → `planningSuggestion` 세팅 → 같은 sheet 재사용 (diff preview + accept/reject + 배치 작업).

**iOS**: 정확히 동일 패턴. `SuggestionPreviewSheet`를 Shared로 이동하거나 iOS에 복사. accept → `EventRepository.update` 호출.

## 10. Error UX (10) ⭐ Quick Win

**iOS EventEditSheet.errorBanner** → **CRUDErrorInlineNotice** 스타일로 교체:
- 주황/red background + icon
- dismiss X 버튼
- "작업 실패 — 복원됨" 2줄 제한

**전역 에러 한 곳만**: `safeAreaInset(edge: .top)` 배너 또는 현 sheet scope 배너 중 택1. 중복 노출 금지.

## 11. UpdateBanner (11)

**iOS는 App Store 자동 업데이트 → 배너 불필요.**

**대안 활용**: `UpdateAvailableBanner` → 공용 `ServiceNoticeBanner`로 재설계:
- "Google 로그인 필요" / "iCloud Drive 꺼져 있음" / "새 iOS 버전에서 Face ID 등록" 등 액션 필요 고지
- 같은 레이아웃 (icon + 제목 + CTA + dismiss)

## 12. Login UX (12)

**공통 패턴**:
- 첫 화면은 **앱 가치 스크린** (제목 + 1줄 설명 + 브랜드 일러스트)과 **계정 연결 CTA**를 섹션 분리
- "나중에" / "로그인 없이 시작" 버튼 추가 (`skipGoogleAuth` 참조) — 기본 CTA 아래 작게

**iOS 적용**: 현 SettingsView의 로그인 행을 **첫 실행 전용 화면**으로 승격. 추후 Settings에서도 동일 호출.

---

## 실행 순서 (마일스톤)

### Milestone 1 — Quick Win (1~2일)
- [ ] Error Banner 통일 (CRUDErrorInlineNotice 패턴)
- [ ] DailyDetailCard 시간 rail 적용
- [ ] onboardingDone 스킵 정책 정리

### Milestone 2 — v0.1.1 (2~3주)
- [ ] ChatView 탭 + `ClaudeAPIClient`
- [ ] Review Tab 3탭 + 5개 카드
- [ ] Settings 7섹션 재구성
- [ ] SuggestionPreviewSheet 이식 + 오늘 재계획

### Milestone 3 — v0.2 (1~2주)
- [ ] AppearanceService Mode Shared 승격
- [ ] CalendarThemeService Shared 승격 + iOS 적용
- [ ] LoginView 가치 스크린
- [ ] CalendarGrid TabView(.page) 3슬롯 pager

---

## macOS 수정 금지 약속

본 문서의 모든 제안은 iOS 측 코드(`CaleniOS/Sources/**`, `Shared/Sources/CalenShared/**`)에서만 구현. macOS(`Planit/**`)는 **읽기 참조만** — 패턴/코드 스니펫 추출은 OK, 파일 수정 금지.
