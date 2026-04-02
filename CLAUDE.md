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

## Repository Structure

```
Retinder/
├── CLAUDE.md                          # This file
├── ARCHITECTURE.md                    # Deep-dive architecture docs
├── project.yml                        # XcodeGen config (source of truth for project)
├── PairwiseReminders.xcodeproj/       # Generated — do not hand-edit
├── PairwiseReminders/
│   └── Info.plist                     # Generated app metadata
└── Sources/PairwiseReminders/
    ├── PairwiseRemindersApp.swift      # App entry point, DI setup
    ├── Models/
    │   ├── ReminderItem.swift          # Wraps EKReminder with display helpers
    │   └── PairwiseSession.swift       # Central workflow state (ObservableObject)
    ├── Engine/
    │   └── PairwiseEngine.swift        # Merge-sort with async user choice (ObservableObject)
    ├── Services/
    │   ├── RemindersManager.swift      # EventKit read/write wrapper (ObservableObject)
    │   ├── AnthropicService.swift      # Claude API HTTP client
    │   ├── KeychainService.swift       # Secure API key storage
    │   └── RankingStore.swift          # UserDefaults session persistence
    └── Views/
        ├── ContentView.swift           # Root router — switches on PairwiseSession.phase
        ├── OnboardingView.swift        # API key entry screen
        ├── ListPickerView.swift        # Reminder list selection UI
        ├── FilteringView.swift         # AI filtering progress indicator
        ├── PairwiseView.swift          # Tinder-style swipe comparison UI
        └── ResultsView.swift           # Ranked results + apply-to-Reminders options
```

---

## Build & Run

### Prerequisites

- **Xcode 16+** (project targets iOS 26.0)
- **XcodeGen** to regenerate the `.xcodeproj` when `project.yml` changes:
  ```bash
  brew install xcodegen
  ```

### Steps

1. Regenerate project if `project.yml` was modified:
   ```bash
   xcodegen generate
   ```
2. Open the project:
   ```bash
   open PairwiseReminders.xcodeproj
   ```
3. Select the **PairwiseReminders** scheme and run on an iOS 26 simulator or device.

> **Note:** The `.xcodeproj` is committed to the repo for convenience, but `project.yml` is the source of truth. When adding files, targets, or build settings, edit `project.yml` and regenerate.

---

## No Tests Yet

There is currently no test target. If adding tests, use **XCTest** or the **Swift Testing** framework. Key areas that need coverage:

- `PairwiseEngine` — merge-sort logic and `choose(winner:)` path
- `AnthropicService` — request construction and response parsing
- `RemindersManager` — `applyPriorities()` and `applyTopNUrgent()` save discipline

---

## Architecture

### MVVM + Service Layer

| Layer | Type | Injected via |
|-------|------|--------------|
| `PairwiseSession` | ViewModel / state container | `@EnvironmentObject` |
| `RemindersManager` | ViewModel / EventKit wrapper | `@EnvironmentObject` |
| `PairwiseEngine` | ViewModel / sort engine | `@EnvironmentObject` |
| `AnthropicService` | Stateless service | Direct instantiation |
| `KeychainService` | Stateless service | Direct instantiation |
| `RankingStore` | Stateless service | Direct instantiation |

All three `@EnvironmentObject` instances are created in `PairwiseRemindersApp.swift` and injected at the root.

### Workflow Phases

`PairwiseSession.phase` drives the root `ContentView` router:

```
.onboarding  →  .listPicking  →  .filtering  →  .comparing  →  .results
```

- **.onboarding** — shown when no API key is stored in Keychain (optional; user can skip)
- **.listPicking** — user selects one or more reminder lists; optionally resumes a saved ranking
- **.filtering** — `AnthropicService` asks Claude to select the most relevant items; falls back gracefully if unavailable
- **.comparing** — `PairwiseEngine` runs merge-sort, pausing at each comparison for the user to swipe
- **.results** — sorted list displayed; user can apply priorities, due dates, or both to Reminders

### Key Patterns

#### 1. `@MainActor` on all ObservableObjects
All mutations happen on the main actor to ensure thread-safe SwiftUI updates. Never call `store.save()` or publish state changes off the main thread.

#### 2. CheckedContinuation for async user input
`PairwiseEngine` suspends merge-sort at each pair comparison using `withCheckedContinuation`. The UI calls `engine.choose(winner:)` to resume. **Always resume a pending continuation before calling `reset()`** to avoid memory leaks.

#### 3. EventKit save discipline
Mutating `EKReminder` properties requires:
```swift
store.save(item, commit: false)  // per item
store.commit()                    // once after all items
```
Never call `store.commit()` inside a loop. See `RemindersManager.applyPriorities()`.

#### 4. Graceful degradation for AI filtering
If the API key is missing or the request fails, `session.aiFilteringFailed` is set to `true` and the workflow continues with random sampling (capped at 20 items). Never block the workflow on AI availability.

#### 5. Session persistence via `RankingStore`
Rankings are keyed by a sorted, comma-joined string of `EKCalendar` identifiers stored in `UserDefaults` with the prefix `ranking_v1_`. New items are appended; completed items are filtered out on load.

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

The API key is auto-filled on the onboarding screen if the pasteboard contains a string starting with `sk-ant-` (workaround for iOS simulator clipboard isolation).

---

## Data Storage

| Store | Key | Value |
|-------|-----|-------|
| Keychain | service: `com.josmall.PairwiseReminders`, account: `anthropic-api-key` | Raw API key |
| UserDefaults | `ranking_v1_<sorted calendar IDs>` | `[String]` of `calendarItemIdentifier` |

---

## iOS Permissions

`NSRemindersUsageDescription` is declared in `project.yml`. The app requests full Reminders access via `EKEventStore.requestFullAccessToReminders()`.

---

## What Not to Do

- **Do not hand-edit `PairwiseReminders.xcodeproj/`** — regenerate via `xcodegen generate` instead.
- **Do not add SPM package dependencies** without updating `project.yml` under `packages` and `dependencies`.
- **Do not add `store.commit()` inside loops** — it's expensive; commit once after all mutations.
- **Do not force-unwrap optionals** from EventKit — items may be deleted or inaccessible at any time.
- **Do not call async methods that publish state changes off `@MainActor`** — all published properties must be mutated on the main thread.
- **Do not block the pairwise workflow** on network availability — AI filtering is always optional.
