# Repository Guidelines

## Project Structure & Module Organization

This is a Swift Package for a macOS menu bar app. The package target is `Calen`, while application sources live under `Planit/`.

- `Planit/PlanitApp.swift` contains the app entry point and menu bar popover setup.
- `Planit/Views/`, `Planit/ViewModels/`, `Planit/Models/`, and `Planit/Services/` hold SwiftUI UI, state, domain models, and integrations.
- `Planit/Resources/` stores localized `Localizable.strings`, app icon, and privacy manifest.
- `Tests/` contains Swift Testing unit tests.
- `scripts/build-app.sh` builds release artifacts.

## Build, Test, and Development Commands

- `swift build` builds the debug Swift package.
- `swift run Calen` launches the app from SwiftPM for local development.
- `swift test` runs the `CalenTests` test target.
- `swift build -c release` builds an optimized binary.
- `scripts/build-app.sh 1.0.0` creates a universal `.app`, `.zip`, and `.dmg` under `.build/release`.

Use Xcode only when you need signing, entitlements, or UI debugging. Generated outputs in `.build/`, `.swiftpm/`, `DerivedData/`, and `xcuserdata/` should stay uncommitted.

## Coding Style & Naming Conventions

Use Swift 5.9 conventions with 4-space indentation. Keep types in `UpperCamelCase`, functions and properties in `lowerCamelCase`, and file names aligned with the primary type when practical. Prefer `struct` for values and `final class` for observable reference types. Keep UI in `Views`, long-lived state in `ViewModels`, and external integrations in `Services`.

There is no dedicated formatter configuration in this repo; preserve the existing Xcode/SwiftPM style and organize larger files with `// MARK:` sections.

## Testing Guidelines

Tests use the Swift Testing framework (`import Testing`) with `@Test` functions and `#expect` assertions. Add tests in `Tests/` with behavior-focused names such as `cliDetection_rejectedCommands`. When app modules are hard to import, keep tests around extracted pure logic or small mirrored helpers.

Run `swift test` before submitting changes. Add regression tests for bug fixes and security-sensitive logic.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative summaries such as `Add Google Calendar OAuth integration...` or version-prefixed release notes like `v1.0.0: ...`. Keep commit subjects specific and mention the main feature or fix.

Pull requests should include a short description, verification commands run, linked issues when available, and screenshots or screen recordings for UI changes.

## Security & Configuration Tips

Do not commit credentials. `google_credentials.json`, `*credentials*.json`, `.omx/`, and build artifacts are ignored. Keep OAuth, Keychain, entitlements, and notification changes tightly scoped and document any required local setup.
