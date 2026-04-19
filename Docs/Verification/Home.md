# Verification — Home

**Last verified:** 2026-04-19 against `7a291db`
**Source:** `Sources/PairwiseReminders/Views/HomeView.swift`
**Related issues:** #101, #106, #114

## Scope
The main landing screen: segmented mode picker (Lists / All Reminders / Due Date), selection mode, prioritise entry, Elo sparklines on list headers, and row interactions (tap = edit, long-press = toggle select, or the reverse depending on `home_tap_default`).

## Golden path
- [ ] Toggle between Lists / All Reminders / Due Date — content updates, no flicker.
- [ ] Lists mode: each list header shows a sparkline for items with `comparisonCount > 0`; bars grow left-to-right (lowest-Elo left, highest right).
- [ ] Sparkline bar heights are scaled against the *global* min/max across all lists, so different lists are visually comparable.
- [ ] Expand a list — reminder rows appear; tap a row with tap-default `.edit` opens `ReminderEditSheet`.
- [ ] Long-press a row (tap-default `.edit`) — toggles selection on that row.
- [ ] Tap the Prioritise pill at the bottom with a selection — Prioritise flow opens prefilled.
- [ ] Tap the Prioritise pill with nothing selected — silently enters Select mode (no alert).
- [ ] In Select mode, tap a list header row — all items in that list become selected (cascade).
- [ ] Deselect a list header — every item under it is deselected.
- [ ] Cancel button appears whenever the selection is non-empty; tapping it clears the selection without leaving Select mode incorrectly.
- [ ] Gear icon opens `SettingsView` as a sheet.
- [ ] Bottom Prioritise pill is a floating glass capsule that stays above content on scroll.
- [ ] Top navigation bar uses `ultraThinMaterial` (frosted) and the title ("Retinder") transitions correctly on scroll.

## Edge cases
- [ ] Set `home_tap_default = .select` in Settings — tap now toggles selection, long-press opens edit sheet. Verify the swap is immediate (no relaunch needed).
- [ ] No lists at all (fresh install, no permission) — empty state renders; Prioritise pill is disabled/hidden.
- [ ] A list with zero ranked items — sparkline is absent (not a flat bar).
- [ ] All Reminders mode with 100+ items — scroll is smooth.
- [ ] Due Date mode — items group correctly under Overdue / Today / Tomorrow / This Week / Later / No date.
- [ ] Long reminder title (multiline) — row height grows; layout doesn't clip.
- [ ] Section gap between list groups is tight (`.listSectionSpacing(.compact)`), not the default chunky iOS grouped inset.

## Known gaps
- Widget surface not yet built (tracked separately).
- No pull-to-refresh on the Home list — EventKit sync only runs at bootstrap.
