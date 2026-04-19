# Verification — Pairwise comparison

**Last verified:** 2026-04-19 against `855b45e`
**Source:** `Sources/PairwiseReminders/Views/PairwiseView.swift`
**Related issues:** #102, #115

## Scope
The Tinder-style comparison screen: nav bar "Which matters more?" title + progress band below it, two identical `PairwiseCardBody` cards (both swipeable), "About equal" button between the cards, Undo and Done-for-now glass pills in the toolbar, gear icon for Settings.

## Golden path
- [ ] Cards render at **equal width and equal min-height** regardless of content length.
- [ ] Both cards use `Color(.secondarySystemBackground)` backing with soft shadow — good contrast in light and dark mode.
- [ ] Progress band appears immediately below the nav bar, visually connected via matching `ultraThinMaterial`.
- [ ] "Which matters more?" appears as the navigation bar title.
- [ ] "N left" label and progress bar fill as comparisons accrue; "Almost done" appears when `estimatedRemaining == 0`.
- [ ] Tap either card — picks that card; next pair enters from the right.
- [ ] Drag top card right past threshold — top card wins; flies off screen right.
- [ ] Drag top card left past threshold — bottom card wins; top card flies off left.
- [ ] Drag bottom card right past threshold — bottom card wins; flies off right.
- [ ] Drag bottom card left past threshold — top card wins; bottom card flies off left.
- [ ] Sub-threshold drag on either card — card rubber-bands back to centre.
- [ ] Swipe overlay: green + thumbs-up when dragging right ("This one"), blue + arrow-up when dragging left ("Top one").
- [ ] "About equal" button sits between the two cards; tapping gives a 0.5/0.5 Elo update.
- [ ] Undo pill (leading) disables/dims before any choice, enables after first choice.
- [ ] Tapping Undo reverts the last decision.
- [ ] Done for now pill (trailing) ends the session and transitions to Results.
- [ ] Gear icon (trailing) opens Settings sheet.
- [ ] Long-press either card — opens `ReminderEditSheet`.

## Edge cases
- [ ] Edit a reminder via the sheet — on dismiss, the card reflects the edit immediately.
- [ ] Seeding-failed note appears in progress band when `session.seedingFailed && mode != .pairwise`.
- [ ] Reach convergence — "Ranking settled!" state appears; tapping "See Results" transitions to `.done`.
- [ ] Rapid-fire swipes — no stuck mid-transition state.
- [ ] Session with exactly 2 items — one comparison, then converges.
- [ ] Top and bottom card drag states are independent — dragging one card doesn't affect the other's position.

## Known gaps
- No haptic feedback on choice (tracked separately).
- Undo is single-level on the UI even though `EloEngine.decisionHistory` supports multi-step undo via repeated taps.
