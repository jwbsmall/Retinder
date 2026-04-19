# Verification — History

**Last verified:** 2026-04-19 against `206c92e`
**Source:** `Sources/PairwiseReminders/Views/HistoryView.swift`
**Related issues:** —

## Scope
Compact log of every pairwise comparison decision, grouped by session and ordered by `sessionDate` descending. Backed by SwiftData's `ComparisonRecord`.

## Scope caveat
`HistoryView` is not currently wired into the main navigation — verify whether the entry point has been restored before exercising this checklist.

## Golden path
- [ ] Open History — sessions list renders in reverse chronological order.
- [ ] Each session header shows the session date + total comparison count.
- [ ] Each row under a session shows the winner + loser titles and the decision (preferred / equal).
- [ ] Empty state renders cleanly when no `ComparisonRecord` rows exist.

## Edge cases
- [ ] 100+ sessions — scroll is smooth; no excessive SwiftData fetch cost on open.
- [ ] A reminder that has since been deleted — its history row still renders (stored title, not a live EventKit lookup).
- [ ] Session with a single "equal" decision — decision label reads "Equal", not blank.
- [ ] Empty-state clock icon scales with Dynamic Type up to Accessibility 2.

## Known gaps
- No entry point from Home yet — navigation wiring TBD.
- No filter by list or date range.
