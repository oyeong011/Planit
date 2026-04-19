# CaleniOS — iPhone/iPad 앱

macOS Calen과 **iCloud sync되는** iOS 컴패니언 앱.

## Xcode 프로젝트 생성 (한 번만)

1. Xcode 열기 → **File → New → Project**
2. **iOS → App** 선택, Next
3. 설정:
   - Product Name: `CaleniOS`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Bundle Identifier: `com.oy.planit.ios`
   - Team: 본인 Apple Developer 계정
4. 저장 위치: **이 `CaleniOS/` 폴더 안** (새 폴더 만들지 말고 "Create Git repository" 체크 해제)
5. Xcode가 자동 생성한 `ContentView.swift`와 `CaleniOSApp.swift`는 삭제
6. `Sources/` 폴더의 파일들을 Xcode 프로젝트에 **Add Files to "CaleniOS"** 로 추가

## iCloud 설정 (중요)

Xcode에서 타겟 선택 → **Signing & Capabilities**:

1. **+ Capability** → **iCloud** 추가
2. Services: ☑ **CloudKit**
3. Containers: `iCloud.com.oy.planit`
4. (최초 한 번) "+" 눌러서 `iCloud.com.oy.planit` 컨테이너 생성

macOS 앱도 동일한 컨테이너를 엔타이틀먼트에 추가해야 동기화됩니다:
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.oy.planit</string>
</array>
```

## 빌드 & 실행

Xcode에서 Cmd+R → 시뮬레이터 또는 실제 iPhone으로 실행.

## 파일 구조

```
CaleniOS/
├── CaleniOS.xcodeproj      (Xcode에서 생성)
├── Sources/
│   ├── CaleniOSApp.swift     — @main, ModelContainer + RootTabView
│   ├── Models/
│   │   └── HermesModels.swift — macOS와 동일한 @Model 스키마
│   └── Views/
│       ├── HomeView.swift    — 메인 탭 (Hermes 요약 + quick actions)
│       ├── MemoryView.swift  — 기억 조회/삭제
│       └── SettingsView.swift— iCloud 상태 + 계정
└── README.md (이 파일)
```

## 다음 단계 (Phase 3)

- [ ] Google 로그인 (macOS의 `GoogleAuthManager` 포팅)
- [ ] 오늘 이벤트 표시 (Google Calendar API)
- [ ] "오늘 다시 짜기" 버튼 — PlanningOrchestrator 호출
- [ ] CalenShared로 공유 코드 이동 (현재 iOS는 스키마 복제본 사용 중)
