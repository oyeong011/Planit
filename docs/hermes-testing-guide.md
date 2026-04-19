# Hermes 장기 기억 — 직접 테스트 가이드

## 0. 사전 준비

```bash
cd /Users/oy/Projects/Planit
git checkout feat/planning-memory-sidecar
```

### ⚠️ 실행은 반드시 `run-dev.sh` 사용

`swift run Calen`은 **절대 안 됩니다**.
UNUserNotificationCenter가 .app 번들을 요구하므로 크래시합니다.

```bash
./scripts/run-dev.sh
```

이 스크립트는:
1. 릴리즈 빌드
2. `/tmp/Calen.app` 번들 생성 (리소스, Sparkle 포함)
3. 개발 서명 적용 (있으면)
4. 기존 Calen 프로세스 종료 + 새 번들 실행

완료되면 메뉴바에 Calen 아이콘이 나타납니다. (기존 릴리즈 버전과 별개 프로세스)

---

## 1. 시나리오 A — 기억이 없는 상태 확인

1. 팝오버 열기 → 우측 하단 **⚙️ 설정** 클릭
2. 사이드바에서 **🧠 사용자 컨텍스트** 섹션 선택 (아이콘: `brain.head.profile`)
3. 가장 아래로 스크롤 → **🧠 Hermes 장기 기억** 카드 확인

**기대 결과:**
- "아직 기억된 패턴이 없습니다." 메시지 표시
- 힌트: "채팅에서 '아침에 집중이 잘 돼요'... 자동으로 학습합니다."
- Facts count = 0

---

## 2. 시나리오 B — 채팅에서 자동 학습

1. 설정 닫기 → 좌측 패널을 **채팅** 탭으로 전환
2. 아래 문장을 차례로 입력하고 AI 응답 대기:

```
아침에 집중이 잘 돼요
```

```
저녁엔 피곤해서 못해요
```

```
집중할 땐 90분 단위 블록이 좋아요
```

```
회의가 너무 많아서 지쳐요
```

```
빈 시간이 있으면 자동으로 추천해줘
```

**기대 결과:**
- 각 메시지 전송 후 약 1~2초 내에 백그라운드에서 fact 저장
- AI 응답은 평소처럼 도착

---

## 3. 시나리오 C — 기억 UI에서 확인

1. 설정 → 사용자 컨텍스트 → Hermes 카드로 돌아가기
2. **기대 결과 (예시):**

| 카테고리 | 키 | 값 | 신뢰도 |
|---|---|---|---|
| 선호 | preferredMorningWork | 오전 집중 선호 | 60% |
| 선호 | avoidsEveningWork | 저녁 작업 회피 | 65% |
| 선호 | preferredBlockLength | 90~120분 딥워크 블록 | 65% |
| 일정 패턴 | meetingFatigue | 회의 과밀 피로 | 70% |
| 선호 | wantsSlotSuggestions | 빈 시간 자동 제안 선호 | 75% |

- 각 행에 `x` 버튼으로 개별 삭제 가능
- 상단 **전체 삭제** 버튼으로 모두 삭제

---

## 4. 시나리오 D — 같은 키워드 반복 → 신뢰도 상승

1. 채팅에서 다시 입력:

```
아침에 집중이 잘 돼요 진짜로
```

2. 설정 → Hermes 카드에서 `preferredMorningWork` 확인

**기대 결과:**
- 값은 유지 (덮어쓰기 아님)
- 신뢰도가 60% → **65% 이상**으로 상승 (가중 평균 + 0.05 부스트)
- 시간 표시가 "방금 전"으로 갱신

---

## 5. 시나리오 E — AI가 실제로 기억을 반영하는지 확인

1. 설정 닫고 채팅에서 입력:

```
내일 2시간짜리 공부 시간을 잡아줘
```

**기대 결과:**
- AI가 **오전 시간대를 우선 제안** (preferredMorningWork 반영)
- 또는 **90분 블록**을 제안 (preferredBlockLength 반영)
- 응답에 저녁 시간대를 배치하면 avoidsEveningWork 학습이 부족한 것

**확인 방법 — 프롬프트에 기억이 주입됐는지:**

```bash
# 앱 로그 확인
log stream --predicate 'subsystem == "com.oy.planit"' --info
```

또는 SQLite 파일 직접 확인:

```bash
sqlite3 ~/Library/Application\ Support/Planit/Memory/hermes.sqlite \
  "SELECT key, value, confidence FROM ZMEMORYFACTRECORD;"
```

---

## 6. 시나리오 F — 영속성 확인 (앱 재시작)

1. 앱 종료 (메뉴바 아이콘 우클릭 → 종료)
2. `swift run Calen` 재시작
3. 설정 → Hermes 카드

**기대 결과:**
- 이전에 학습된 모든 fact가 그대로 표시됨
- SwiftData가 SQLite로 영속 저장하므로 재시작 후에도 유지

---

## 7. 시나리오 G — 삭제 동작

1. 개별 삭제: 특정 fact 행의 `x` 클릭
   - **기대**: 해당 행만 사라지고 카운트 -1
2. 전체 삭제: 상단 **전체 삭제** 버튼
   - **기대**: 모든 fact와 decision이 사라지고 "아직 기억된 패턴이 없습니다." 복귀

---

## 8. 디버깅 — 기억이 저장되지 않는 경우

### 확인 순서

1. **앱이 feat/planning-memory-sidecar 브랜치에서 빌드됐는지**
   ```bash
   git branch --show-current
   # feat/planning-memory-sidecar 가 출력되어야 함
   ```

2. **SQLite 파일이 생성됐는지**
   ```bash
   ls -la ~/Library/Application\ Support/Planit/Memory/
   # hermes.sqlite 파일이 있어야 함
   ```

3. **키워드가 트리거 패턴과 일치하는지**
   - 현재 감지 키워드: `아침`, `오전`, `저녁+(싫/안돼/못해)`, `짧게`, `30분`,
     `집중+(2시간/90분/두 시간)`, `회의+(많/지쳐/힘들)`, `빈 시간`, `여유 시간`,
     `남는 시간`, `급하게`, `갑자기`, `긴급`

4. **AIService에 hermesMemoryService가 주입됐는지**
   - `MainView.swift:117`의 `aiService.hermesMemoryService = hermesMemoryService` 확인

---

## 9. 단위 테스트 실행

자동화된 단위 테스트 9개 (TC-57~65):

```bash
swift test --filter "hermes"
```

**기대 결과:**
```
✔ Test hermesMemoryFact_confidenceClamped() passed
✔ Test hermesMemoryFact_recordRoundtrip() passed
✔ Test hermesMemory_remember_updatesExistingKey() passed
✔ Test hermesMemory_remember_addsNewKey() passed
✔ Test hermesMemory_forget_removesOnlyTarget() passed
✔ Test hermesMemory_recall_excludesStaleLoConfidence() passed
✔ Test hermesMemory_contextForAI_emptyWhenNoFacts() passed
✔ Test hermesMemory_contextForAI_containsBlock() passed
✔ Test hermesMemory_extract_morningKeyword() passed
```

---

## 10. 파일 경로 참고

| 용도 | 경로 |
|---|---|
| SwiftData 영속 | `~/Library/Application Support/Planit/Memory/hermes.sqlite` |
| 마크다운 컨텍스트 | `~/Library/Application Support/Planit/user_context.md` |
| 서비스 구현 | `Planit/Services/HermesMemoryService.swift` |
| 도메인 모델 | `Planit/Models/HermesModels.swift` |
| UI | `Planit/Views/SettingsView.swift` → `hermesMemoryCard` |
| 자동 추출 | `Planit/Services/HermesMemoryService.swift` → `extractAndRemember` |
| 테스트 | `Tests/CalenTests.swift` → TC-57~65 |

---

## 11. 실전 체크리스트 — 이것들을 한 번씩 돌려보세요

각 시나리오마다 **입력 문장**과 **기대 결과**를 표시했습니다. 설정 → Hermes 카드에서 확인.

### 📘 시나리오 1: 시간대 선호 점진 학습

| # | 입력 | 기대 fact |
|---|---|---|
| 1-1 | `아침에 집중이 잘 돼요` | preferredMorningWork 65% |
| 1-2 | `오전이 제일 좋아` | preferredMorningWork 70%+ (가중) |
| 1-3 | `아침엔 진짜 집중 잘됨` | preferredMorningWork 75%+ |

### 📘 시나리오 2: 선호 번복 (Hermes 핵심 — 사용자는 변한다)

| # | 입력 | 기대 동작 |
|---|---|---|
| 2-1 | `아침에 집중 잘돼요` | preferredMorningWork 65% |
| 2-2 | `저녁에 집중이 잘 돼요` | preferredEveningWork 65% **생성**, preferredMorningWork **40%로 감소** |
| 2-3 | 다시 `저녁이 좋아` | preferredEveningWork 70%+, preferredMorningWork **15%로 더 감소** |
| 2-4 | 다시 `저녁이 최고` | preferredMorningWork **삭제** (0.1 미만 → 자동 소멸) |

### 📘 시나리오 3: 부정 감지

| # | 입력 | 기대 fact |
|---|---|---|
| 3-1 | `아침엔 피곤해서 못해요` | avoidsMorningWork 65% |
| 3-2 | `저녁엔 집중 안돼요` | avoidsEveningWork 65% |
| 3-3 | `밤에 힘들어` | avoidsEveningWork 65% |

### 📘 시나리오 4: 블록 길이 선호

| # | 입력 | 기대 fact |
|---|---|---|
| 4-1 | `30분 정도 짧게 하고 싶어` | preferredBlockLength = "30분 내외" |
| 4-2 | `집중할 땐 2시간 정도가 좋아` | preferredBlockLength = "90~120분 딥워크" (덮어씀) |
| 4-3 | `90분 블록 선호` | preferredBlockLength 신뢰도 상승 |

### 📘 시나리오 5: 회의 과밀

| # | 입력 | 기대 fact |
|---|---|---|
| 5-1 | `오늘 회의가 너무 많아서 지쳐` | meetingFatigue 70% |
| 5-2 | `회의가 힘들어` | meetingFatigue 신뢰도 상승 |

### 📘 시나리오 6: 빈 시간 자동 제안 의향

| # | 입력 | 기대 fact |
|---|---|---|
| 6-1 | `빈 시간 있으면 알아서 추천해줘` | wantsSlotSuggestions 75% |
| 6-2 | `여유 시간에 운동 넣어줘` | wantsSlotSuggestions 유지 |
| 6-3 | `남는 시간 공부에 써줘` | wantsSlotSuggestions 유지 |

### 📘 시나리오 7: 급한 일정 패턴

| # | 입력 | 기대 fact |
|---|---|---|
| 7-1 | `갑자기 회의 잡혔어` | urgentReschedulingNeeds 70% |
| 7-2 | `급하게 내일 발표 준비해야 돼` | urgentReschedulingNeeds 신뢰도 상승 |

### 📘 시나리오 8: AI가 실제로 기억을 반영하는지 (최종 목표)

**준비:** `저녁에 집중이 잘 돼요` + `90분 블록이 좋아` 두 문장으로 학습

**검증 질문:**
```
내일 공부 시간 잡아줘
```

**기대 응답:**
- 시작 시간이 **18:00~22:00 사이**
- 길이가 **90분 (1시간 30분)**

✅ 둘 다 맞으면 Hermes가 제대로 동작  
❌ 오전 9시, 1시간 배치하면 기억이 프롬프트에 주입 안 된 것

---

### 📘 시나리오 9: 재시작 영속성

1. 시나리오 1~7 중 5개 이상 학습
2. 메뉴바 아이콘 우클릭 → 종료
3. `./scripts/run-dev.sh` 다시 실행
4. 설정 → Hermes 카드 → 모든 fact 그대로 있어야 함

---

### 📘 시나리오 10: 개별/전체 삭제

1. 특정 fact 우측 `x` 버튼 → 그 행만 사라짐
2. 상단 "전체 삭제" → 모든 fact + decisions 삭제

---

## 부록 — 새 키워드 추출 규칙 추가하기

`Planit/Services/HermesMemoryService.swift`의 `extractAndRemember` 함수에서 패턴 추가:

```swift
if msg.contains("새벽") {
    extracted.append(.init(
        category: .preference,
        key: "prefersEarlyMorning",
        value: "새벽 시간대 선호",
        confidence: 0.6
    ))
}
```

저장 후 `swift build` → 앱 재시작 → 채팅에서 "새벽에 공부해요" 입력 → 설정에서 확인.
