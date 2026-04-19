# Verification — Bootstrap

**Last verified:** 2026-04-19 against `7a291db`
**Source:** `Sources/PairwiseReminders/Views/ContentView.swift`
**Related issues:** #105

## Scope
App launch path: splash screen, EventKit permission request, initial SwiftData sync, fade into HomeView.

## Golden path
- [ ] Cold launch (app quit, then reopen) — splash appears with the pulsing icon and "Syncing your reminders…" label.
- [ ] Splash fades out smoothly once `syncWithEventKit` completes.
- [ ] HomeView is already populated when splash disappears (no blank state flash).
- [ ] On first-ever launch, the iOS Reminders permission prompt appears before sync.

## Edge cases
- [ ] Permission denied — HomeView still renders; empty-state messaging is sensible.
- [ ] Permission revoked in Settings, then app relaunched — fresh prompt appears.
- [ ] Large number of reminders (100+) — splash stays visible until sync actually completes; no flicker.
- [ ] Network offline on launch — bootstrap completes normally (AI seeding is only triggered during Prioritise flow, not here).

## Known gaps
- No retry UX if EventKit sync fails mid-flight — silently proceeds.
