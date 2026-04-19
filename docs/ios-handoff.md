# Calen iOS 앱 작업 의도서 (develop 분기 기반)

## 배경
- macOS 앱 Calen(Planit 레포)이 v0.3.4까지 배포됨
- develop 브랜치에서 iOS 컴패니언 앱 시작
- Hermes 장기 기억 + Planning Orchestrator 이미 구현됨
- CloudKit으로 mac↔iOS↔iPad 간 Hermes 데이터 자동 동기

## 목표
1. iOS 네이티브 SwiftUI 앱 (menu bar 개념 없음)
2. macOS 앱과 **같은 iCloud 컨테이너** (`iCloud.com.oy.planit`) 공유
3. Hermes 기억은 CloudKit으로 자동 sync
4. iPhone UX 중심: 빠른 캡처, 오늘 재계획, 기억 조회

## 이미 준비된 것 (CaleniOS/ 폴더)
```
CaleniOS/
├── README.md                   # Xcode 프로젝트 생성 가이드
└── Sources/
    ├── CaleniOSApp.swift       # @main, ModelContainer + 3탭
    ├── Models/HermesModels.swift  # macOS와 동일한 SwiftData 스키마
    └── Views/
        ├── HomeView.swift      # 오늘 요약 + quick actions
        ├── MemoryView.swift    # Hermes 기억 조회/삭제
        └── SettingsView.swift  # iCloud 상태 + 계정
```

## 첫 작업 순서 (Phase 1)
1. Xcode → File → New Project → iOS App
   - Product Name: CaleniOS
   - Bundle ID: com.oy.planit.ios
   - Interface: SwiftUI
   - 저장: /Users/oy/Projects/Planit/CaleniOS/ (기존 폴더 사용)
2. 생성된 ContentView/CaleniOSApp 삭제, Sources/ 파일들 Add Files
3. Signing & Capabilities:
   - + Capability → iCloud → CloudKit
   - Container: iCloud.com.oy.planit (신규 생성)
4. macOS 앱 Planit.entitlements에도 같은 container 추가
5. 시뮬레이터/실기기로 빌드 → 3탭 UI 확인
6. Mac에서 Hermes에 fact 추가 → iPhone에 자동 sync되는지 검증

## 디자인 원칙
- Hermes 철학: "기억하며 성장하는 에이전트"
- iOS는 "빠른 동행자(companion)" — 무거운 작업은 Mac에서
- OAuth 로그인, Google Calendar 동기는 Phase 2에서
- Phase 1은 **Hermes 기억 sync 검증**에 집중

## 주의
- macOS 앱 코드(Planit/)는 절대 수정 안 함 — iOS 앱만 독립 개발
- Models/HermesModels.swift는 macOS와 정확히 같은 @Model 구조 유지 (CloudKit 스키마 해시)
- main/develop 브랜치는 건드리지 않음

작업하시면 GitHub PR로 develop에 올려주세요.
