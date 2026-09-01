# SHARED KNOWLEDGE BASE

**Scope:** `/Users/oy/Projects/Planit/Shared`
**Generated:** 2026-07-01T02:53:56Z

## OVERVIEW

`Shared/` wraps the `CalenShared` SwiftPM target. Put cross-platform domain models, protocol seams, validation, math, and transport-neutral clients here; platform app code belongs in `Planit/` or `CaleniOS/`.

## STRUCTURE

```text
Shared/
`-- Sources/CalenShared/
    |-- CalenShared.swift        # module marker and boundary note
    |-- Models/                  # Codable/Sendable value types
    |-- Protocols/               # app-provided auth, AI, memory seams
    |-- Planning/                # prompt/parse/validate orchestration
    |-- Networking/              # shared Google/Claude REST clients
    |-- Layout/                  # pure calendar layout math
    |-- Memory/                  # CloudKit/Hermes shared records
    `-- Review/                  # shared review aggregation helpers
```

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| module boundary | `Sources/CalenShared/CalenShared.swift` | says no AppKit/UIKit/EventKit/Sparkle |
| planning actions | `Sources/CalenShared/Planning/PlanningOrchestrator.swift` | public test-facing validation helpers |
| AI seam | `Sources/CalenShared/Protocols/PlanningAIProvider.swift` | implemented by app-specific providers |
| calendar auth seam | `Sources/CalenShared/Protocols/CalendarAuthProviding.swift` | used by shared Google client |
| memory seam | `Sources/CalenShared/Protocols/MemoryFetching.swift` | implemented by iOS memory adapter |
| shared Google API | `Sources/CalenShared/Networking/GoogleCalendarClient.swift` | tested request/retry/parse boundary |
| layout math | `Sources/CalenShared/Layout/` | pure algorithms with focused tests |

## CONVENTIONS

- Keep APIs platform-neutral: `Foundation`, `CloudKit` where required, and data-only Swift types.
- Prefer `public struct`/`enum` for shared values and `public protocol` for app-provided behavior.
- Shared models should be `Codable` and `Sendable` when they cross app, widget, network, or CloudKit boundaries.
- Put validation and parsing helpers here only when both app surfaces can reuse them or tests need stable pure logic.
- Add or update tests in `Tests/` for planning, layout, networking, and serialization behavior.

## ANTI-PATTERNS

- No AppKit, UIKit, EventKit, Sparkle, WidgetKit, menu bar state, view state, or Keychain implementation code.
- Do not import app targets from shared code. Dependencies point outward: apps import `CalenShared`.
- Do not make iOS widget payload types depend on this module unless `CaleniOS/project.yml` models that dependency explicitly.
- Do not hide platform behavior behind `#if os(...)` here unless the type remains a true shared contract.

## NOTES

- `PlanningOrchestrator` is consumed by iOS replan services and heavily tested; keep its public validation helpers stable.
- `GoogleCalendarClient` depends on `CalendarAuthProviding`; concrete OAuth managers live in platform services.
- This file intentionally sits at `Shared/AGENTS.md`, outside the SwiftPM target path, so it does not become target input.
