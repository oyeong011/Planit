# Menu Bar Progress And Animal Expansion Design

## Goal

Calen should show today's completion progress in the macOS menu bar and expand the existing macOS animal pet set without regressing animation performance, privacy behavior, or the settings animal tab.

## Scope

- macOS Planit only.
- Keep the existing popover walking pet engine.
- Add a small number of new animals using the current normalized sprite contract.
- Add a menu bar progress indicator based on today's completion rate.
- Do not touch iOS.
- Do not change review/statistics/chat tab structure.
- Do not add new dependencies.

## Menu Bar Completion Model

The menu bar percentage uses "today's work completion":

- Numerator: completed items for today.
- Denominator: all eligible items for today.
- Eligible sources are existing today todos/reminders and completion-tracked today calendar events, using the same domain data already owned by `CalendarViewModel`/review metrics.
- If the denominator is zero, the menu bar shows a neutral state instead of a misleading `0%`.

The first implementation should prefer a pure helper so the rule is testable without rendering AppKit UI.

## Menu Bar Design

The icon should read like a compact battery/progress meter rather than a text-heavy badge:

- Use a small horizontal battery body with a cap.
- Fill width reflects today's completion percent.
- Color shifts from low to mid to complete, but remains readable in light and dark menu bars.
- Avoid always-on high-frame animation.
- Animate only on progress changes or with very low-frequency idle updates if needed later.

This keeps performance predictable. The status item is tiny, so the first version should prioritize clear progress over showing a full walking animal inside the menu bar.

## Animal Additions

The active animal set currently uses:

- `cat`
- `dog`
- `cheetah`
- `duck`
- `rabbit`

Add 2-3 animals only, preserving the current sprite rules:

- 8 frames per animal.
- `56x56` 1x PNG.
- `112x112` 2x PNG.
- Stored under `Planit/Resources/CatSprites`.
- Named `character_<animal>_R1...R8` plus `@2x` variants.

Recommended first additions:

- `panda`
- `turtle`
- `squirrel`

These are visually distinct from the existing set and avoid reintroducing the removed fox/hamster/penguin problems.

## Performance Guardrails

- Walking animals stay in the existing AppKit/CALayer engine.
- Menu bar rendering uses cached or deterministic `NSImage` generation.
- No SwiftUI timer for menu bar animation.
- No per-frame SwiftUI state updates.
- Progress recomputes only when calendar/todo data changes or at a coarse interval.
- Tests should fail if the walking pet engine regresses to `Timer.publish`/SwiftUI state.

## Privacy Guardrails

This feature must not request Music, Pictures/Photos, Downloads, Network Volumes, user-selected file, network server, or AppleEvents entitlements.

The menu bar icon generation must not read external files at runtime. New animal sprites are bundled resources only.

## Testing

Add or update tests for:

- Today completion calculation: empty day, partial, complete, future items ignored where applicable.
- Menu bar progress icon generation returns non-empty images for neutral, partial, and complete states.
- Animal style list includes the new approved animals and excludes removed fox/hamster/penguin.
- Every exposed animal has 8 normalized `56x56` and `112x112` frames.
- Privacy entitlement regression remains strict.
- Walking animal performance regression remains strict.

## Release Notes

User-facing release note should mention:

- Menu bar can show today's completion progress.
- Animal choices expanded.
- Existing privacy restrictions remain in place.

