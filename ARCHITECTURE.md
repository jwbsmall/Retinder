# Retinder — Architecture

## What it does

Fetches your incomplete Apple Reminders, optionally asks Claude to shortlist the ~15 most
important ones, then runs a pairwise ("which of these two is more urgent?") merge-sort
comparison to produce a ranked list. You can then write that ranking back to Reminders as
priorities in one tap.

---

## Workflow phases

```
listPicking ──► filtering ──► comparing ──► results
     │               │
     │         (API fails →
     │          fallback to
     │          all items, cap 20)
     │
  (Start Over resets to here)
```

---

## File map

```
PairwiseReminders/
├── PairwiseReminders/
│   └── Info.plist                Generated iOS metadata: display name ("Retinder"),
│                                 Reminders usage description, orientations, etc.
│
└── Sources/PairwiseReminders/
    │
    ├── PairwiseRemindersApp.swift   @main entry point. Creates and injects the three
    │                                shared state objects via @EnvironmentObject:
    │                                  • PairwiseSession  (what phase are we in?)
    │                                  • RemindersManager (EventKit wrapper)
    │                                  • PairwiseEngine   (comparison algorithm)
    │
    ├── Models/
    │   ├── ReminderItem.swift       Lightweight struct wrapping one EKReminder.
    │   │                            Holds: id, title, listName, dueDate, aiReasoning,
    │   │                            sortRank, and a reference to the live EKReminder
    │   │                            (reference type — mutations are visible to the store).
    │   │                            Also computes priorityLabel / priorityColor from sortRank.
    │   │
    │   └── PairwiseSession.swift    @MainActor ObservableObject. The single source of truth
    │                                for the session workflow. Published properties:
    │                                  • phase           (listPicking/filtering/comparing/results)
    │                                  • selectedListIDs (which Reminders lists to pull from)
    │                                  • allItems        (raw fetch from EventKit)
    │                                  • filteredItems   (AI shortlist, or fallback sample)
    │                                  • rankedItems     (final sorted order)
    │                                  • aiFilteringFailed, filteringError, applyError, didApply
    │
    ├── Engine/
    │   └── PairwiseEngine.swift     @MainActor ObservableObject. Implements merge-sort with
    │                                human comparisons instead of a comparator function.
    │                                  • start(with:) — kicks off async merge sort
    │                                  • currentPair   — the two items currently shown
    │                                  • choose(winner:) — resumes the suspended sort task
    │                                  • isComplete / sortedItems — fires when done
    │                                  • reset() — clears all state for reuse
    │                                Uses CheckedContinuation to suspend the sort Task while
    │                                waiting for the user's tap/swipe choice.
    │
    ├── Services/
    │   ├── RemindersManager.swift   @MainActor ObservableObject. All EventKit I/O:
    │   │                              • requestAccess()           ask for Reminders permission
    │   │                              • fetchLists()              available reminder lists
    │   │                              • fetchIncompleteReminders() pull items from chosen lists
    │   │                              • applyPriorities()         tiered (top 25% High, etc.)
    │   │                              • applyTopNUrgent()         top N → High, rest → None
    │   │                            IMPORTANT: must call store.save(reminder, commit: false)
    │   │                            for each item before store.commit() — just mutating
    │   │                            properties without save() is silently ignored by EventKit.
    │   │
    │   ├── AnthropicService.swift   Stateless struct. Sends reminder titles to Claude via
    │   │                            the Anthropic Messages API and parses a JSON shortlist
    │   │                            back. Throws on any non-200 response — callers catch and
    │   │                            fall back gracefully (see FilteringView).
    │   │
    │   └── KeychainService.swift    Thin wrapper: save/load the Anthropic API key in the
    │                                device Keychain.
    │
    └── Views/
        ├── ContentView.swift        Root router. Checks for stored API key → shows Onboarding
        │                            if missing. Otherwise routes on session.phase:
        │                              .listPicking → ListPickerView
        │                              .filtering   → FilteringView
        │                              .comparing   → PairwiseView
        │                              .results     → ResultsView
        │
        ├── OnboardingView.swift     API key entry screen. onAppear auto-fills from UIPasteboard
        │                            if clipboard starts with "sk-ant-" (works around Xcode 16.x
        │                            simulator clipboard isolation bug).
        │
        ├── ListPickerView.swift     Lets the user pick which Reminder lists to include.
        │                            Fetches allItems via RemindersManager then advances phase.
        │
        ├── FilteringView.swift      Shows a progress animation while calling AnthropicService.
        │                            On API failure: sets aiFilteringFailed = true, falls back
        │                            to a random sample of up to 20 items, always advances to
        │                            .comparing (never blocks the user).
        │
        ├── PairwiseView.swift       Tinder-style swipe UI.
        │                              • Big swipeable card = left item from engine.currentPair
        │                              • Drag right → left item wins (more urgent)
        │                              • Drag left  → right item wins (less urgent)
        │                              • Tap small bottom card → right item wins directly
        │                              • Swipe threshold: 100pt. Snaps back if under threshold.
        │                            Listens to engine.isComplete → assigns sortRank to each
        │                            item and advances to .results.
        │
        └── ResultsView.swift        Ranked list + action bottom bar.
                                       • "Apply to Reminders…" → half-sheet (ApplySheet)
                                         with two modes:
                                           - Tiered: top 25% High / Medium / Low / None
                                           - Urgent: top N → High, rest → None (pick N)
                                       • "Copy list" → numbered plain-text to clipboard
                                       • "Start Over" → resets engine + session
```

---

## Data flow summary

```
EventKit ──► RemindersManager.fetchIncompleteReminders()
                │
                ▼
         PairwiseSession.allItems
                │
                ▼
         AnthropicService.filterReminders()   (or fallback sample)
                │
                ▼
         PairwiseSession.filteredItems
                │
                ▼
         PairwiseEngine.start(with: filteredItems)
           [merge sort pauses at each comparison]
           user swipes/taps in PairwiseView
           engine.choose(winner:) resumes sort
                │
                ▼
         PairwiseEngine.sortedItems
         → PairwiseSession.rankedItems (with sortRank assigned)
                │
                ▼
         ResultsView → ApplySheet
         → RemindersManager.applyPriorities() or applyTopNUrgent()
         → EKEventStore.commit()
```

---

## Key constraints / gotchas

- **EventKit save discipline**: mutating `EKReminder.priority` alone does nothing. You must call
  `store.save(reminder, commit: false)` per item, then `store.commit()` once at the end.

- **MainActor throughout**: PairwiseSession, PairwiseEngine, and RemindersManager are all
  `@MainActor`. The sort Task in PairwiseEngine runs on the MainActor so published property
  mutations are always UI-safe.

- **CheckedContinuation**: PairwiseEngine suspends the merge-sort Task with a continuation
  stored in `pendingContinuation`. `choose(winner:)` resumes it. `reset()` always resumes
  any pending continuation before discarding it to avoid a Task leak.

- **AI filtering is optional**: if the API key is missing or the call fails for any reason
  (network, 402 out-of-credits, rate limit), the app falls back silently and proceeds with
  all items (capped at 20 random). `session.aiFilteringFailed` flags this for a subtle UI note.
