# Verification — Prioritise start

**Last verified:** 2026-04-19 against `7a291db`
**Source:** `Sources/PairwiseReminders/Views/ListPickerView.swift`, `Sources/PairwiseReminders/Views/FilteringView.swift`, `PrioritiseOptionsSheet` in `HomeView.swift`
**Related issues:** —

## Scope
The flow that runs before `PairwiseView` opens: list picker (when entered without a pre-selection), options sheet (mode, AI criteria, top-N), and the `FilteringView` progress screen during AI seeding.

## Golden path
- [ ] Tap Prioritise pill from Home with a selection → options sheet opens preset to the saved mode (AI Only / Pairwise / Both).
- [ ] Change mode in the segmented picker — Criteria field shows/hides correctly (hidden for Pairwise).
- [ ] Enter criteria (e.g. "work tasks") and tap Start — session transitions to `.seeding`, `FilteringView` appears with progress indicator.
- [ ] With API key configured, seeding completes within a few seconds and transitions to `.comparing` (Both/Pairwise) or `.done` (AI Only).
- [ ] Top-N enabled (e.g. 20) — only the top 20 items by AI rank proceed into pairwise comparison.
- [ ] "Back" / cancel from `FilteringView` cleanly returns to `.idle` and dismisses the cover.

## Edge cases
- [ ] No API key set — a footer hint reads "No API key. Add one in Settings → AI."
- [ ] AI Only mode with no API key — start button should be disabled, or the flow falls back gracefully and shows the seeding-failed banner.
- [ ] API request fails (network off, bad key) — `session.seedingFailed` is set, the flow continues into pairwise with default Elo ratings, and the banner "AI seeding unavailable — using default ratings" appears on the Pairwise header.
- [ ] Pairwise-only mode + top-N — top-N is applied by existing Elo rating (from prior sessions), not AI seed rank.
- [ ] Start Prioritise with fewer than 2 items in the selection — flow transitions to `.idle` silently (nothing to compare).
- [ ] Criteria field blank — seeding still runs (criteria is optional).

## Known gaps
- No visible "time remaining" during seeding — only a spinner.
