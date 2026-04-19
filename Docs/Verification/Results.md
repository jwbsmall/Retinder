# Verification — Results

**Last verified:** 2026-04-19 against `206c92e`
**Source:** `Sources/PairwiseReminders/Views/ResultsView.swift`
**Related issues:** #103, #114

## Scope
Ranked-list view shown after `PairwiseView` finishes or AI Only mode completes: Elo-sorted rows with `SparklinePill` strength indicators, drag-to-reorder, per-row detail/edit, refinement flow, Apply sheet (tiered priorities + optional due dates), Back to Compare, and Done/Apply floating glass buttons.

## Golden path
- [ ] Items render in descending Elo order (highest priority at the top).
- [ ] Each row shows a `SparklinePill` on the right reflecting its relative Elo strength (no rank number badges).
- [ ] AI confidence percentage appears alongside the list name when present (e.g. "Work · 87%").
- [ ] Orange banner appears at the top if `session.seedingFailed && session.mode != .pairwise`.
- [ ] Drag a row to reorder — Elo rating is recalculated in-place; reorder persists via SwiftData.
- [ ] Tap a row — `ItemDetailSheet` opens (always, regardless of any settings).
- [ ] Long-press a row — enters selection mode and toggles that row.
- [ ] Select multiple rows → Refine — session restarts in `.comparing` with only those items.
- [ ] Tap Apply floating glass button — Apply sheet opens with title "Apply".
- [ ] Apply sheet: assign High / Medium / Low tiers; toggle due-date defaults per tier.
- [ ] Confirm apply — EventKit priority + due date are saved on each item (batch `commit`).
- [ ] Back to Compare button (top-leading) — continues the comparison session.
- [ ] Done floating button — resets session to `.idle`, fullScreenCover dismisses.

## Edge cases
- [ ] Row heights stay stable during scroll (no jitter from async cell sizing).
- [ ] Refine with 1 item selected — action disabled (needs at least 2).
- [ ] Apply sheet respects tier defaults from Settings.
- [ ] Apply with a custom due date per tier — saves that exact date.
- [ ] Top navigation bar uses `ultraThinMaterial`; floating glass buttons sit on a safe-area inset at the bottom.
- [ ] Session stopped early — ranked items still show sparkline pills and confidence; Apply is available.
- [ ] Respects `accessibilityReduceMotion`: "Applied to Reminders!" banner appears via ease instead of spring.

## Known gaps
- No "undo apply" — if you apply wrong priorities, you must rerun.
- No per-tier item-count preview on the Apply sheet.
