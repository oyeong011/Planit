# Calen iOS — 모바일 디자인 시안 v0.4 (Figma 호주 시안 톤 반영)

> **v0.4 변경**: Figma 시안 (`figma.com/design/jKqpASj8RoniMSlGufQkfy/호주`) 분석 결과 반영.
> - 흰 배경 + Calen 시안 블루(`#2B8BDA`) + 파스텔 카드 4종 (블루/핑크/라벤더/크림)
> - 4탭 → **5탭 + 중앙 마이크 floating** (음성 입력 메인 액션)
> - 월간 그리드 → **주간 가로 strip + Today's Schedule 시간축**
> - **드라이브 점선 + 차 아이콘**으로 이동시간 시각화 (시안 핵심 패턴)
> - SAT 파랑 / SUN 빨강 (한국식)
> - 14 테마 시스템은 유지

> 대상: `Planit/CaleniOS/` (iOS 전용)
> 외부 디렉토리(특히 `Planit/Planit/` macOS, `Planit/Sources/Calen` 공유 macOS 코드)는 건드리지 않는다.
> macOS Calen이 **Source of Truth**, iOS는 CloudKit 실시간 구독으로 **읽기·로컬 편집** 중심.
> 작성일: 2026-04-27 / 검토자: 권오영

---

## 0. 디자인 원칙

| 원칙 | 의미 |
|------|------|
| **Apple-grade 시안 유지** | 등록된 시안의 톤(말끔한 컴팩트 캘린더, pill 탭바, 카드형 정보 영역) 그대로 |
| **Dynamic Type 100% 대응** | 모든 폰트는 `Font.TextStyle` 기반 토큰. 고정 `.system(size:)` 금지 |
| **Adaptive Layout** | iPhone 세로/가로, iPad 세로/가로, Split View 4종을 모두 깨지지 않게 |
| **CloudKit 실시간** | macOS에서 변경된 메모리/일정이 **5초 이내** iOS에 반영 (CKQuerySubscription) |
| **No data loss** | iOS 로컬 편집은 항상 SwiftData에 먼저 저장 후 CloudKit push (offline-first) |
| **Zero-touch others** | `Sources/Calen` macOS 타깃, `Planit/` 디렉토리 코드는 일체 수정 X |

---

## 1. 정보 구조 (IA)

```
RootView
└─ MainTabView (custom pill bar)
    ├─ [1] HomeTab        — 캘린더 + 오늘
    ├─ [2] ChatTab        — Hermes AI 채팅
    ├─ [3] ReviewTab      — 통계 / 회고
    └─ [4] SettingsTab    — 계정·테마·동기화
```

### iPad — 별도 디자인 (확정)

iPad는 iPhone 레이아웃을 확대한 것이 아니라 **iPad 전용 IA**를 사용한다.

```
NavigationSplitView (3-column on regular width)

┌────────────┬─────────────────────────┬────────────────┐
│ Sidebar    │ Content                  │ Inspector       │
│ 260~300pt  │ 가변 (flex)              │ 320~380pt       │
├────────────┼─────────────────────────┼────────────────┤
│ ◆ 오늘      │  ┌─────────────────┐    │ [선택 일정]     │
│ 📅 캘린더   │  │ 4월              │    │ 제목            │
│ ✓ 할일      │  │  ◐ 월 그리드      │    │ 시간            │
│ 💬 Hermes   │  │     ⋮             │    │ 위치/메모        │
│ 📈 리뷰     │  └─────────────────┘    │ [편집] [삭제]   │
│ ⚙ 설정     │  ┌─────────────────┐    │                 │
│            │  │ 시간 그리드      │    │ ─ AI 인사이트  │
│ — 캘린더 — │  │ 09 ▮▮▮ 스탠드업 │    │ Hermes 한 줄   │
│ ☐ 개인     │  │ 14 ▮ 데모         │    │                 │
│ ☐ 업무     │  │  ⋮                │    │                 │
│ ☐ Google   │  └─────────────────┘    │                 │
└────────────┴─────────────────────────┴────────────────┘
```

- **Sidebar**: 탭 + 캘린더 카테고리 토글 (Apple Calendar.app 스타일)
- **Content**: 월 + 주 시간 그리드를 동시에 (수직 split). 선택일을 두 뷰가 공유
- **Inspector** (3rd column):
  - 일정 선택 시 → 상세 + 인라인 편집
  - Hermes 채팅 선택 시 → 풀 채팅 스레드 (Slide Over 아님, 항상 옆에)
  - 미선택 시 → 오늘의 AI 인사이트 1줄 + 빠른 추가 입력

- **Apple Pencil**:
  - 시간 그리드에 펜 스트로크로 일정 블록 그리기
  - 빈 슬롯 길게 그어 시작/종료 시간 자동 결정
  - 손글씨 → Live Text → 일정 제목으로 OCR 인입
- **Slide Over**: ChatTab을 Slide Over로도 띄울 수 있도록 toolbar 단축
- **Compact iPad** (Split View 1/3 등): NavigationStack으로 자동 전환 (`horizontalSizeClass == .compact`)

**iPad 가로/세로 둘 다**: SplitView 3-column 기본, 세로에서 inspector 자동 collapse

---

## 2. 디자인 토큰

### 2.1 컬러 — 등록 시안 14 테마 (확정)

각 테마는 `primary / secondary / accent / eventTint / bgOverlay` 5색을 가진다.
`iOSThemeService.current.{primary|secondary|accent|eventTint|bgOverlay}` 환경 주입으로 접근. **하드코딩 RGB 금지**.

| # | id | name | primary | secondary | accent | eventTint | bgOverlay |
|---|------|------|---------|-----------|--------|-----------|-----------|
| 1 | classic | Classic | `#3F5EFB` | `#6D7A99` | `#7C3AED` | `#3366CC` | `#EAF0FF` |
| 2 | ocean | Ocean | `#006D77` | `#4B7F86` | `#00818A` | `#0077B6` | `#DDF5F7` |
| 3 | sunset | Sunset | `#B54708` | `#8A5A44` | `#C2410C` | `#D97706` | `#FFF1E6` |
| 4 | forest | Forest | `#207A4D` | `#52665A` | `#2F855A` | `#3A7D44` | `#E7F5EC` |
| 5 | mono | Mono | `#404040` | `#737373` | `#525252` | `#595959` | `#F0F0F0` |
| 6 | sakura | Sakura | `#A7355E` | `#8A6473` | `#BE185D` | `#DB2777` | `#FCE7F3` |
| 7 | pantone-classic-blue | Pantone Classic Blue | `#0F4C81` | `#496982` | `#1D5F95` | `#0D5C9B` | `#E3EEF7` |
| 8 | pantone-illuminating | Pantone Illuminating | `#F5DF4D` | `#8A7A28` | `#7A5F00` | `#9A6B00` | `#FFF7C2` |
| 9 | pantone-ultimate-gray | Pantone Ultimate Gray | `#939597` | `#62666A` | `#555A60` | `#6A6D70` | `#EFEFEF` |
| 10 | pantone-very-peri | Pantone Very Peri | `#6667AB` | `#4D4C7D` | `#5454A6` | `#5A5BC4` | `#ECECFA` |
| 11 | pantone-viva-magenta | Pantone Viva Magenta | `#BB2649` | `#7B3044` | `#A2143A` | `#C32148` | `#FBE7ED` |
| 12 | pantone-peach-fuzz | Pantone Peach Fuzz | `#FFBE98` | `#A65F3B` | `#B85C38` | `#C65D2E` | `#FFF0E8` |
| 13 | pantone-mocha-mousse | Pantone Mocha Mousse | `#A47864` | `#6E5248` | `#7B4B3B` | `#8A5B4A` | `#F3E8E1` |
| 14 | pantone-cloud-dancer | Pantone Cloud Dancer | `#F0EEE9` | `#8B8378` | `#5F5A52` | `#7D756B` | `#F8F6F0` |

**다크 모드**: 각 테마는 light/dark 별도 cooked 토큰을 갖는다. 기본 규칙:
- `primary`/`accent`는 동일 (Brand 인지 일관성)
- `bgOverlay`는 다크에선 어두운 카운터파트로 자동 매핑 (예: `#EAF0FF` → `#1A2545`)
- `eventTint`는 다크 가독성 위해 +12% lightness 보정

**시스템 기본 토큰** (테마 무관):
- `surface.bg` = `bgOverlay` (light) / dark counterpart
- `surface.elevated` = `#FFFFFF` / `#1A1C20`
- `text.primary` = `#1B1C1F` / `#F2F3F6`
- `text.secondary` = `#6B7280` / `#9CA3AF`
- `divider` = `#E5E7EB` / `#2A2D33`

### 2.2 타이포 (Dynamic Type)

| Token | TextStyle | weight | 사용처 |
|-------|-----------|--------|--------|
| `display` | `.largeTitle` | .bold | 월/연 헤더 |
| `title` | `.title2` | .semibold | 카드 제목 |
| `subtitle` | `.headline` | .semibold | 섹션 헤더 |
| `body` | `.body` | .regular | 일반 본문 |
| `bodyEmph` | `.body` | .medium | 강조 본문 |
| `caption` | `.caption` | .regular | 시간/메타 |
| `mono` | `.callout` (`.monospacedDigit()`) | .medium | 시간 숫자 |

→ 모든 라벨은 `.font(Theme.font(.body))` 식으로 토큰 호출. `.system(size:)` 신규 사용 **금지**.
→ `@ScaledMetric` 으로 아이콘 크기/간격까지 스케일링.

### 2.3 간격 / 코너

```
spacing: 4 / 8 / 12 / 16 / 20 / 24 / 32
radius:  6 (chip) / 12 (card) / 16 (sheet) / 32 (tabbar pill)
shadow:  0 1 2 / 4% (card) | 0 8 24 / 8% (floating)
```

### 2.4 Iconography

- SF Symbols만 사용. `.symbolRenderingMode(.hierarchical)` 기본.
- 탭바 아이콘은 `.imageScale(.medium)` + `@ScaledMetric var iconSize: CGFloat = 22`.

---

## 3. 핵심 화면 시안

### 3.1 HomeTab — 캘린더

```
┌─────────────────────────────────┐
│  ←  2026년 4월  →     [오늘 ●]  │  ← Header (display + nav)
├─────────────────────────────────┤
│  일 월 화 수 목 금 토            │  ← 요일 strip (caption)
│  · · 1 2 3 4 5                  │  ← MonthGrid (TimelinesLayout 7-col)
│  6 7 8 9 10 11 12               │     · 오늘 = brand circle
│  13 14 15 ◉ 17 18 19            │     · 점 = 일정 dot (max 3, +N)
│  20 21 22 23 24 25 26           │
│  27 28 29 30 · · ·              │
├─────────────────────────────────┤
│  ▼ 4월 16일 (목)                 │  ← 선택일 panel (snap)
│  ┌───────────────────────────┐  │
│  │ 09:00  스탠드업           │  │  ← 이벤트 카드 (color bar)
│  │ 14:30  Hermes 데모        │  │
│  │ +할일 3                   │  │
│  └───────────────────────────┘  │
│  [+ 일정 추가]                  │  ← FAB는 우하단 floating
└─────────────────────────────────┘
        [Home] Chat Review Settings  ← Pill TabBar (90pt safe)
```

- 가로 스와이프로 월 이동 (`TabView(.page)`).
- iPad regular: 좌측 월 그리드 + 우측 일자 리스트 2단.
- 길게 누르면 `WeekTimeGridSheet` (드래그/리사이즈로 일정 편집).

### 3.2 ChatTab — Hermes AI 채팅

```
┌─────────────────────────────────┐
│  Hermes        🧠 12 facts      │  ← title + 메모리 카운터
├─────────────────────────────────┤
│             "어제 일정 어땠어?"  │  ← user bubble (right)
│  ┌───────────────────────────┐  │
│  │ 4건 완료, 2건 미완 …       │  │  ← assistant bubble (left)
│  │ [재계획 보기]              │  │     · 추천 액션 칩
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│ [📎] [메시지 입력……]    [전송]  │  ← Input bar (safeArea bottom)
└─────────────────────────────────┘
```

- 스트리밍 토큰 표시(점 3개 → 텍스트 swap).
- 첨부: PhotosPicker + DocumentPicker.
- macOS Hermes의 메모리 변경이 CloudKit으로 들어오면 헤더 카운터 라이브 업데이트.

### 3.3 ReviewTab — 통계 / 회고

```
[일][주][월]  ← Picker
┌────────────┐  ┌────────────┐
│ 완료율 78% │  │ 카테고리시간│  ← 2-col grid (iPhone)
│ ▓▓▓▓░░░░░ │  │ 도넛차트    │     iPad는 4-col
└────────────┘  └────────────┘
┌────────────┐  ┌────────────┐
│ 연속 12일  │  │ Grass 지도 │
│ 🔥         │  │ ▣▣▢▣▣▣▢   │
└────────────┘  └────────────┘
┌──────────────────────────────┐
│ AI 제안 · "이번 주는 회의가  │
│ 평균 대비 +40%, 집중시간 부족"│
└──────────────────────────────┘
```

### 3.4 SettingsTab — 카드형

```
[프로필 카드]   사진·이름·이메일·로그인 상태
[계정]          Google 계정 / Apple ID(iCloud)
[AI]            Claude API 키 (SecureField), 모델 선택
[동기화]        🟢 연결됨 · 마지막 5초 전 · [강제 새로고침]
[모양]          테마 8색 + Light/Dark/System
[언어]          한국어 / English
[알림]          일정 알림 / Hermes 인사이트
[정보]          버전, 빌드, 라이선스
```

### 3.5 위젯 — HomeScreen / Lock Screen / StandBy (확정)

#### HomeScreen
- `small`: 다음 1개 일정 + 시작까지 남은 시간
- `medium`: 다음 3개 일정 (시간/제목/카테고리 점)
- `large`: 오늘 전체 + 미니 도넛(완료율)

#### Lock Screen (iOS 16+)
- `accessoryInline` (시계 옆): "🟦 14:30 데모" 1줄
- `accessoryRectangular`: 다음 일정 2개 (시간 + 제목) + 카테고리 색바
- `accessoryCircular`: 다음 일정까지 분 단위 카운트다운 (`Gauge`)

#### StandBy (iOS 17+)
- 가로 와이드 위젯: 시계 옆에 다음 2개 일정 큰 글씨
- 야간 모드 자동 적색 (시스템)
- 16:9 풀 스타일은 `accessoryRectangular` 재사용

빈 상태 카피: `"오늘 일정 없음 · 산책 어때요?"` (Hermes 톤). Lock/StandBy에서는 `"비어 있어요"` 단축.

위젯 타임라인은 App Group `group.com.oy.planit`의 SwiftData 스냅샷 + `WidgetCenter.shared.reloadAllTimelines()` (CloudKit 동기화 직후 호출).

---

## 4. 화면 깨짐 방지 — Lint 규칙

| 규칙 | 위반 시 액션 |
|------|------|
| `.system(size:` 직접 호출 | swiftlint custom rule로 막고, 토큰으로 교체 |
| `.frame(width:height:)` 고정 (아이콘 제외) | `@ScaledMetric` 또는 `maxWidth: .infinity` 권장 |
| `.padding(.bottom, 90)` 같은 매직 넘버 | `Theme.tabBarHeight` 토큰 |
| 색상 RGB 하드코딩 | `Color("…")` asset 또는 `ThemeService` |
| `GeometryReader` 안에 또 `GeometryReader` | 1단으로 평탄화 |
| `.fixedSize()` 텍스트 | 멀티라인 허용해야 함, 사용 시 주석 필수 |
| HStack에 width 고정 + Spacer 없음 | 가로 overflow 가능 — 검수 필요 |

테스트 시뮬레이터:
- iPhone SE (3rd gen) 세로
- iPhone 15 Pro Max 세로
- iPad mini (6) 세로/가로
- iPad Pro 12.9 가로 (Split View 1/3 포함)
- Dynamic Type: xSmall / Large / AX1 / AX3 (4지점)

---

## 5. CloudKit 실시간 연동 흐름

```
[macOS Calen]
    HermesMemoryService.save(fact)
        │
        ▼  CKModifyRecordsOperation (private DB · default zone)
   iCloud.com.oy.planit  ←─── HermesMemoryFactV1 record
        │
        ▼  CKQuerySubscription (predicate: TRUEPREDICATE, fires on create/update)
   APNs silent push  ──────►  iOS Calen
                                │
                                ▼  fetchChanges (CKFetchRecordZoneChangesOperation)
                                ▼  SwiftData 로컬 캐시 갱신 (MemoryFactRecord)
                                ▼  @Query 재발행 → SwiftUI 자동 갱신
```

추가 도입:
- `CloudKitSyncCoordinator` (신규, iOS 전용) — 구독 등록·changeToken 영속화·재시도.
- 앱 foreground 시 `fetchAllChanges()` 1회 강제 — push 누락 대비.
- 충돌: macOS `updatedAt` 우선 (iOS는 read-mostly). 로컬 편집은 `pendingLocalChanges` 큐에 쌓고 push 성공 시 제거.

스키마는 v1 그대로 사용 + `CalendarEventV1` 신규 record 타입 추가:
```
CalendarEventV1
  eventId      String (PK)
  calendarId   String
  title        String
  start, end   Date
  location     String?
  notes        String?
  colorIndex   Int
  source       String  ("google" | "apple" | "local")
  updatedAt    Date
  deletedAt    Date?     ← soft delete
  origin       String    ← "macOS" | "iOS" (충돌 추적용)
  schemaVersion Int = 1
```

### 5.1 iOS CRUD (확정)

iOS는 일정에 대한 **풀 CRUD**를 지원한다 (read-only 아님):

| 동작 | 흐름 |
|------|------|
| Create | 로컬 SwiftData insert → CloudKit push → (필요시) Google Calendar API write |
| Read   | CloudKit subscription + GoogleCalendarRepository fetch (둘 다 유지) |
| Update | 로컬 update → CloudKit push → 원본 source(google/apple)에도 반영 |
| Delete | soft delete (deletedAt 설정) → 30일 후 hard purge |

충돌 해결: `updatedAt` 최신 우선. 동일 timestamp 시 `origin == "macOS"` 우선.

### 5.2 Google Calendar 직접 호출 유지 (확정)

기존 `GoogleCalendarRepository` (iOS) 유지. 두 경로 병행:
- **CloudKit 경로**: macOS와 iOS 간 즉시 동기화 (중복 방지용 dedup key = `eventId`)
- **Google API 경로**: iOS가 macOS 없이도 Google Calendar 직접 R/W 가능 (오프라인 macOS 시나리오)

`EventSource` enum으로 추적: `.cloudkit / .google / .apple / .local`

---

## 6. 빈/에러/로딩 상태

| 상태 | 카피 (한국어) | 액션 |
|------|---------------|------|
| 첫 실행 | "Apple ID로 iCloud에 로그인하면 macOS Calen과 자동 연결돼요" | [iCloud 설정 열기] |
| 동기화 끊김 | "오프라인이에요. 변경사항은 연결되면 보낼게요." | 토스트 + 노란 배지 |
| 오늘 빈 일정 | "오늘은 비어 있어요 ☕️ Hermes에게 계획 부탁해볼까요?" | [AI에게 묻기] |
| API 키 없음 (Chat) | "Claude API 키를 입력하면 채팅이 켜져요" | [설정으로 이동] |
| 위젯 데이터 없음 | "Calen을 한 번 열어 동기화해주세요" | — |

---

## 7. 구현 우선순위 (확정)

### Sprint A — 기반 (P0)
1. `Theme.swift` — 14 테마 5색 토큰 시스템 (light/dark cooked) + Dynamic Type 폰트 토큰
2. `CloudKitSyncCoordinator` — CKQuerySubscription + changeToken + offline 큐
3. `CalendarEventV1` CKRecord 스키마 + 양방향 sync (CRUD)
4. 화면 깨짐 점검 — iPhone SE/15 Pro Max + iPad mini/Pro12.9 4종 스냅샷 테스트

### Sprint B — iPad 전용 IA (P0)
5. `iPadRootView` — NavigationSplitView 3-column (Sidebar/Content/Inspector)
6. `horizontalSizeClass` 기반 iPhone/iPad 분기 (compact iPad는 NavigationStack)
7. Apple Pencil 시간 그리드 입력 (PencilKit)
8. iPad Sidebar의 캘린더 카테고리 토글

### Sprint C — 기능 완성 (P1)
9. iOS CRUD: 신규/편집/삭제 + Google Calendar API write 경로
10. 충돌 해결 로직 + soft delete + origin 추적
11. ChatTab Inspector 3-column 모드
12. Skeleton 로딩 / Toast / 오프라인 배너

### Sprint D — 위젯 3종 (P1)
13. HomeScreen `small/medium/large`
14. Lock Screen `inline/rectangular/circular`
15. StandBy 가로 와이드 위젯
16. `WidgetCenter.shared.reloadAllTimelines()` 동기화 hook

---

## 8. 확정된 결정 (사용자 답변 반영, 2026-04-27)

| # | 항목 | 결정 |
|---|------|------|
| 1 | 컬러 팔레트 | **14개 등록 테마, 각 5색 (primary/secondary/accent/eventTint/bgOverlay)** ← 위 표 |
| 2 | iPad 레이아웃 | **iPad 전용 IA — NavigationSplitView 3-column + Apple Pencil** |
| 3 | iOS CRUD 범위 | **풀 CRUD (신규/편집/삭제 모두 허용)** |
| 4 | Google Calendar | **CloudKit + Google API 직접 호출 둘 다 유지** |
| 5 | 위젯 범위 | **HomeScreen + Lock Screen + StandBy 3종 모두** |

---

## 9. 검증 루프 (codex-claude-loop)

```
[Claude] 구현 → [Codex] 리뷰 → [Claude] 반영 → 빌드/스냅샷 테스트 → 통과까지 반복
```

각 Sprint 완료마다:
1. `xcodebuild -scheme CaleniOS -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' build`
2. `xcodebuild -scheme CaleniOS -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)' build`
3. Dynamic Type 4지점(xS/L/AX1/AX3) 스냅샷 비교
4. Codex가 변경 diff 리뷰 → 화면 깨짐/접근성 위반 검출
5. 사용자 검토 → 승인 후 다음 Sprint

---

> 이 문서는 v0.3 (사용자 답변 반영본). 승인 후 Sprint A부터 구현 시작.
