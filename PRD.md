# Calen PRD — v2.0
## Hermes Agent 통합 + 멀티플랫폼 확장

> 작성일: 2026-04-17  
> 작성자: 권오영  
> 버전: 2.0 (Hermes 통합 + iOS/iPad 확장)

---

## 1. 제품 철학

**"사용자의 구독으로 돌아가는, 기억하는 AI 캘린더"**

| 원칙 | 의미 |
|------|------|
| 개발자 API 비용 $0 | 사용자 본인의 Claude Code / Codex 구독으로 LLM 실행 |
| 로컬 우선 | 일정·메모리·컨텍스트는 사용자 기기에 저장 |
| 기억하는 AI | Hermes Agent가 세션 간 사용자 패턴을 누적 학습 |
| 플랫폼 연속성 | macOS → iPhone → iPad, 어디서도 같은 AI 경험 |

---

## 2. 현재 상태 (v1.x)

### 잘 되어 있는 것
- macOS 메뉴바 앱 (`NSStatusItem` + `NSPopover`) 완성
- Google Calendar CRUD + Apple Calendar/Reminders 양방향 동기화
- Claude Code / Codex CLI 기반 AI 채팅 (`AIService.swift` 1470줄)
- `UserContextService` — 마크다운 기반 사용자 컨텍스트 누적
- `SmartSchedulerService` — 빈 슬롯 자동 탐색
- 보안 검증 (eventId 화이트리스트, 배치 안전장치)

### 문제점
| 문제 | 영향 |
|------|------|
| `AIService`의 `Process` 기반 CLI 호출 | iOS/iPad에서 실행 불가 |
| 세션 재시작 시 컨텍스트 리셋 | AI가 사용자를 "처음 만나는 것처럼" 대함 |
| 컨텍스트가 마크다운 파일에만 저장 | 검색·구조화 불가 |
| `Package.swift`가 macOS 전용 | iOS 빌드 자체가 불가 |
| UI 고정 크기 (1320×860) | 모바일 레이아웃 불가 |

---

## 3. v2.0 목표

### 3.1 Hermes Agent 통합 — 기억하는 AI

**현재 문제**: `UserContextService`가 마크다운 파일에 컨텍스트를 저장하지만  
— 비구조적, 검색 불가, 세션 간 연속성이 약함

**해결**: Hermes Agent를 로컬 메모리·오케스트레이션 레이어로 도입

```
[기존]
ChatView → AIService → Claude CLI → 응답
                                 ↓
                    UserContextService (마크다운 파일, 약한 기억)

[v2.0]
ChatView → HermesMemoryService → Hermes Agent (SQLite, 강한 기억)
                                       ↓ 메모리 조회 후
                              Claude CLI / Codex CLI (사용자 구독)
                                       ↓
                              응답 → 메모리 업데이트
```

**Hermes가 기억하는 것**
- 사용자 일정 패턴 ("월요일 아침은 항상 바쁨")
- 반복 요청 선호도 ("회의는 2시간 블록으로")
- 목표와 진행 상황
- 캘린더 카테고리별 우선순위
- 자주 쓰는 표현/단축 명령

### 3.2 멀티플랫폼 아키텍처

**핵심 제약**: iOS/iPad는 CLI(`Process`) 호출 불가  
**해결 전략**: 플랫폼별 AI 백엔드 분기 + 공유 메모리 레이어

```
┌─────────────────────────────────────────────────────────┐
│              CalenCore (공유 모듈)                        │
│   Models / ViewModels / Services (플랫폼 무관 로직)       │
└─────────────────────────────────────────────────────────┘
          ↓                            ↓
┌──────────────────┐         ┌──────────────────────────┐
│   macOS          │         │   iOS / iPad             │
│                  │         │                          │
│  NSStatusItem    │         │  TabView (iPhone)        │
│  NSPopover       │         │  SplitView (iPad)        │
│                  │         │                          │
│  AI: CLI 호출    │         │  AI: Mac Bridge OR       │
│  (Claude/Codex)  │         │  Anthropic SDK (API 키)  │
│                  │         │                          │
│  Hermes: 로컬    │         │  Hermes: iCloud 동기화   │
│  (풀 기능)        │         │  (메모리 동기화)          │
└──────────────────┘         └──────────────────────────┘
          ↓                            ↓
┌─────────────────────────────────────────────────────────┐
│              iCloud / CloudKit                           │
│   메모리 DB / 일정 캐시 / 사용자 컨텍스트 동기화            │
└─────────────────────────────────────────────────────────┘
```

---

## 4. 기능 요구사항

### 4.1 Hermes 통합 (P0 — 핵심)

#### FR-H1: HermesMemoryService
```swift
// 새 서비스: Services/HermesMemoryService.swift
@MainActor final class HermesMemoryService: ObservableObject {
    // Hermes Agent CLI 또는 HTTP API 연결
    // SQLite + FTS5 기반 메모리 저장
    
    func remember(_ fact: String, category: MemoryCategory) async
    func recall(context: String) async -> [Memory]
    func buildContextForAI() async -> String  // AI 프롬프트 주입용
    func updateFromConversation(_ messages: [ChatMessage]) async
}
```

#### FR-H2: 메모리 카테고리
| 카테고리 | 예시 |
|---------|------|
| `schedule_pattern` | "월요일 오전은 집중 작업 시간" |
| `preference` | "회의는 오후 2~5시 선호" |
| `goal` | "5월까지 앱 출시 목표" |
| `recurring` | "매주 화요일 팀 스탠드업" |
| `shortcut` | "점심 = 12:30-13:30" |

#### FR-H3: Hermes 설치 플로우 (brew install calen)
```bash
brew install calen
# 자동으로:
# 1. Calen.app 설치
# 2. hermes-agent 로컬 인스턴스 설치 (launchd 서비스)
# 3. calendar skill 등록
# 4. Google OAuth 안내
```

#### FR-H4: AI 라우팅 (macOS)
```
사용자 메시지
    ↓
HermesMemoryService.recall(context: 메시지)
    ↓ 관련 기억 조회
기존 AIService.buildSystemPrompt() + 기억 주입
    ↓
Claude CLI / Codex CLI (사용자 구독)
    ↓
응답
    ↓
HermesMemoryService.updateFromConversation()
```

---

### 4.2 iOS 앱 (P0)

#### FR-I1: AI 백엔드 전략

**옵션 A — Mac Bridge** (권장, 초기 버전)
```
iPhone Calen
    ↓ 로컬 네트워크 (Bonjour)
Mac Calen (백그라운드 실행)
    ↓
Hermes + Claude CLI
```
- 장점: 사용자 구독 그대로 활용, 추가 비용 $0
- 단점: Mac이 온라인이어야 함

**옵션 B — API 모드** (Mac 없을 때 fallback)
```
iPhone Calen
    ↓
사용자가 입력한 Anthropic API 키
    ↓
Anthropic SDK (REST)
```
- 장점: 독립적 동작
- 단점: 사용자가 API 키 필요 (별도 비용 발생 가능)

**구현**: 첫 실행 시 선택, 언제든 전환 가능

#### FR-I2: iOS UI 구조

**iPhone — TabView**
```
Tab 1: 캘린더
  - 월간/주간/일간 뷰 (적응형)
  - 일정 탭으로 상세 표시

Tab 2: AI 채팅
  - ChatView (공유 컴포넌트)
  - 첨부: 사진 라이브러리 + 파일 앱

Tab 3: 목표 & 리뷰
  - GoalView + ReviewView

Tab 4: 설정
  - AI 백엔드 선택
  - Google 계정
  - Hermes 메모리 설정
```

**iPad — NavigationSplitView**
```
사이드바        | 중앙 캘린더      | 디테일
- 캘린더 탐색   | CalendarGridView | DailyDetailView
- AI 채팅      |                  | ChatView (슬라이드 오버)
- 목표         |                  |
```

#### FR-I3: 플랫폼 조건부 컴파일 전략
```swift
// Package.swift
platforms: [.macOS(.v14), .iOS(.v17), .iPadOS(.v17)]

targets: [
    .target(name: "CalenCore"),      // 공유: Models, ViewModels, Services
    .executableTarget(name: "CalenMac",  
                      dependencies: ["CalenCore"]),   // macOS 전용
    .executableTarget(name: "CalenMobile",
                      dependencies: ["CalenCore"]),   // iOS/iPad 전용
]
```

---

### 4.3 iPad 앱 (P1)

#### FR-P1: Split View 레이아웃
- 사이드바 (최소 250pt): 날짜 탐색, 카테고리
- 주 화면: CalendarGridView (반응형)
- 디테일 (최대 330pt): DailyDetailView / ChatView 전환

#### FR-P2: Slide Over 지원
- ChatView를 Slide Over로 오버레이
- 캘린더 보면서 AI에게 질문 가능

#### FR-P3: Apple Pencil 지원
- 손글씨로 할일 추가
- 드래그로 일정 이동

---

### 4.4 크로스플랫폼 동기화 (P0)

#### FR-S1: iCloud 동기화 레이어
```
macOS Calen ←→ CloudKit ←→ iOS/iPad Calen
                  ↕
           Hermes 메모리 (압축 동기화)
           사용자 컨텍스트 (마크다운)
           카테고리 설정
           목표 데이터
```

#### FR-S2: 동기화 항목
| 항목 | 방법 | 우선순위 |
|------|------|---------|
| 할일 (TodoItem) | CloudKit | P0 |
| 카테고리 | CloudKit | P0 |
| 목표 (GoalModels) | CloudKit | P0 |
| Hermes 메모리 | CloudKit (압축) | P0 |
| 사용자 컨텍스트 | iCloud Documents | P1 |
| AI 채팅 히스토리 | CloudKit (선택적) | P2 |

#### FR-S3: 충돌 해결
- 타임스탬프 기반 최신 우선
- 삭제는 soft delete (30일 보관)

---

### 4.5 Homebrew 배포 (P1)

#### FR-B1: Formula 구조
```ruby
# brew tap oyyy/calen
# brew install calen

class Calen < Formula
  desc "AI-powered calendar with persistent memory"
  
  depends_on "hermes-agent"  # NousResearch/hermes-agent
  
  def install
    # Calen.app → /Applications
    # Hermes calendar skill 등록
    # launchd plist 생성
  end
  
  service do
    run [opt_bin/"hermes", "serve", "--skill", "calendar"]
    keep_alive true
    log_path var/"log/hermes-calen.log"
  end
  
  def caveats
    <<~EOS
      Calen requires Claude Code or Codex CLI:
        brew install claude-code
        brew install codex
      
      First launch: Google Calendar login required
    EOS
  end
end
```

#### FR-B2: 설치 후 온보딩
```
1. AI 백엔드 감지
   → claude 발견: "Claude Code 연결됨 ✓"
   → codex 발견: "Codex 연결됨 ✓"
   → 둘 다 없음: 설치 가이드 표시

2. Google Calendar 로그인

3. Hermes 메모리 초기화
   → "처음 사용하시는군요. 몇 가지 알려주세요..."
   → 기본 근무 시간, 선호 언어 설정

4. 완료 → 메뉴바 아이콘 표시
```

---

## 5. 기술 스택

### 5.1 현재 → v2.0 변경 사항

| 항목 | 현재 | v2.0 |
|------|------|-------|
| 메모리 | UserContextService (마크다운) | + HermesMemoryService (SQLite) |
| AI 백엔드 (macOS) | Claude/Codex CLI | 동일 (유지) |
| AI 백엔드 (iOS) | 없음 | Mac Bridge 또는 Anthropic SDK |
| 동기화 | 없음 | CloudKit |
| iOS 진입점 | 스텁만 있음 | TabView 완성 |
| iPad 지원 | 없음 | NavigationSplitView |
| 배포 | 수동 | brew install calen |
| Package.swift | macOS 전용 | 멀티플랫폼 |

### 5.2 새로 추가할 의존성

| 패키지 | 용도 | 플랫폼 |
|--------|------|--------|
| CloudKit (내장) | 동기화 | 전체 |
| Hermes Agent CLI | 메모리 레이어 | macOS |
| AnthropicSwiftSDK | iOS AI fallback | iOS/iPad |
| Network.framework (내장) | Mac Bridge | iOS/iPad |

---

## 6. 구현 로드맵

### Phase 1 — Hermes 메모리 통합 (macOS 우선) `4주`
```
Week 1:
  - HermesMemoryService 작성
  - Hermes Agent CLI 연동 (로컬 포트)
  - 기존 UserContextService → Hermes 마이그레이션

Week 2:
  - AI 라우팅 수정 (AIService에 기억 주입)
  - 메모리 카테고리 분류기 구현
  - brew tap oyyy/calen Formula 초안

Week 3-4:
  - Hermes 메모리 품질 개선
  - 테스트 (기억 정확도, 세션 연속성)
  - 온보딩 플로우 완성
```

### Phase 2 — Package 구조 개편 + iOS 기반 `4주`
```
Week 5-6:
  - Package.swift: CalenCore 분리
  - PlanitApp.swift: iOS 진입점 완성 (TabView)
  - AIService: #if os(macOS) 분기 완성
  - 파일 저장소: AppGroup 마이그레이션

Week 7-8:
  - iPhone UI: CalendarGridView 반응형
  - ChatView: iOS 적응 (파일 피커 등)
  - Mac Bridge 프로토타입 (Bonjour + local HTTP)
  - iCloud 동기화 (CloudKit) 기반 작업
```

### Phase 3 — iPad + 동기화 완성 `4주`
```
Week 9-10:
  - iPad NavigationSplitView
  - Apple Pencil 기본 지원
  - CloudKit 동기화 완성 (TodoItem, Goal, 카테고리)

Week 11-12:
  - Hermes 메모리 iCloud 동기화
  - 충돌 해결 로직
  - 전체 플랫폼 E2E 테스트
```

### Phase 4 — 배포 `2주`
```
Week 13-14:
  - brew Formula 완성
  - App Store 준비 (iOS/iPad)
  - TestFlight 배포
  - 성능 최적화 (메모리 캐시, 동기화 빈도)
```

---

## 7. 플랫폼별 AI 경험 비교

| 시나리오 | macOS | iPhone (Mac Bridge) | iPhone (API 모드) | iPad |
|---------|-------|---------------------|------------------|------|
| 기억 지속 | ✅ Hermes 풀 기능 | ✅ Mac의 Hermes 활용 | ✅ iCloud 동기화 | ✅ |
| 비용 | $0 | $0 | API 비용 발생 | $0 또는 API |
| 오프라인 | ✅ | ❌ (Mac 필요) | ✅ | 부분적 |
| 응답 속도 | 빠름 | Mac 네트워크 속도 | 빠름 | 빠름 |
| 기능 완성도 | 100% | 90% | 80% | 95% |

---

## 8. 중요 설계 결정 (ADR)

### ADR-1: iOS AI 백엔드 전략
**결정**: Mac Bridge 우선, API 모드 fallback  
**이유**: 사용자 구독 철학 유지. Mac 없는 사용자도 API 키로 접근 가능  
**트레이드오프**: Mac Bridge는 Mac이 온라인이어야 함 (제약)

### ADR-2: Hermes를 중간 레이어로 사용
**결정**: Hermes가 LLM이 아닌 메모리+오케스트레이션 담당  
**이유**: LLM은 사용자 구독(Claude/Codex)으로, Hermes는 기억과 라우팅만  
**트레이드오프**: Hermes 로컬 실행 필요 (brew 설치 복잡도 증가)

### ADR-3: CalenCore 공유 모듈 분리
**결정**: Models, ViewModels, 플랫폼 무관 Services를 CalenCore로 분리  
**이유**: iOS/iPad/macOS가 동일 비즈니스 로직 사용  
**트레이드오프**: 초기 리팩토링 비용 발생 (약 2주)

### ADR-4: CloudKit으로 동기화
**결정**: iCloud/CloudKit 사용  
**이유**: 별도 서버 없이 Apple 생태계 내에서 동기화  
**트레이드오프**: Android 지원 불가, 저장소 한계 존재

---

## 9. 비기능 요구사항

| 항목 | 목표 |
|------|------|
| AI 응답 시간 | < 15초 (p95) |
| 동기화 지연 | < 5초 (같은 Wi-Fi 환경) |
| Hermes 메모리 조회 | < 500ms |
| 앱 실행 시간 | < 1초 (macOS cold start) |
| 메모리 사용량 | < 150MB (macOS), < 80MB (iOS) |
| 오프라인 가용성 | Google 없이 로컬 할일 CRUD 가능 |

---

## 10. 마일스톤 요약

| 마일스톤 | 내용 | 기간 |
|---------|------|------|
| M1 | Hermes 메모리 통합 (macOS) | 4주 |
| M2 | iOS 기반 완성 + Mac Bridge | 4주 |
| M3 | iPad + CloudKit 동기화 | 4주 |
| M4 | 배포 (brew + App Store) | 2주 |
| **총계** | | **14주** |

---

*이 PRD는 개발 진행에 따라 업데이트됩니다.*
