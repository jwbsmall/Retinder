# Verification — List detail

**Last verified:** 2026-04-19 against `7a291db`
**Source:** `Sources/PairwiseReminders/Views/ListDetailView.swift`
**Related issues:** —

## Scope
Deep-link from a single list header on Home: shows that list's ranked items (above the fold) and unranked items (below), with drag-to-reorder on the ranked section and an entry point into the Prioritise flow scoped to just this list.

## Scope caveat
This view may be supplanted by the Home "expand list" affordance — keep the checklist minimal until the architecture stabilises.

## Golden path
- [ ] Tap a list row on Home → `ListDetailView` pushes onto the navigation stack.
- [ ] Ranked section lists items in descending Elo order.
- [ ] Unranked section lists items with no `RankedItemRecord` or `comparisonCount == 0`.
- [ ] Drag-to-reorder on the ranked section updates Elo ratings and persists.
- [ ] Prioritise entry from this screen pre-fills `session.pendingListIDs` with only this list.

## Edge cases
- [ ] List with zero items — both sections render their empty states cleanly.
- [ ] List with only unranked items — ranked section is hidden or shows an empty-state hint.
- [ ] Back to Home reflects any reorderings made here (ranked sparkline updates).

## Known gaps
- No "run AI seeding" shortcut from this view.
- Drag-to-reorder does not fire haptics.
