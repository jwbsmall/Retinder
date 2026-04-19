# CLAUDE.md — Retinder (PairwiseReminders)

AI assistant guidance for working in this codebase.

---

## Project Overview

**Retinder** is a native iOS app that lets users prioritize their Apple Reminders using a Tinder-style pairwise comparison UI. It uses a merge-sort algorithm to produce a ranked list, optionally pre-filtered by the Claude API to surface the most relevant items first.

- **Bundle ID:** `com.josmall.PairwiseReminders`
- **Platform:** iOS 26.0+
- **Language:** Swift 5.9
- **UI Framework:** SwiftUI
- **External Service:** Anthropic Claude API (`claude-sonnet-4-6`)

---

## Core Principles

These apply to every change made in this codebase, without exception:

- **No dependencies.** Use only Apple's built-in frameworks. No SPM packages, no CocoaPods, no third-party code of any kind.
- **Native/stock UI.** Use SwiftUI's built-in components. Only build custom UI when the system provides nothing adequate for the job.
- **Good UX.** Clear affordances, immediate feedback, graceful error states. Never block the user on non-essential work (network, AI, permissions).
- **Readable code.** Clear names, short focused functions, idiomatic Swift. Obvious over clever.

---

## Repository Structure

```
Retinder/
├── CLAUDE.md                          # This file
├── ARCHITECTURE.md                    # Deep-dive architecture docs
├── PairwiseReminders.xcodeproj/       # Xcode project — edit via Xcode, not by hand
├── PairwiseReminders/
│   └── Info.plist                     # Generated app metadata
└── Sources/PairwiseReminders/
    ├── PairwiseRemindersApp.swift      # App entry point, DI setup
    ├── Models/
    │   ├── ReminderItem.swift          # Wraps EKReminder with display helpers
    │   └── PairwiseSession.swift       # Central workflow state (ObservableObject)
    ├── Engine/
    │   └── EloEngine.swift             # Merge-sort with Elo rating + async user choice (ObservableObject)
    ├── Services/
    │   ├── RemindersManager.swift      # EventKit read/write wrapper (ObservableObject)
    │   ├── AnthropicService.swift      # Claude API HTTP client
    │   ├── KeychainService.swift       # Secure API key storage
    │   └── RankingStore.swift          # UserDefaults session persistence
    └── Views/
        ├── ContentView.swift           # Root view — just renders HomeView + bootstrap task
        ├── HomeView.swift              # Lists/All Reminders toggle; gear → Settings, arrow → Prioritise
        ├── ListDetailView.swift        # Single-list ranked + unranked items, drag-to-reorder
        ├── ListPickerView.swift        # Reminder list selection UI (inside Prioritise flow)
        ├── FilteringView.swift         # AI seeding progress indicator
        ├── PairwiseView.swift          # Tinder-style swipe comparison UI
        ├── ResultsView.swift           # Ranked results + apply-to-Reminders options
        └── SettingsView.swift          # AI key entry and preference settings
```

---

## Build & Run

**Prerequisites:** Xcode 16+ (project targets iOS 26.0).

1. Open the project: `open PairwiseReminders.xcodeproj`
2. Select the **PairwiseReminders** scheme and run on an iOS 26 simulator or device.

To add new source files, use Xcode's New File dialog — it updates `.xcodeproj` automatically.

---

## Tests

No test target yet — **manual verification docs under `Docs/Verification/` are the current safety net** for UI/EventKit/SwiftData behaviour, enforced per-PR by a GitHub Action. See the **Testing & Verification** section below for the full workflow.

When a test target is added, use **Swift Testing** (not XCTest) and prioritise: `EloEngine` (merge-sort + undo + convergence), `AnthropicService` (request/response with fixtures, no network), `PairwiseSession` (phase transitions via a `RemindersManagerProtocol` fake).

---

## Architecture

### MVVM + Service Layer

| Layer | Type | Injected via |
|-------|------|--------------|
| `PairwiseSession` | ViewModel / state container | `@EnvironmentObject` |
| `RemindersManager` | ViewModel / EventKit wrapper | `@EnvironmentObject` |
| `EloEngine` | ViewModel / sort engine | `@EnvironmentObject` |
| `AnthropicService` | Stateless service | Direct instantiation |
| `KeychainService` | Stateless service | Direct instantiation |
| `RankingStore` | Stateless service | Direct instantiation |

All three `@EnvironmentObject` instances are created in `PairwiseRemindersApp.swift` and injected at the root.

### Navigation Structure

`HomeView` is the single root view. It contains two modes (Lists / All Reminders) toggled by a segmented picker at the top. No tab bar.

- **Lists mode** — shows all `EKCalendar` lists with Elo sparklines; tapping drills into `ListDetailView`
- **All Reminders mode** — flattened cross-list view sorted by Elo; supports multi-select → Prioritise
- **Gear icon** (top-right) — opens `SettingsView` as a sheet (API key, AI preference)
- **Arrow icon** (top-right) — opens the Prioritise flow as a `fullScreenCover`

### Prioritise Flow (fullScreenCover)

`PairwiseSession.phase` drives the session router inside the `fullScreenCover`:

```
.idle  →  .seeding  →  .comparing  →  .done
```

- **.idle** — `ListPickerView`: user selects one or more reminder lists; Cancel dismisses the cover
- **.seeding** — `FilteringView`: AI seeding in progress; falls back gracefully if unavailable
- **.comparing** — `PairwiseView`: merge-sort pauses at each pair for the user to swipe or choose
- **.done** — `ResultsView`: ranked list displayed; "Done" resets session → phase = .idle → cover dismisses

`session.pendingListIDs` is the bridge from `ListDetailView` / All Reminders multi-select → Prioritise flow. Setting it non-empty from HomeView's `onChange` opens the cover and pre-populates `ListPickerView`.

### Key Patterns

#### 1. `@MainActor` on all ObservableObjects
All mutations happen on the main actor to ensure thread-safe SwiftUI updates. Never call `store.save()` or publish state changes off the main thread.

#### 2. CheckedContinuation for async user input
`EloEngine` suspends merge-sort at each pair comparison using `withCheckedContinuation`. The UI calls `engine.choose(winner:)` to resume. **Always resume a pending continuation before calling `reset()`** to avoid memory leaks.

#### 3. EventKit save discipline
Mutating `EKReminder` properties requires:
```swift
store.save(item, commit: false)  // per item
store.commit()                    // once after all items
```
Never call `store.commit()` inside a loop. See `RemindersManager.applyPriorities()`.

#### 4. Graceful degradation for AI seeding
If the API key is missing or the request fails, `session.seedingFailed` is set to `true` and the workflow continues with default Elo ratings (1000). Never block the workflow on AI availability. On-device Foundation Models are tried first (if available), then the Anthropic API, based on `session.aiPreference`.

#### 5. Elo persistence via SwiftData (`RankedItemRecord`)
Elo ratings, K-factors, and comparison counts are persisted in SwiftData keyed by `EKReminder.calendarItemIdentifier`. Loaded into `ReminderItem` at fetch time; written back by `EloEngine.finish(context:)` at session end or bail-out.

---

## Code Conventions

### Naming

| Concept | Convention |
|---------|-----------|
| Types, enums, protocols | `PascalCase` |
| Properties, functions, local vars | `camelCase` |
| Observable state holders | `*Manager` (stateful, holds `EKEventStore`) or `*Session` |
| Stateless helpers | `*Service` or `*Store` |
| SwiftUI views | `*View` suffix |

### File Organization

- One primary type per file, named after the type.
- Nested sub-views live at the bottom of their parent view file (private structs).
- Services are single-responsibility — one external integration or one storage concern per file.

### SwiftUI Patterns

- Use `@EnvironmentObject` for shared session/manager state; avoid passing them as explicit parameters.
- Prefer `.task {}` over `.onAppear {}` for async work.
- Keep view bodies lean — extract sub-views rather than deeply nesting.

---

## External API: Anthropic Claude

- **Endpoint:** `https://api.anthropic.com/v1/messages`
- **Model:** `claude-sonnet-4-6`
- **API version header:** `anthropic-version: 2023-06-01`
- **Auth header:** `x-api-key: <stored in Keychain>`
- **Key storage:** Keychain service `com.josmall.PairwiseReminders`, account `anthropic-api-key`

The API key is entered in `SettingsView` (gear icon in HomeView). No onboarding screen — the app works without a key (AI seeding is skipped).

---

## Data Storage

| Store | Key | Value |
|-------|-----|-------|
| Keychain | service: `com.josmall.PairwiseReminders`, account: `anthropic-api-key` | Raw API key |
| UserDefaults | `ranking_v1_<sorted calendar IDs>` | `[String]` of `calendarItemIdentifier` |

---

## iOS Permissions

`NSRemindersUsageDescription` is declared in `PairwiseReminders/Info.plist`. The app requests full Reminders access via `EKEventStore.requestFullAccessToReminders()`.

---

## Testing & Verification

### Automated tests

There is currently no test target. If adding one, use **Swift Testing** (Xcode 16+) in preference to XCTest. Highest-leverage seams to cover first: `EloEngine` (merge-sort, undo, convergence), `AnthropicService` (request construction, fixture-based response decoding), and `PairwiseSession` phase transitions (introduce a `RemindersManagerProtocol` so the session can be tested against a fake).

### Verification docs (manual checklists)

Because the UI surface is SwiftUI + EventKit-bound, manual verification covers the gap between unit tests and shipped behaviour. One markdown doc per user-facing surface lives under [`Docs/Verification/`](Docs/Verification/README.md). Every doc follows the same shape: Scope → Golden path → Edge cases → Known gaps → `Last verified: YYYY-MM-DD against <short-sha>`.

**Any PR that changes a file under `Sources/PairwiseReminders/Views/` must update the matching verification doc.** Even a no-behaviour-change PR should bump the `Last verified` date + commit hash when you re-run the checklist.

The mapping view → doc is enforced by `.github/workflows/verification-sync.yml` (via `.github/scripts/check-verification.sh`). It blocks PRs that touch a view file without touching its doc. Escape hatch: add `[verification: n/a — <reason>]` to the PR body for pure refactors / non-visible changes.

**Adding a new view file:** create the matching `Docs/Verification/<Surface>.md`, add a bullet to the PR template under **Surfaces touched**, and add the pair to `VIEW_TO_DOC` in `check-verification.sh`. The workflow will fail until all three are done.

---

## Git & GitHub Workflow

- Work on feature branches, never directly on `main`.
- After pushing a completed batch of work to a feature branch, **always create a GitHub PR** using `mcp__github__create_pull_request` — unless one already exists for that branch, or the user explicitly asks not to.
- Check for an existing open PR with `mcp__github__list_pull_requests` before creating a new one.
- PR title should be concise (≤70 chars). Body should bullet the changes and include a test plan checklist.
- **Every user request that is not implemented immediately must have a GitHub issue.** Before ending a working session, check the conversation for any unresolved requests and create issues for them. Title: concise description. Body: the user's words + relevant context.

---

## What Not to Do

- **Do not add any third-party dependencies** — no SPM packages, no CocoaPods, no external code of any kind.
- **Do not add `store.commit()` inside loops** — it's expensive; commit once after all mutations.
- **Do not force-unwrap optionals** from EventKit — items may be deleted or inaccessible at any time.
- **Do not call async methods that publish state changes off `@MainActor`** — all published properties must be mutated on the main thread.
- **Do not block the pairwise workflow** on network availability — AI filtering is always optional.
