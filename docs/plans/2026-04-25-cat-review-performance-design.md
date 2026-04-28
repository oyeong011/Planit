# Walking Cat and Review Performance Design

Date: 2026-04-25
Status: Approved

## Goal

Bring the current `main` behavior into the working branch, replace the unnatural walking cat frames with new generated PNG assets, and improve Review tab scroll performance without changing Google Calendar sync behavior.

## Context

`develop` is behind `main`, and `main` contains the walking cat feature that is not present on `develop`: `Planit/Views/WalkingCatView.swift`, `Planit/Models/CatSettings.swift`, `frame_R1...frame_R8` PNG assets, and cat tests.

The existing `main` cat implementation loads `frame_R\(n)` and `frame_R\(n)@2x` from `Bundle.module`. The current failure mode is asset quality and motion, not Google Calendar integration. Static inspection found `frame_R2` and `frame_R3` touching the canvas edges with visual centroids shifted left, while the existing frame-alignment tests only check bottom-centered bounding boxes.

Review tab slowness is likely render-time work inside `ReviewView`. The heaviest paths are:

- `ReviewView` uses eager `ScrollView` + `VStack`, so all sections rebuild on invalidation.
- `todoGrassSection` computes `TodoGrassStats.make(...)` inline during rendering.
- `TodoGrassStats.make(...)` scans 365 days and filters todos, reminders, and history events for each day.
- Current `develop` `dayStats(for:)` scans year-scale `historyEvents` and logs per day; `main` used bounded `eventsForDate(date)`.
- Habit and goal cards repeatedly perform linear membership and matching scans while rendering.

## Approved Approach

Use a TDD-first, split-scope implementation:

1. Bring `main` content into the working implementation branch.
2. Replace the cat frame assets with new generated PNG frames using the same resource names to avoid extra manifest churn.
3. Improve cat motion through a pure motion helper, keeping frame cadence and position updates testable.
4. Move Review-only aggregation out of SwiftUI render paths into pure helper/snapshot code.
5. Keep Google Calendar, OAuth, fetch, dedupe, and sync files untouched unless a failing guardrail proves an existing regression unrelated to this work.

## Cat Design

Generate an 8-frame side-view walking cat sprite sequence with transparent PNG output. Preserve the existing asset contract:

- 1x frames: `Planit/Resources/frame_R1.png` through `frame_R8.png`, each 44x44.
- 2x frames: `Planit/Resources/frame_R1@2x.png` through `frame_R8@2x.png`, each 88x88.
- The cat must have consistent scale, clear padding, stable visual centroid, bottom alignment, and no alpha pixels touching the left or right canvas edges.

Motion should remain lightweight:

- Keep a small fixed lane under the calendar grid.
- Decouple sprite frame cadence from x-position updates.
- Add boundary behavior that does not look like instant mirrored sliding.
- Avoid touching calendar data, auth, sync, or event fetching.

## Review Performance Design

Introduce a Review-only metrics layer rather than pushing cached state into `CalendarViewModel`.

The first implementation pass should:

- Restore or replace `dayStats(for:)` so it does not scan year-scale `historyEvents` during scroll.
- Remove hot-path logging and per-call `DateFormatter` creation from weekly chart rendering.
- Precompute `TodoGrassStats`, weekly chart counts, habit row metrics, and goal card lookup maps from immutable inputs.
- Keep the existing section order and drag-reorder behavior, but extract reorder math to pure code before changing layout.
- Prefer `LazyVStack` only if it does not break drag-reorder behavior; otherwise keep the eager shell and reduce the cost of each rebuild.

## Google Calendar Safety Boundary

Do not edit these files as part of cat or Review performance work:

- `Planit/Services/GoogleCalendarService.swift`
- `Planit/Services/GoogleAuthManager.swift`
- `Planit/Services/GoogleAuthManager+CalendarAuthProviding.swift`
- `Planit/ViewModels/CalendarViewModel.swift`
- `Shared/Sources/CalenShared/Networking/GoogleCalendarClient.swift`

Existing Google sync and CRUD regression tests must be run after the targeted work. If guardrails are added, prefer source-level regression checks in `Tests/CalendarSyncRegressionTests.swift` rather than coupling cat or Review helpers into sync code.

## TDD Strategy

Write and run failing tests before production edits.

Cat RED tests:

- Frame PNGs exist in the bundle/resource path.
- 1x and 2x frames have stable canvas sizes.
- Alpha bounding boxes do not touch left/right edges.
- Visual centroid drift stays within tolerance.
- Bottom alignment remains stable.
- Motion is monotonic between turns.
- Frame index wraps without position jumps.

Review RED tests:

- Section order loading deduplicates and restores missing sections.
- Drag reorder math clamps and moves at expected thresholds.
- Weekly chart day stats do not use year-scale `historyEvents` in the hot path.
- Todo grass aggregation remains behaviorally identical after helper extraction.

Google guardrail tests:

- Existing `CalendarSyncRegressionTests`, `CRUDRegressionTests`, `AppleMirrorFilteringTests`, and `GoogleCalendarClientTests` must pass.
- Add source guardrails only if implementation touches shared boundaries.

## Parallelization

Implementation can run in parallel after the TDD plan is written:

- Cat asset/motion track owns `WalkingCatView`, cat assets, and cat tests.
- Review performance track owns Review-only helper/tests and limited `ReviewView` wiring.
- Verification track owns Google guardrail test execution and reports failures without modifying sync logic.

Write sets must stay disjoint. Any shared file such as `Package.swift` or `ReviewView.swift` needs a single owner.

## Trade-offs

| Option | Pros | Cons |
| --- | --- | --- |
| Minimal cat asset replacement | Smallest visual fix | Does not address hard boundary turns or missing frame guardrails |
| Review-only snapshot layer | High scroll impact and protects sync code | Adds a small amount of Review-specific state/invalidating logic |
| CalendarViewModel-level caching | Centralizes data ownership | Higher risk to Google sync, Apple mirror dedupe, TTL, and pending edit behavior |

## Verification

Targeted commands:

```bash
swift test --filter WalkingCat
swift test --filter TodoGrassStats
swift test --filter ReviewSectionLayout
swift test --filter CalendarSyncRegressionTests
swift test --filter CRUDRegressionTests
swift test --filter AppleMirrorFilteringTests
swift test --filter GoogleCalendarClientTests
swift test
```

The work is complete only when the generated cat frames pass geometry tests, Review helper tests pass, and Google Calendar guardrails remain green.
