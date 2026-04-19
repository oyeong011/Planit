# CaleniOS — iPhone/iPad 앱

macOS Calen과 **Custom CKRecord 기반 단방향 sync**되는 iOS 컴패니언.

> **설계 원칙(v0.1.0)**
> - macOS가 Hermes 메모리의 **Source of Truth**. iOS는 **read-only** 조회만.
> - SwiftData automatic CloudKit sync는 **사용하지 않음** (`HermesMemoryFactV1` custom CKRecord 스키마 채택).
> - 공유 코드는 모두 `CalenShared` 라이브러리(Package.swift의 `CalenShared` target)를 통해 임포트.
> - `CaleniOS/Sources/`는 iOS 전용 뷰/앱 엔트리만 보관.

## 프로젝트 생성 (xcodegen)

iOS 앱은 **xcodegen**으로 `.xcodeproj`를 생성합니다 (수동 Xcode New Project 금지 — 재현성/소스 제어 목적).

> RELEASE 팀장이 `CaleniOS/project.yml` + `scripts/build-ios-app.sh`를 작성할 때까지 로컬 빌드는
> `xcodebuild -scheme CaleniOS -destination 'generic/platform=iOS Simulator' build`로 SwiftPM 스킴을 이용하세요.

## iCloud 설정 (RELEASE 팀장 작업)

1. Apple Developer 콘솔에서 **iCloud Container** `iCloud.com.oy.planit` 생성 (이미 존재할 수 있음).
2. macOS Planit.entitlements + iOS entitlements 양쪽에 추가:
   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array>
       <string>iCloud.com.oy.planit</string>
   </array>
   <key>com.apple.developer.icloud-services</key>
   <array>
       <string>CloudKit</string>
   </array>
   ```
3. macOS 앱이 `HermesMemoryFactV1` 레코드를 private DB의 `default zone`에 저장 → iOS가 `CKQueryOperation`으로 fetch.

> **참고**: SwiftData `.automatic` CloudKit sync는 의도적으로 **사용하지 않습니다**. 이유:
> - `@Attribute(.unique)`가 CloudKit에서 uniqueness 보장 불가
> - Production schema deploy 과정 필요
> - Background Modes + remote notifications capability 추가 필요

## 빌드 & 실행

```bash
# 시뮬레이터 빌드 (저장소 루트에서)
xcodebuild -scheme CaleniOS -destination 'generic/platform=iOS Simulator' build

# 시뮬레이터 실행 (xcodegen 프로젝트 생성 후)
open -a Simulator
xcodebuild -project CaleniOS/CaleniOS.xcodeproj -scheme CaleniOS -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -configuration Debug
```

## 파일 구조

```
CaleniOS/
├── project.yml               (RELEASE 팀장이 추가 예정 — xcodegen 입력)
├── Sources/
│   ├── CaleniOSApp.swift     — @main, RootTabView (SwiftData automatic CloudKit 제거됨)
│   ├── Models/
│   │   └── HermesModels.swift — Shared re-export. 값 타입은 CalenShared에서 제공
│   └── Views/
│       ├── HomeView.swift    — v0.1.0 placeholder (UI 팀장 확장)
│       ├── MemoryView.swift  — Hermes 기억 조회 (read-only, UI 팀장 확장)
│       └── SettingsView.swift— 로그인/API키/동기화 상태 (UI 팀장 확장)
└── README.md                  (이 파일)
```

## 공유 코드 (`Shared/Sources/CalenShared/`)

M1에서 추출된 iOS-Safe 공유 레이어:

- **Models** — `MemoryFact`, `MemoryCategory`, `PlanningDecision`, `CalendarEvent` (모두 `public`, `Codable`, `Sendable`)
- **Protocols** — `PlanningAIProvider`, `CalendarAuthProviding`, `MemoryFetching`
- **CloudKit** — `HermesMemoryFactV1` (macOS가 write, iOS가 read, schemaVersion=1)
- **Planning** — `PlanningSummaryMath` (순수 계산 함수)

`SwiftUI.Color`/`AppKit`/`UIKit` 의존 없이 Foundation + CloudKit만 사용.

## 후속 팀장 작업 (M2 병렬)

- [ ] **AUTH 팀장** — `GoogleAuthManager`를 `ASWebAuthenticationSession` + reversed-client-ID로 iOS 포팅. Keychain은 App Group `group.com.oy.planit`로 공유(`kSecUseDataProtectionKeychain=true`).
- [ ] **UI 팀장** — 3탭(오늘/할일/설정) 레이아웃, iPad는 NavigationSplitView. MemoryView는 **read-only**.
- [ ] **SYNC 팀장** — macOS `HermesMemoryService`가 `HermesMemoryFactV1.encode(fact:)`로 업로드 + iOS `CKQueryOperation` fetch 구현.
- [ ] **AI 팀장** — `AIServiceProtocol` / `PlanningAIProvider` 구현체 `iOSClaudeAPIProvider` 스텁 + 설정 UI의 API 키 `SecureField`.
- [ ] **RELEASE 팀장** — `CaleniOS/project.yml` (xcodegen), `scripts/build-ios-app.sh`, iOS entitlements.

## 릴리즈

- **태그 체계**: `calen-ios-<x.y.z>` (macOS `v0.4.x`와 독립)
- **v0.1.0 P0 범위**: Google Calendar 읽기 + 간단 편집, Todo 로컬, Hermes 기억 **조회 전용**, Claude API 키 입력만(iOS 채팅은 v0.1.1+).
