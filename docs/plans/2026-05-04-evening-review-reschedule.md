# Evening Review Reschedule Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an evening review flow that recommends where missed todos should move before applying changes.

**Architecture:** Reuse the existing `SmartSchedulerService` for deterministic scheduling, add a small reschedule recommendation model, and surface recommendations in `ReviewView` only for evening review. Keep movement explicit: todos move only after the user confirms the recommendation.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing, existing Planit services.

---

### Task 1: Lock Scheduling Behavior

**Files:**
- Test: `Tests/CalenTests.swift`
- Modify: `Planit/Services/SmartSchedulerService.swift`

**Steps:**
1. Add a failing Swift Testing case for backlog recommendations that prefer lower-load future days and expose per-todo target dates plus reasons.
2. Run `swift test --filter EveningReschedule`.
3. Add the minimal scheduling API needed by review UI.
4. Run `swift test --filter EveningReschedule`.

### Task 2: Connect Evening Review

**Files:**
- Modify: `Planit/Services/ReviewService.swift`
- Modify: `Planit/Models/GoalModels.swift`

**Steps:**
1. Add a review-facing recommendation model.
2. Generate evening backlog recommendations from incomplete local todos and future calendar load.
3. Keep existing event-completion suggestions intact.
4. Run targeted tests.

### Task 3: Add Confirmation UI

**Files:**
- Modify: `Planit/Views/ReviewView.swift`

**Steps:**
1. Add an evening reschedule card before tomorrow planning.
2. Show grouped target dates, item titles, and lightweight reason text.
3. Add “추천대로 이동” and “이번엔 넘기기” actions.
4. Apply moves through `CalendarViewModel.moveTodoBySystem`.

### Task 4: Stop Silent Auto-Move

**Files:**
- Modify: `Planit/Services/MidnightRolloverService.swift`
- Modify: `Planit/ViewModels/CalendarViewModel.swift`

**Steps:**
1. Change midnight behavior away from silent date mutation.
2. Make manual “지금 재배치” route through the review recommendation path where possible.
3. Verify no unrelated menu bar or animal resource changes.

### Task 5: Verify

**Commands:**
- `swift test --filter EveningReschedule`
- `swift test --skip codexTranscript_ignoresEchoedUserPromptJSON`
- `swift build`
