# Verification — Results

**Last verified:** 2026-04-19 against `7a291db`
**Source:** `Sources/PairwiseReminders/Views/ResultsView.swift`
**Related issues:** #103, #114

## Scope
Ranked-list view shown after `PairwiseView` finishes or AI Only mode completes: Elo-sorted rows, drag-to-reorder, per-row edit sheet, refinement flow (re-rank a subset), Apply sheet (tiered priorities + optional due dates), Back to Compare, and Cancel/Done floating glass buttons.

## Golden path
- [ ] Items render in descending Elo order (highest priority at the top).
- [ ] Orange banner appears at the top if `session.seedingFailed && session.mode != .pairwise`.
- [ ] Drag a row to reorder — Elo rating is recalculated in-place; reorder persists via SwiftData.
- [ ] Tap a row with tap-default `.edit` — `ReminderEditSheet` opens.
- [ ] Save an edit — dismissing the sheet reflects changes on the row immediately.
- [ ] Select multiple rows → Refine — session restarts in `.comparing` with only those items, splicing back into ranked positions on finish.
- [ ] Tap Apply floating glass button — Apply sheet opens.
- [ ] Apply sheet: assign High / Medium / Low tiers; toggle due-date defaults per tier.
- [ ] Confirm apply — EventKit priority + due date are saved on each item (batch `commit`).
- [ ] Back to Compare button (top-leading) — continues the comparison session on the current ranked list.
- [ ] Done floating button — resets session to `.idle`, fullScreenCover dismisses.
- [ ] Cancel floating button — same as Done (session reset, cover dismissed) — no EventKit side-effects.

## Edge cases
- [ ] Row heights stay stable during scroll (no jitter from async cell sizing).
- [ ] Refine with 1 item selected — action disabled / no-op (needs at least 2).
- [ ] Apply sheet respects tier defaults from Settings (`defaultHighDueTarget`, etc.).
- [ ] Apply with a custom due date per tier — saves that exact date, not the default.
- [ ] Back to Compare with a 1-item ranked list — action disabled / no-op.
- [ ] Done after a refine flow — ranked list reflects spliced order, not the refined subset alone.
- [ ] Top navigation bar uses `ultraThinMaterial`; floating glass buttons sit on a safe-area inset at the bottom.

## Known gaps
- No per-tier item-count preview on the Apply sheet.
- No "undo apply" — if you apply wrong priorities, you must rerun.
