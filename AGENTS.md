# PROJECT KNOWLEDGE BASE

**Generated:** 2026-07-01T02:53:56Z
**Commit:** `ca795ca`
**Branch:** `feature/screen-time-integration`

## OVERVIEW

Calen is a Swift 5.9 calendar app repo with three live surfaces: macOS menu bar app (`Calen`), platform-neutral shared library (`CalenShared`), and iOS companion app/widget (`CaleniOS`). The repo is a hybrid SwiftPM plus XcodeGen workspace; do not assume a single canonical `Sources/` layout.

## STRUCTURE

```text
./
|-- Package.swift                 # SwiftPM target graph and resource bundling
|-- Planit/                       # macOS executable target path for `Calen`
|-- Shared/                       # non-target wrapper; child guidance lives here
|-- CaleniOS/                     # iOS app/widget plus XcodeGen project spec
|-- Tests/                        # Swift Testing target `CalenTests`
|-- scripts/                      # build, release, signing, localization checks
|-- docs/                         # public docs, Sparkle appcasts, OAuth evidence
|-- marketing/                    # non-build assets/copy
`-- submission/                   # non-build presentation/submission artifacts
```

Do not add guidance files inside SwiftPM target paths such as `Planit/` or `Shared/Sources/CalenShared/`; stray markdown can become package input noise.

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| macOS boot/menu bar | `Planit/PlanitApp.swift` | `@main`, `NSStatusItem`, popover, updater hooks |
| macOS app state | `Planit/ViewModels/CalendarViewModel.swift` | central state/sync owner, largest source hotspot |
| macOS UI composition | `Planit/Views/MainView.swift` | service wiring plus nested calendar/detail views |
| macOS Google auth | `Planit/Services/GoogleAuthManager.swift` | loopback OAuth, PKCE, Keychain tokens |
| macOS calendar API | `Planit/Services/GoogleCalendarService.swift` | concrete Google Calendar integration |
| shared planning | `Shared/Sources/CalenShared/Planning/PlanningOrchestrator.swift` | pure parse/validate/generate path |
| shared REST client | `Shared/Sources/CalenShared/Networking/GoogleCalendarClient.swift` | used by iOS repository and tests |
| iOS app shell | `CaleniOS/Sources/CaleniOSApp.swift` | SwiftData stack, env services, placeholder main |
| iOS project generation | `CaleniOS/project.yml` | XcodeGen source of truth for app and widget |
| widget contract | `CaleniOS/Sources/Services/WidgetDataPublisher.swift`, `CaleniOS/Widget/` | mirrored App Group payload schema |
| packaging | `scripts/build-app.sh`, `.github/workflows/release.yml` | universal binary, Sparkle, signing, notarization |
| localization/privacy checks | `Tests/LocalizationQualityTests.swift`, `Tests/MacPrivacyEntitlementTests.swift` | packaging invariants are tested |

## CODE MAP

| Symbol | Type | Location | Refs | Role |
| --- | --- | --- | --- | --- |
| `PlanitApp` | `App` | `Planit/PlanitApp.swift:9` | entry | macOS status-bar app boot |
| `AppDelegate` | class | `Planit/PlanitApp.swift:24` | entry | popover/menu/updater lifecycle |
| `MainCalendarView` | `View` | `Planit/Views/MainView.swift:31` | high | macOS service graph and root UI |
| `CalendarViewModel` | class | `Planit/ViewModels/CalendarViewModel.swift:20` | high | app state, sync, CRUD hub |
| `GoogleAuthManager` | class | `Planit/Services/GoogleAuthManager.swift:49` | medium | OAuth credentials and token lifecycle |
| `PlanningOrchestrator` | class | `Shared/Sources/CalenShared/Planning/PlanningOrchestrator.swift:159` | medium | shared AI planning validation |
| `GoogleCalendarClient` | class | `Shared/Sources/CalenShared/Networking/GoogleCalendarClient.swift:28` | medium | shared Google REST boundary |
| `CaleniOSApp` | `App` | `CaleniOS/Sources/CaleniOSApp.swift:23` | entry | iOS lifecycle and SwiftData setup |
| `RootView` | `View` | `CaleniOS/Sources/App/RootView.swift:10` | entry | routes directly to `MainTabView` |
| `WidgetDataProvider` | enum | `CaleniOS/Widget/WidgetDataProvider.swift:14` | widget | reads App Group event snapshots |

## CONVENTIONS

- `Package.swift` uses nonstandard target paths: macOS app in `Planit/`, shared library in `Shared/Sources/CalenShared`, iOS executable in `CaleniOS/Sources`.
- Keep platform-only frameworks out of `CalenShared`: no AppKit, UIKit, EventKit, Sparkle, or WidgetKit there.
- Keep long Swift files organized with `// MARK:`. Current hotspots include `CalendarViewModel.swift`, `MainView.swift`, `ReviewView.swift`, `AIService.swift`, and iOS `SettingsView.swift`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Favor pure logic, parser, layout, request/response, localization, and packaging invariant tests.
- Localization base is `Planit/Resources/ko.lproj/Localizable.strings`; `scripts/verify-localizations.sh` and `LocalizationQualityTests` both enforce resource quality.
- Use Xcode only for signing, entitlements, UI debugging, or generated iOS project workflows.

## ANTI-PATTERNS (THIS PROJECT)

- Do not commit credentials: `google_credentials.json`, `*credentials*.json`, and `Planit/Services/BundledCredentials.local.swift` stay local/secret-generated.
- Do not commit generated outputs: `.build/`, `.swiftpm/`, `DerivedData/`, `xcuserdata/`, `CaleniOS/CaleniOS.xcodeproj/`, `.omx/`, `.lazyweb/`, `.playwright-mcp/`.
- Do not bundle entitlement plist files as app resources; packaging scripts explicitly remove them.
- Do not hand-edit generated iOS project files; change `CaleniOS/project.yml` and regenerate.
- Do not break the widget payload mirror between app-side publisher and widget-side snapshot/provider.

## COMMANDS

```bash
swift build
swift run Calen
swift test
swift build -c release
bash scripts/build-app.sh 1.0.0
bash scripts/build-ios-app.sh 0.1.0
bash scripts/verify-localizations.sh
make dev
make ci-ios
```

## NOTES

- `scripts/build-app.sh` intentionally builds `arm64` and `x86_64` separately, merges with `lipo`, embeds Sparkle, adds `@executable_path/../Frameworks` rpath, and signs Sparkle inside-out.
- Release signing/notarization needs Developer ID and notarization env vars; CI injects bundled OAuth credentials from GitHub secrets.
- Existing generated/vendor noise under `CaleniOS/build/DerivedData/SourcePackages/checkouts/Sparkle/` is not repo source.
- The current test suite is broad but heterogeneous; `Tests/CalenTests.swift` is a maintenance hotspot, while newer suites are more focused.
