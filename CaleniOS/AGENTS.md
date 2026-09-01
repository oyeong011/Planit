# CALENIOS KNOWLEDGE BASE

**Scope:** `/Users/oy/Projects/Planit/CaleniOS`
**Generated:** 2026-07-01T02:53:56Z

## OVERVIEW

`CaleniOS/` is the iOS companion app plus widget surface. It depends on `CalenShared`, uses XcodeGen for app/widget project generation, and has iOS-only SwiftData, CloudKit, App Group, OAuth, theme, language, and widget code.

## STRUCTURE

```text
CaleniOS/
|-- project.yml                  # XcodeGen source of truth
|-- BUILD.md                     # local IPA/archive guide
|-- Sources/
|   |-- CaleniOSApp.swift        # iOS app entry, SwiftData container
|   |-- App/                     # RootView, MainTabView, AppState
|   |-- Models/                  # iOS wrappers/re-exports
|   |-- Services/                # iOS auth, memory, widget publisher
|   |-- Views/                   # iOS SwiftUI screens
|   `-- Resources/               # iOS entitlements/localizations
`-- Widget/                      # WidgetKit extension and App Group reader
```

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| generated project config | `project.yml` | app, widget, entitlements, package reference |
| iOS build flow | `BUILD.md`, `../scripts/build-ios-app.sh` | `xcodegen`, archive, export IPA |
| app entry | `Sources/CaleniOSApp.swift` | SwiftData setup and non-iOS placeholder main |
| navigation shell | `Sources/App/MainTabView.swift`, `Sources/App/AppState.swift` | tab routing and transient nav state |
| Google auth | `Sources/Services/iOSGoogleAuthManager.swift` | `ASWebAuthenticationSession`, Keychain, callback URL |
| Google data | `Sources/Services/GoogleCalendarRepository.swift`, `Sources/Views/HomeViewModel.swift` | iOS repository/view-model bridge |
| shared memory | `Sources/Services/iOSMemoryFetcher.swift` | implements `CalenShared.MemoryFetching` |
| widget write path | `Sources/Services/WidgetDataPublisher.swift` | app-side App Group payload |
| widget read path | `Widget/EventSnapshot.swift`, `Widget/WidgetDataProvider.swift` | mirrored schema; keep compatible |

## CONVENTIONS

- Change `project.yml` for project, plist, entitlement, widget, bundle ID, App Group, and package-reference behavior; generated `.xcodeproj` is not source.
- Preserve `createIntermediateGroups: false` and `schemePathPrefix: ../`; they avoid XcodeGen/local-package collisions.
- Keep `Sources/Info.plist` and entitlements aligned with `project.yml`; check comments before editing generated-owner fields.
- Keep iOS-only app code under `Sources/` and widget-only code under `Widget/`.
- Use `#if os(iOS)` carefully. The placeholder `@main` exists so SwiftPM can compile the executable target off iOS.
- Widget payload schema is duplicated by design; update publisher, `EventSnapshot`, provider, and tests together.

## ANTI-PATTERNS

- Do not manually edit or commit `CaleniOS/CaleniOS.xcodeproj`; regenerate it with XcodeGen.
- Do not route widget data through app-only types unless the widget target can compile them.
- Do not replace custom CKRecord read-only memory sync with SwiftData automatic CloudKit sync without a full schema/release plan.
- Do not remove App Group or CloudKit entitlements casually; app, widget, Keychain, and memory sync depend on them.
- Do not put macOS-only services, AppKit, Sparkle, or menu bar assumptions in this subtree.

## COMMANDS

```bash
brew install xcodegen
(cd CaleniOS && xcodegen generate)
xcodebuild -project CaleniOS/CaleniOS.xcodeproj -scheme CaleniOS -destination 'generic/platform=iOS Simulator' build
bash scripts/build-ios-app.sh 0.1.0
```

Run the script from repo root. It creates `.build/ios-archive/CaleniOS-<VERSION>.xcarchive` and `.build/ios-ipa/CaleniOS.ipa`.
