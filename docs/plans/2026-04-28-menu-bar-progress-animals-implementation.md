# Menu Bar Progress And Animal Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a macOS menu bar today's completion progress indicator and expand the walking animal choices with a small, normalized sprite set.

**Architecture:** Keep the walking pet engine in the existing AppKit/CALayer path and add a separate pure progress model plus status-item image renderer. The menu bar icon should be generated from deterministic inputs and updated from `PlanitApp`/`CalendarViewModel` data without a high-frequency animation timer.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, CALayer, Swift Testing, SwiftPM resources.

---

### Task 1: Lock Today's Completion Progress Rules

**Files:**
- Create: `Tests/MenuBarProgressTests.swift`
- Create or Modify: `Planit/Models/MenuBarProgress.swift`

**Step 1: Write the failing tests**

Create `Tests/MenuBarProgressTests.swift` with tests for:

```swift
import Foundation
import Testing
@testable import Calen

@Suite("Menu bar progress")
struct MenuBarProgressTests {
    @Test("empty today uses neutral progress")
    func emptyTodayUsesNeutralProgress() {
        let snapshot = MenuBarProgressSnapshot.make(todayTotal: 0, todayCompleted: 0)
        #expect(snapshot.state == .neutral)
        #expect(snapshot.percent == nil)
    }

    @Test("partial today rounds to nearest percent")
    func partialTodayRoundsToNearestPercent() {
        let snapshot = MenuBarProgressSnapshot.make(todayTotal: 3, todayCompleted: 2)
        #expect(snapshot.state == .active)
        #expect(snapshot.percent == 67)
    }

    @Test("completed today clamps at 100 percent")
    func completedTodayClampsAtOneHundred() {
        let snapshot = MenuBarProgressSnapshot.make(todayTotal: 2, todayCompleted: 5)
        #expect(snapshot.percent == 100)
    }
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter MenuBarProgressTests
```

Expected: FAIL because `MenuBarProgressSnapshot` does not exist.

**Step 3: Implement the minimal model**

Create `Planit/Models/MenuBarProgress.swift`:

```swift
import Foundation

struct MenuBarProgressSnapshot: Equatable {
    enum State: Equatable {
        case neutral
        case active
    }

    let completed: Int
    let total: Int
    let percent: Int?
    let state: State

    static func make(todayTotal: Int, todayCompleted: Int) -> MenuBarProgressSnapshot {
        let safeTotal = max(0, todayTotal)
        let safeCompleted = min(max(0, todayCompleted), safeTotal)
        guard safeTotal > 0 else {
            return MenuBarProgressSnapshot(completed: 0, total: 0, percent: nil, state: .neutral)
        }
        let percent = Int((Double(safeCompleted) / Double(safeTotal) * 100).rounded())
        return MenuBarProgressSnapshot(completed: safeCompleted, total: safeTotal, percent: percent, state: .active)
    }
}
```

**Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter MenuBarProgressTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Planit/Models/MenuBarProgress.swift Tests/MenuBarProgressTests.swift
git commit -m "test: add menu bar progress model"
```

---

### Task 2: Derive Today's Progress From Existing View Model Data

**Files:**
- Modify: `Planit/Models/MenuBarProgress.swift`
- Test: `Tests/MenuBarProgressTests.swift`

**Step 1: Add failing tests for today filtering**

Extend tests to cover:

- Today's incomplete todo counts toward denominator only.
- Today's completed todo counts toward numerator and denominator.
- Tomorrow's todo is ignored.
- All-day or future calendar events should not accidentally inflate completed work unless existing completion state says they are done.

Use small `TodoItem` and `CalendarEvent` fixtures already available in tests where possible.

**Step 2: Run focused tests**

```bash
swift test --filter MenuBarProgressTests
```

Expected: FAIL until helper exists.

**Step 3: Implement a pure helper**

Add a static helper such as:

```swift
static func make(
    todos: [TodoItem],
    reminders: [TodoItem],
    events: [CalendarEvent],
    completedEventIDs: Set<String>,
    now: Date = Date(),
    calendar: Calendar = .current
) -> MenuBarProgressSnapshot
```

Rules:

- Include todos/reminders whose scheduled date is today.
- Count completed todos/reminders as completed.
- Include non-all-day calendar events scheduled today only if they are not purely future placeholders.
- Count calendar events completed only when `completedEventIDs` contains the event ID.
- Clamp numerator/denominator with `make(todayTotal:todayCompleted:)`.

**Step 4: Run focused tests**

```bash
swift test --filter MenuBarProgressTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Planit/Models/MenuBarProgress.swift Tests/MenuBarProgressTests.swift
git commit -m "feat: compute today menu bar progress"
```

---

### Task 3: Add Menu Bar Progress Icon Renderer

**Files:**
- Create: `Planit/Models/MenuBarProgressIcon.swift`
- Test: `Tests/MenuBarProgressTests.swift`
- Modify: `Package.swift` only if the new file is not picked up automatically.

**Step 1: Write failing renderer tests**

Add tests:

```swift
@Test("progress icon renders non-empty images")
func progressIconRendersNonEmptyImages() throws {
    for snapshot in [
        MenuBarProgressSnapshot.make(todayTotal: 0, todayCompleted: 0),
        MenuBarProgressSnapshot.make(todayTotal: 4, todayCompleted: 1),
        MenuBarProgressSnapshot.make(todayTotal: 4, todayCompleted: 4),
    ] {
        let image = MenuBarProgressIcon.makeImage(snapshot: snapshot, updateAvailable: false)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }
}
```

**Step 2: Run failing test**

```bash
swift test --filter MenuBarProgressTests
```

Expected: FAIL because `MenuBarProgressIcon` does not exist.

**Step 3: Implement renderer**

Create `MenuBarProgressIcon` using AppKit:

- Canvas size around `28x18`.
- Draw battery outline and cap.
- Fill width based on percent.
- Neutral state uses existing `StatusBarIcon` fallback or gray battery.
- Update available can draw a small accent dot without replacing the progress icon.
- Cache by `(percent or neutral, updateAvailable, scale)`.

**Step 4: Run focused tests**

```bash
swift test --filter MenuBarProgressTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Planit/Models/MenuBarProgressIcon.swift Tests/MenuBarProgressTests.swift
git commit -m "feat: render menu bar progress icon"
```

---

### Task 4: Wire Progress Icon Into `PlanitApp`

**Files:**
- Modify: `Planit/PlanitApp.swift`
- Modify: `Planit/ViewModels/CalendarViewModel.swift` only if a small published progress snapshot is cleaner.
- Test: `Tests/MenuBarProgressTests.swift` or a focused source-level regression test.

**Step 1: Add source-level regression test**

Add a test that checks:

- `PlanitApp` no longer only calls `makeStatusBarImage(update:)`.
- Menu bar progress rendering is driven by `MenuBarProgressSnapshot`.
- No `Timer.publish` is introduced for the menu bar.

**Step 2: Run focused tests**

```bash
swift test --filter MenuBarProgressTests
```

Expected: FAIL until wiring exists.

**Step 3: Implement wiring**

In `PlanitApp`:

- Keep `statusItem` creation.
- Replace or overload `makeStatusBarImage(update:)` with `makeStatusBarImage(progress:update:)`.
- Subscribe to relevant `CalendarViewModel` published data or expose a small `@Published` progress snapshot from `CalendarViewModel`.
- Refresh icon when data changes and when updater state changes.
- Do not add high-frequency timers.

**Step 4: Run focused tests**

```bash
swift test --filter MenuBarProgressTests
```

Expected: PASS.

**Step 5: Manual run**

```bash
scripts/run-dev.sh
```

Expected: Calen launches and the menu bar icon appears.

**Step 6: Commit**

```bash
git add Planit/PlanitApp.swift Planit/ViewModels/CalendarViewModel.swift Tests/MenuBarProgressTests.swift
git commit -m "feat: show today progress in menu bar"
```

---

### Task 5: Add New Animal Styles

**Files:**
- Modify: `Planit/Models/AnimalSettings.swift`
- Modify: `Planit/Resources/*/Localizable.strings`
- Add: `Planit/Resources/CatSprites/character_panda_R1.png` through `R8@2x.png`
- Add: `Planit/Resources/CatSprites/character_turtle_R1.png` through `R8@2x.png`
- Add: `Planit/Resources/CatSprites/character_squirrel_R1.png` through `R8@2x.png`
- Test: `Tests/WalkingAnimalViewTests.swift`

**Step 1: Add failing style-list test**

Update `animalStylesAreStable` expected IDs:

```swift
[
    "cat",
    "dog",
    "cheetah",
    "duck",
    "rabbit",
    "panda",
    "turtle",
    "squirrel",
]
```

**Step 2: Run focused tests**

```bash
swift test --filter WalkingAnimalView
```

Expected: FAIL until styles and assets exist.

**Step 3: Add enum cases and frame mapping**

Modify `WalkingAnimalStyle`:

```swift
case panda
case turtle
case squirrel
```

Map frames through the generic `character_\(rawValue)_R\(index)` path.

**Step 4: Add localized names**

Add keys for every locale:

```text
"settings.animal.style.panda" = "...";
"settings.animal.style.turtle" = "...";
"settings.animal.style.squirrel" = "...";
```

Use Korean base names:

- panda = `판다`
- turtle = `거북이`
- squirrel = `다람쥐`

**Step 5: Add normalized sprites**

Generate or curate `56x56`/`112x112` 8-frame PNGs. Before active insertion, inspect the preview images manually. Only copy into `Planit/Resources/CatSprites` after the sprites pass visual review.

**Step 6: Run focused tests**

```bash
swift test --filter WalkingAnimalView
scripts/verify-localizations.sh
```

Expected: PASS.

**Step 7: Commit**

```bash
git add Planit/Models/AnimalSettings.swift Planit/Resources Tests/WalkingAnimalViewTests.swift
git commit -m "feat: add more walking animal styles"
```

---

### Task 6: Final Verification

**Files:**
- No intended code edits.

**Step 1: Run full test suite**

```bash
swift test
```

Expected: PASS.

**Step 2: Run localization verification**

```bash
scripts/verify-localizations.sh
```

Expected: all 29 languages complete.

**Step 3: Run release build**

```bash
swift build -c release
```

Expected: PASS.

**Step 4: Run app locally**

```bash
scripts/run-dev.sh
```

Expected:

- App launches.
- Settings animal tab shows old and new animals.
- Menu bar icon reflects today's completion progress.
- No Music/Photos/Pictures/Downloads/Network TCC logs.

**Step 5: Check git state**

```bash
git status --branch --short
git log --oneline --decorate -8
```

Expected: clean working tree on the intended branch.

**Step 6: Commit any final polish**

Only if verification required a fix:

```bash
git add <changed-files>
git commit -m "fix: polish menu bar progress animals"
```

