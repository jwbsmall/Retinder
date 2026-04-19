# Verification — Home

**Last verified:** 2026-04-19 against `855b45e`
**Source:** `Sources/PairwiseReminders/Views/HomeView.swift`
**Related issues:** #101, #106, #114

## Scope
The main landing screen: segmented mode picker (Lists / All Reminders / Due Date), selection mode, prioritise entry, universal SparklinePill sparklines on list headers and item rows, and row interactions (tap = edit out of select mode, long-press = toggle select).

## Golden path
- [ ] Toggle between Lists / All Reminders / Due Date — content updates, no flicker.
- [ ] Lists mode: each list header shows a combined sparkline (HStack of `SparklinePill`s) for items with `comparisonCount > 0`; pills are fixed max-height with proportional fill, ordered low → high.
- [ ] Sparkline fills are scaled against the *global* min/max across all lists, so different lists are visually comparable.
- [ ] Expand a list — reminder rows appear; each ranked row shows a single `SparklinePill` on the right reflecting its relative Elo strength.
- [ ] Tap a row (out of select mode) — opens `ReminderEditSheet`.
- [ ] Long-press a row — toggles selection on that row.
- [ ] Tap the Prioritise pill at the bottom with a selection — Prioritise flow opens prefilled.
- [ ] Tap the Prioritise pill with nothing selected — silently enters Select mode (no alert).
- [ ] In Select mode, tap a list header row — all items in that list become selected (cascade).
- [ ] Deselect a list header — every item under it is deselected.
- [ ] Cancel button appears whenever the selection is non-empty; tapping it clears the selection without leaving Select mode incorrectly.
- [ ] Gear icon opens `SettingsView` as a sheet.
- [ ] Bottom Prioritise pill is a floating glass capsule that stays above content on scroll.
- [ ] Top navigation bar uses `ultraThinMaterial` (frosted) and the title ("Retinder") transitions correctly on scroll.
- [ ] Filter/group icon (line.3.horizontal.decrease.circle) opens the Group By / Sort By menu.

## Edge cases
- [ ] No lists at all (fresh install, no permission) — empty state renders; Prioritise pill is disabled/hidden.
- [ ] A list with zero ranked items — sparkline is absent (not a flat track).
- [ ] All Reminders mode with 100+ items — scroll is smooth.
- [ ] Due Date mode — items group correctly under Today / Tomorrow / This Week / Later / No date.
- [ ] Long reminder title (multiline) — row height grows; layout doesn't clip.
- [ ] Section gap between list groups is tight (`.listSectionSpacing(.compact)`), not the default chunky iOS grouped inset.
- [ ] Unranked items (comparisonCount == 0) show no sparkline pill.

## Known gaps
- Widget surface not yet built (tracked separately).
