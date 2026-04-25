# Walking Cat and Review Performance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the unnatural walking cat frames and reduce Review tab scroll jank while preserving Google Calendar sync behavior.

**Architecture:** Keep cat work, Review performance work, and Google Calendar guardrails separate. Cat assets and motion live behind `WalkingCatView` and `CatSettings`; Review metrics move into Review-only pure helpers/snapshots; Google Calendar files remain untouched except for read-only verification and source guardrail tests if needed.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, SwiftPM resources, ImageIO/CoreGraphics tests, generated PNG sprite assets.

---

## Preflight

**Files:**
- Read: `AGENTS.md`
- Read: `docs/plans/2026-04-25-cat-review-performance-design.md`
- Read: `Package.swift`
- Read: `Planit/Views/ReviewView.swift`
- Read: `Planit/Models/TodoGrassStats.swift`
- Read: `Tests/CalendarSyncRegressionTests.swift`

**Step 1: Check workspace state**

Run:

```bash
git status --short --branch
```

Expected: the only pre-existing unrelated change may be `.claude/scheduled_tasks.lock`. Do not stage or revert it.

**Step 2: Create implementation branch**

Run:

```bash
git switch -c codex/cat-review-performance
```

Expected: new branch created from the current approved-design commit.

**Step 3: Bring in `main` content**

Run:

```bash
git merge main --no-edit
```

Expected: `main` content is merged. If conflicts appear, resolve only files needed for this feature and preserve the approved design doc.

**Step 4: Verify merge compiles before new work**

Run:

```bash
swift test --filter CalendarSyncRegressionTests
```

Expected: PASS. If this fails before edits, diagnose the merge first and do not begin cat or Review changes.

---

## Task 1: Cat Frame Geometry Tests

**Files:**
- Modify: `Tests/WalkingCatFrameAlignmentTests.swift`
- Do not modify: `Planit/Services/GoogleCalendarService.swift`
- Do not modify: `Planit/ViewModels/CalendarViewModel.swift`

**Step 1: Write failing tests**

Add tests that reject the current bad `main` frames:

```swift
@Test("cat frames keep transparent side padding")
func framesKeepTransparentSidePadding() throws {
    try assertSidePadding(frameNames: (1...8).map { "frame_R\($0)" }, minimumPadding: 2)
    try assertSidePadding(frameNames: (1...8).map { "frame_R\($0)@2x" }, minimumPadding: 4)
}

@Test("cat frame visual centroids stay near canvas center")
func frameVisualCentroidsStayCentered() throws {
    try assertCentroid(frameNames: (1...8).map { "frame_R\($0)" }, canvasSize: 44, tolerance: 2.5)
    try assertCentroid(frameNames: (1...8).map { "frame_R\($0)@2x" }, canvasSize: 88, tolerance: 5.0)
}
```

Implement helpers in the test file using the existing `CGImage` pixel scan pattern. The centroid helper should average alpha-weighted x positions, not only bbox center.

**Step 2: Verify RED**

Run:

```bash
swift test --filter WalkingCatFrameAlignmentTests
```

Expected: FAIL on current `main` frames because some frames touch canvas edges and drift left.

**Step 3: Do not fix yet**

Commit nothing yet. Move to Task 2 so motion behavior is locked before asset replacement.

---

## Task 2: Cat Motion Tests

**Files:**
- Modify: `Tests/WalkingCatViewTests.swift`
- Later modify: `Planit/Views/WalkingCatView.swift`

**Step 1: Write failing tests**

Add tests for motion behavior:

```swift
@Test("movement is monotonic between turns")
func movementIsMonotonicBetweenTurns() {
    var state = WalkingCatView.MotionState(xPos: 6, isMovingRight: true, frameIndex: 0, frameElapsed: 0)
    var previousX = state.xPos

    for _ in 0..<40 {
        state = WalkingCatView.advancedState(from: state, totalWidth: 400)
        #expect(state.xPos >= previousX)
        previousX = state.xPos
        if state.isMovingRight == false { break }
    }
}

@Test("frame wraps without position jump")
func frameWrapsWithoutPositionJump() {
    let start = WalkingCatView.MotionState(xPos: 80, isMovingRight: true, frameIndex: 7, frameElapsed: 0)
    let next = WalkingCatView.advancedState(from: start, totalWidth: 400, tickDuration: 1.0 / 12.0)

    #expect(next.frameIndex == 0)
    #expect(next.xPos > start.xPos)
}
```

If the final motion design adds turn pause or easing state, add one more test that proves the state machine exposes that behavior explicitly.

**Step 2: Verify RED or baseline**

Run:

```bash
swift test --filter WalkingCatViewTests
```

Expected: existing tests pass; new turn/easing test should fail if the behavior is not implemented yet. If monotonic/wrap already pass, keep them as guardrails and make the turn-behavior test the RED case.

---

## Task 3: Generate and Install Cat Assets

**Files:**
- Replace: `Planit/Resources/frame_R1.png`
- Replace: `Planit/Resources/frame_R1@2x.png`
- Replace: `Planit/Resources/frame_R2.png`
- Replace: `Planit/Resources/frame_R2@2x.png`
- Replace: `Planit/Resources/frame_R3.png`
- Replace: `Planit/Resources/frame_R3@2x.png`
- Replace: `Planit/Resources/frame_R4.png`
- Replace: `Planit/Resources/frame_R4@2x.png`
- Replace: `Planit/Resources/frame_R5.png`
- Replace: `Planit/Resources/frame_R5@2x.png`
- Replace: `Planit/Resources/frame_R6.png`
- Replace: `Planit/Resources/frame_R6@2x.png`
- Replace: `Planit/Resources/frame_R7.png`
- Replace: `Planit/Resources/frame_R7@2x.png`
- Replace: `Planit/Resources/frame_R8.png`
- Replace: `Planit/Resources/frame_R8@2x.png`

**Step 1: Generate source sprite**

Use the `imagegen` skill with a prompt equivalent to:

```text
Use case: stylized-concept
Asset type: macOS menu bar app sprite sheet
Primary request: Create an 8-frame side-view walking cat sprite sequence on a perfectly flat #00ff00 chroma-key background.
Subject: A cute compact black-and-white calendar app cat, consistent body size across frames, clean silhouette, short legs visible, tail balanced.
Style: polished pixel-friendly flat illustration, crisp edges, no text, no shadow, no floor, no background texture.
Layout: one horizontal sprite sheet with 8 equally sized frames, the cat centered in each frame with generous transparent-safe side padding and feet aligned to one baseline.
Avoid: cropped ears, cropped tail, changing cat size, motion blur, perspective changes, extra objects, green in the cat.
```

**Step 2: Remove chroma key**

Use the imagegen chroma-key helper or equivalent local post-processing. Save an intermediate source only under a temporary path, then split frames into exact PNGs.

**Step 3: Split to exact frame assets**

Create 44x44 and 88x88 PNGs with matching frame names. Ensure alpha corners are transparent.

**Step 4: Verify GREEN**

Run:

```bash
swift test --filter WalkingCatFrameAlignmentTests
```

Expected: PASS.

**Step 5: Commit cat assets and tests**

Run:

```bash
git add Tests/WalkingCatFrameAlignmentTests.swift Tests/WalkingCatViewTests.swift Planit/Resources/frame_R*.png
git commit -m "test: lock walking cat frame geometry"
```

---

## Task 4: Improve Cat Motion

**Files:**
- Modify: `Planit/Views/WalkingCatView.swift`
- Modify: `Tests/WalkingCatViewTests.swift`

**Step 1: Implement minimal motion helper changes**

Keep production changes small:

- Keep the public test surface `MotionState` and `advancedState`.
- Add turn behavior only if required by the RED test.
- Avoid adding dependencies.
- Do not touch calendar files.

**Step 2: Verify GREEN**

Run:

```bash
swift test --filter WalkingCatViewTests
swift test --filter WalkingCatFrameAlignmentTests
```

Expected: PASS.

**Step 3: Commit**

Run:

```bash
git add Planit/Views/WalkingCatView.swift Tests/WalkingCatViewTests.swift
git commit -m "fix: smooth walking cat motion"
```

---

## Task 5: Review Section Reorder Math Tests

**Files:**
- Create: `Planit/Models/ReviewSectionLayout.swift`
- Create: `Tests/ReviewSectionLayoutTests.swift`
- Later modify: `Planit/Views/ReviewView.swift`

**Step 1: Write failing tests**

Create tests for pure reorder behavior:

```swift
import Testing
@testable import Calen

@Suite("ReviewSectionLayout")
struct ReviewSectionLayoutTests {
    @Test("pending order moves one slot after threshold")
    func pendingOrderMovesOneSlotAfterThreshold() {
        let order: [ReviewSectionID] = [.habitGraph, .weeklyChart, .todoGrass, .myHabits, .progress, .longTermGoals]
        let result = ReviewSectionLayout.computePendingOrder(
            dragging: .weeklyChart,
            offset: 160,
            sectionOrder: order,
            draggedHeight: 148
        )

        #expect(result.firstIndex(of: .weeklyChart) == 2)
    }
}
```

If `ReviewSectionID` is private today, this test should fail to compile. That is the intended RED: the reorder math is not testable yet.

**Step 2: Verify RED**

Run:

```bash
swift test --filter ReviewSectionLayoutTests
```

Expected: FAIL because the helper/type does not exist or is private.

---

## Task 6: Extract Review Reorder Helper

**Files:**
- Create: `Planit/Models/ReviewSectionLayout.swift`
- Modify: `Planit/Views/ReviewView.swift`
- Modify: `Tests/ReviewSectionLayoutTests.swift`

**Step 1: Implement minimal helper**

Move the testable section IDs and reorder math out of `ReviewView`:

```swift
enum ReviewSectionID: String, CaseIterable, Codable, Identifiable {
    case habitGraph = "habit_graph"
    case weeklyChart = "weekly_chart"
    case todoGrass = "todo_grass"
    case myHabits = "my_habits"
    case progress = "progress"
    case longTermGoals = "long_term_goals"

    var id: String { rawValue }
}

enum ReviewSectionLayout {
    static let defaultOrder: [ReviewSectionID] = [
        .habitGraph, .weeklyChart, .todoGrass, .myHabits, .progress, .longTermGoals
    ]

    static func computePendingOrder(
        dragging sid: ReviewSectionID,
        offset: CGFloat,
        sectionOrder: [ReviewSectionID],
        draggedHeight: CGFloat
    ) -> [ReviewSectionID] {
        guard let fromIdx = sectionOrder.firstIndex(of: sid) else { return sectionOrder }
        let slotH = draggedHeight + 10
        let steps = Int((offset / slotH).rounded())
        let toIdx = max(0, min(sectionOrder.count - 1, fromIdx + steps))
        guard toIdx != fromIdx else { return sectionOrder }
        var result = sectionOrder
        result.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        return result
    }
}
```

Adjust imports for `CGFloat` if needed.

**Step 2: Verify GREEN**

Run:

```bash
swift test --filter ReviewSectionLayoutTests
```

Expected: PASS.

**Step 3: Commit**

Run:

```bash
git add Planit/Models/ReviewSectionLayout.swift Planit/Views/ReviewView.swift Tests/ReviewSectionLayoutTests.swift
git commit -m "refactor: extract review section layout math"
```

---

## Task 7: Review Metrics Snapshot Tests

**Files:**
- Create: `Planit/Models/ReviewMetricsSnapshot.swift`
- Create: `Tests/ReviewMetricsSnapshotTests.swift`
- Modify only if needed: `Tests/TodoGrassStatsTests.swift`

**Step 1: Write failing tests**

Test the weekly stats hot path without depending on SwiftUI rendering:

```swift
@Test("weekly day stats use visible calendar events instead of history cache")
func weeklyDayStatsUseVisibleCalendarEvents() {
    let date = fixedDate(year: 2026, month: 4, day: 25)
    let visibleEvent = makeEvent(id: "visible", start: date, source: .google)
    let staleHistoryEvent = makeEvent(id: "history-only", start: date, source: .google)

    let stats = ReviewMetricsSnapshot.dayStats(
        for: date,
        visibleEvents: [visibleEvent],
        historyEvents: [staleHistoryEvent],
        todos: [],
        reminders: [],
        completedEventIDs: ["visible"],
        calendar: testCalendar
    )

    #expect(stats.done == 1)
    #expect(stats.total == 1)
}
```

Expected RED: `ReviewMetricsSnapshot` does not exist.

**Step 2: Verify RED**

Run:

```bash
swift test --filter ReviewMetricsSnapshotTests
```

Expected: FAIL because helper does not exist.

---

## Task 8: Implement Review Metrics Snapshot

**Files:**
- Create: `Planit/Models/ReviewMetricsSnapshot.swift`
- Modify: `Planit/Views/ReviewView.swift`
- Modify: `Tests/ReviewMetricsSnapshotTests.swift`

**Step 1: Implement pure day stats**

Add a small pure helper that accepts already-selected visible events. Do not import or reference `GoogleCalendarService`.

```swift
struct ReviewDayStats: Equatable {
    var done: Int
    var total: Int
}

enum ReviewMetricsSnapshot {
    static func dayStats(
        for date: Date,
        visibleEvents: [CalendarEvent],
        historyEvents: [CalendarEvent],
        todos: [TodoItem],
        reminders: [TodoItem],
        completedEventIDs: Set<String>,
        calendar: Calendar = .current
    ) -> ReviewDayStats {
        let dayStart = calendar.startOfDay(for: date)
        let localTodos = todos.filter { calendar.startOfDay(for: $0.date) == dayStart }
        let reminderTodos = reminders.filter { calendar.startOfDay(for: $0.date) == dayStart }
        let doneEvents = visibleEvents.filter { completedEventIDs.contains($0.id) }.count
        let doneTodos = (localTodos + reminderTodos).filter(\.isCompleted).count
        return ReviewDayStats(done: doneEvents + doneTodos, total: visibleEvents.count + localTodos.count + reminderTodos.count)
    }
}
```

The unused `historyEvents` parameter is intentional in the first test: it proves the helper ignores the year-scale cache for weekly visible stats. Remove it only if the test can still prove the same contract.

**Step 2: Wire `ReviewView.dayStats`**

In `ReviewView`, use `viewModel.eventsForDate(date)` and the helper. Remove per-day diagnostic logging and per-call `DateFormatter` creation from the hot path.

**Step 3: Verify GREEN**

Run:

```bash
swift test --filter ReviewMetricsSnapshotTests
swift test --filter TodoGrassStatsTests
```

Expected: PASS.

**Step 4: Commit**

Run:

```bash
git add Planit/Models/ReviewMetricsSnapshot.swift Planit/Views/ReviewView.swift Tests/ReviewMetricsSnapshotTests.swift
git commit -m "perf: remove review weekly chart hot path"
```

---

## Task 9: Review Grass and Goal Lookup Optimization

**Files:**
- Modify: `Planit/Models/ReviewMetricsSnapshot.swift`
- Modify: `Planit/Views/ReviewView.swift`
- Modify: `Tests/ReviewMetricsSnapshotTests.swift`

**Step 1: Write failing tests**

Add tests that lock behavior for:

- Todo grass stats computed once from the same input.
- Matched activity title lookup uses prebuilt dictionaries.
- Goal progress inputs preserve counts.

Keep tests behavior-focused; do not test implementation timing directly.

**Step 2: Verify RED**

Run:

```bash
swift test --filter ReviewMetricsSnapshotTests
```

Expected: FAIL for missing snapshot APIs.

**Step 3: Implement minimal snapshot APIs**

Add only helpers required by the tests. Prefer structs of primitive values and existing model IDs. Keep SwiftUI `Color` out of pure snapshot code unless the current model already requires it.

**Step 4: Verify GREEN**

Run:

```bash
swift test --filter ReviewMetricsSnapshotTests
swift test --filter ReviewViewModelTests
```

Expected: PASS.

**Step 5: Commit**

Run:

```bash
git add Planit/Models/ReviewMetricsSnapshot.swift Planit/Views/ReviewView.swift Tests/ReviewMetricsSnapshotTests.swift
git commit -m "perf: cache review metrics outside render paths"
```

---

## Task 10: Google Calendar Guardrails

**Files:**
- Prefer modify: `Tests/CalendarSyncRegressionTests.swift`
- Do not modify unless diagnosing a pre-existing failure: `Planit/ViewModels/CalendarViewModel.swift`
- Do not modify unless diagnosing a pre-existing failure: `Planit/Services/GoogleCalendarService.swift`
- Do not modify unless diagnosing a pre-existing failure: `Shared/Sources/CalenShared/Networking/GoogleCalendarClient.swift`

**Step 1: Run existing guardrails**

Run:

```bash
swift test --filter CalendarSyncRegressionTests
swift test --filter CRUDRegressionTests
swift test --filter AppleMirrorFilteringTests
swift test --filter GoogleCalendarClientTests
```

Expected: PASS.

**Step 2: Add source guardrail only if needed**

If any Review implementation accidentally references Google sync files or modifies them, add a regression test in `CalendarSyncRegressionTests.swift` that proves the intended sync path is still wired.

**Step 3: Commit only if tests changed**

Run only if a guardrail was added:

```bash
git add Tests/CalendarSyncRegressionTests.swift
git commit -m "test: guard google calendar sync paths"
```

---

## Task 11: Full Verification

**Files:**
- Read: all changed files

**Step 1: Run focused tests**

Run:

```bash
swift test --filter WalkingCat
swift test --filter ReviewSectionLayoutTests
swift test --filter ReviewMetricsSnapshotTests
swift test --filter TodoGrassStatsTests
swift test --filter CalendarSyncRegressionTests
swift test --filter CRUDRegressionTests
swift test --filter AppleMirrorFilteringTests
swift test --filter GoogleCalendarClientTests
```

Expected: PASS.

**Step 2: Run full suite**

Run:

```bash
swift test
```

Expected: PASS.

**Step 3: Inspect diff**

Run:

```bash
git status --short
git diff --stat main...HEAD
git diff --name-status main...HEAD
```

Expected: only planned files changed, plus the pre-existing `.claude/scheduled_tasks.lock` remains unstaged if still present.

**Step 4: Final report**

Report:

- Changed files.
- Cat asset prompt and saved asset paths.
- Review simplifications made.
- Tests run and results.
- Confirmation that Google Calendar sync files were not modified, or a clear explanation if any guardrail-only test changed.

---

## Execution Options

After this plan is saved, choose one:

1. **Subagent-Driven (this session)** - dispatch separate implementation agents for cat assets/motion, Review metrics, and verification, then integrate.
2. **Parallel Session (separate)** - open a new session in the implementation branch and use `superpowers:executing-plans` to follow this plan with checkpoints.
