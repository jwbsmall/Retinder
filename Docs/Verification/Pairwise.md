# Verification — Pairwise comparison

**Last verified:** 2026-04-19 against `7a291db`
**Source:** `Sources/PairwiseReminders/Views/PairwiseView.swift`
**Related issues:** #102, #115

## Scope
The Tinder-style comparison screen: frosted header ("Which matters more?" + progress + N left), two identical `PairwiseCardBody` cards, drag-to-pick gestures, Undo and Done-for-now glass pills in the toolbar, "About equal" action.

## Golden path
- [ ] Cards render at **equal width and equal min-height** regardless of content length.
- [ ] Both cards have `.ultraThinMaterial` backing with the subtle stroke and soft shadow (Live-Activity look).
- [ ] Tap the top card with tap-default `.choose` — picks it, next pair enters from the right.
- [ ] Tap the bottom card — picks it, next pair enters.
- [ ] Drag bottom card right past threshold — card slides off-screen right with fade + scale, next pair enters.
- [ ] Drag bottom card left past threshold — card slides off-screen left.
- [ ] Sub-threshold drag — card rubber-bands back to centre.
- [ ] Undo pill (leading) disables/dims before any choice, enables after first choice.
- [ ] Tapping Undo reverts the last decision; the pair that was shown before reappears.
- [ ] Done for now pill (trailing) ends the session and transitions to `.done` (Results).
- [ ] Header progress bar fills as comparisons accrue; "N left" updates monotonically.
- [ ] "Almost done" appears when `estimatedRemaining == 0` and the engine is finishing up.
- [ ] "About equal" pill splits a 0.5/0.5 Elo update between the pair.

## Edge cases
- [ ] Change `pairwise_tap_default = .edit` in Settings — tap now opens `ReminderEditSheet`, long-press picks. Swipe still picks regardless of setting.
- [ ] Long-press with tap-default `.choose` — opens `ReminderEditSheet`.
- [ ] Edit a reminder via the sheet — on dismiss, the card reflects the edit immediately (title, notes).
- [ ] Seeding-failed banner appears below the header when `session.seedingFailed && mode != .pairwise`.
- [ ] Reach convergence (keep comparing a short list until `isConverged`) — "Ranking settled!" state appears; tapping "See Results" transitions to `.done`.
- [ ] Rapid-fire swipes (3+ in a second) — no stuck mid-transition state; exit animation completes each time before next pair appears.
- [ ] Drag during the swipe-off animation is ignored (no interference with the chosen-card's exit).
- [ ] Session with exactly 2 items — one comparison, then converges.

## Known gaps
- No haptic feedback on choice (tracked separately).
- Undo is single-level on the UI even though `EloEngine.decisionHistory` supports multi-step undo via repeated taps.
