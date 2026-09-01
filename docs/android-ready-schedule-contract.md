# Android Readiness Contract for Schedule Sync and Widgets

## Scope and policy

This document defines the Android readiness contract only. It does **not** authorize
any Android app/module implementation yet.

- Phase sequencing and implementation are controlled by `mobile-replan-refactor` Todo 11.
- Until the shared schedule contract and sync boundaries are stable, Android code and
  Gradle projects are explicitly out of scope.
- This contract is derived from existing iOS/macOS code in:
  - `Package.swift`
  - `Shared/Sources/CalenShared/Models/CalendarEvent.swift`
  - `CaleniOS/Sources/Services/WidgetDataPublisher.swift`
  - `CaleniOS/Widget/EventSnapshot.swift`
  - `PRD.md`

## Android phase gates

### Phase 0 — Contract Freeze (current)
- Stop conditions: define and freeze event schema, identity, and publish payload.
- Go conditions:
  - Shared event model fields and identity are documented.
  - Widget snapshot payload schema is documented.
  - No Android implementation changes are merged before this gate is approved.
- Exit from gate when this document is accepted and referenced by Todo 11.

### Phase 1 — Shared Contract Adapter (future)
- Keep Android work purely adapter-driven and data-only.
- Work includes:
  - Pure Kotlin data models that mirror the shared schedule payload
  - Mapping rules from canonical JSON fields to local Android types
  - Validation tests for schema compatibility
- Explicit prohibition: no Gradle, AndroidManifest, or widget source files.

### Phase 2 — Local Glance Integration (future)
- Build a Glance rendering path from canonical payload.
- Reuse the same canonical payload contract without mutation.
- Only implement if Phase 1 contract tests and sync assumptions are stable.

### Phase 3 — Surface + sync alignment (future)
- Add Android widget/screen scheduling surface only after
  - cross-platform conflict policies are stable, and
  - sync conflict precedence rules are accepted.
- Re-check this contract before every migration step.

## Source-of-truth and sync boundaries

- Canonical schedule domain model in this repo is platform-neutral and lives in
  `CalendarEvent` (`Shared/Sources/CalenShared/Models/CalendarEvent.swift`):
  - `id`
  - `calendarId`
  - `title`
  - `startDate`, `endDate`
  - `isAllDay`
  - `location`, `description`
  - `colorHex`
  - `source`, `etag`, `updated`, `isReadOnly`, `isCompleted`
- Event identity is canonicalized as `calendarId + id`, not `id` alone.
- iOS today-widget path currently serializes only a reduced payload for widget use,
  and publishes via `WidgetDataPublisher`.
- Android must consume a stable JSON contract before any data writes/reads are added.

### Sync source recommendations (for planning)
- Recommended source-of-truth for schedule content: existing shared domain model (`CalendarEvent`)
- Android temporary adapter strategy: read-only contract ingestion + explicit mapping layer
- Android write-back strategy: deferred until Android sync architecture (and conflict
  resolution policy) is finalized

## Widget payload schema (as currently implemented on iOS)

`CalendarEvent` is converted to a compact snapshot payload in
`CaleniOS/Sources/Services/WidgetDataPublisher.swift`.

### Shared fields used for widget transport
- `schemaVersion` = 1
- `publishedAt` (ISO-8601 date string in JSON)
- `events`: ordered array, start-date ascending

### Snapshot event fields
- `id`: string composed as `"\(calendarId)::\(id)"`
- `title`: string
- `start`: ISO-8601 timestamp
- `end`: ISO-8601 timestamp
- `colorHex`: string like `#3366CC`
- `isAllDay`: boolean

### Storage and key names (current iOS implementation)
- UserDefaults suite: `group.com.oy.planit`
- UserDefaults key: `planit.widget.today-events.v1`
- Fallback file: `widget-events.json`
- Max events for publish: 10
- Filter rule: only events with `endDate >= now` are included

### Contract equivalence rule
The App-side mirror type in `WidgetDataPublisher` and widget-side `EventSnapshot`
must stay field-compatible for JSON decode/encode compatibility. Any schema
evolution must update both sides simultaneously.

## First Kotlin/Glance milestone

### Milestone A — Kotlin/Glance contract bootstrapping
- Scope: docs-first, data model only, no runtime Android target files.
- Deliverables:
  - Plain Kotlin value classes representing the exact fields above.
  - Decoder/encoder tests using existing JSON sample(s) from current iOS contract.
  - Decision record: whether Glance reads contract from local sync channel or
    separate feed.
- Exit criteria:
  - Stable schema review is approved.
  - No behavior changes on iOS/macOS from this step.
  - No Gradle / Android source files committed.

## Explicit "do not start Android" checklist
- Do not add `build.gradle`, `settings.gradle`, `AndroidManifest.xml`.
- Do not add `android/`, `Android/`, or `app/src/main/*` trees.
- Do not add new runtime dependencies for Android platform.
- Do not add platform-specific implementation to satisfy widgets before contract lock.

## Official Android references
- Android App Widgets overview:
  https://developer.android.com/develop/ui/views/appwidgets/overview
- Android Glance:
  https://developer.android.com/develop/ui/compose/glance/create-app-widget

## Status
- Android implementation is blocked until the above gates are accepted.
- This doc is the current truth source for the mobile readiness contract.

