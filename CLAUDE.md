# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Planit (앱 이름: Calen)은 macOS 메뉴바 앱으로, Google Calendar 연동 + AI 기반 일정 관리 기능을 제공합니다. Swift Package (`Calen` 타깃)로 빌드되며, 소스는 `Planit/` 디렉터리에 있습니다.

## Build & Test Commands

```bash
swift build                    # 디버그 빌드
swift build -c release         # 릴리즈 빌드
swift run Calen                # 로컬 실행
swift test                     # 전체 테스트 (CalenTests 타깃)
scripts/build-app.sh 1.0.0     # 배포용 .app/.zip/.dmg 생성
```

Xcode는 서명, 엔타이틀먼트, UI 디버깅이 필요할 때만 사용. `.build/`, `DerivedData/`, `xcuserdata/`는 커밋 금지.

## Architecture

```
PlanitApp.swift          ← @main, NSStatusItem + NSPopover 설정 (AppDelegate)
Views/MainView.swift     ← 루트 뷰. 로그인 여부에 따라 LoginView 또는 MainCalendarView
ViewModels/
  CalendarViewModel.swift  ← @MainActor ObservableObject, 앱 전체 상태 허브
Services/
  GoogleAuthManager.swift  ← OAuth2 인증 (Keychain 저장)
  GoogleCalendarService.swift ← Calendar API CRUD
  AIService.swift          ← Claude / Codex API 호출, 첨부파일(이미지·PDF) 지원
  SmartSchedulerService.swift ← 빈 슬롯 분석 및 Todo 자동 배치
  ReviewAIService.swift    ← 일간·주간 AI 리뷰 생성
  UserContextService.swift ← 초개인화 컨텍스트 수집/저장
  GoalService.swift        ← 목표 관리
  ReviewService.swift      ← 리뷰 히스토리
  NotificationService.swift ← UNUserNotificationCenter
Models/
  TodoItem.swift           ← Todo 도메인 모델
  GoalModels.swift         ← Goal 도메인 모델
```

**핵심 데이터 흐름**: `CalendarViewModel`이 모든 Service를 소유하고 View에 상태를 노출. View는 ViewModel 메서드를 호출하고, Service는 직접 호출하지 않음.

## Key Patterns

- `@MainActor final class` for ViewModels; `struct` for domain models
- `// MARK:` 섹션으로 긴 파일 구조화
- `UserDefaults` key prefix: `planit.*`
- Apple Calendar/Reminders는 `EventKit`으로 별도 통합 (Google Calendar와 병렬)
- AI 기능: `AIProvider` enum으로 Claude / Codex 선택, API 키는 Keychain에 저장

## Testing

Swift Testing 프레임워크 사용 (`import Testing`, `@Test`, `#expect`). 테스트는 `Tests/CalenTests.swift`.

## Branch Strategy

- `develop` ← 일상 개발 기준 브랜치
- `feature/*` / `fix/*` ← develop에서 분기, PR은 develop으로
- `main` ← 릴리즈 전용, 직접 push 불가

## Commit Convention

```
feat: / fix: / refactor: / style: / docs: / test: / chore:
```
