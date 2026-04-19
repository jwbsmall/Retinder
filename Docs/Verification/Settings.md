# Verification — Settings

**Last verified:** 2026-04-19 against `206c92e`
**Source:** `Sources/PairwiseReminders/Views/SettingsView.swift`
**Related issues:** #114

## Scope
Sheet launched from the Home gear icon (and the Pairwise gear icon): Anthropic API key entry + masking + connection test, and due-date defaults per priority tier. Interaction tap-default settings have been removed — tapping always edits out of select mode, long-press always selects.

## Golden path
- [ ] Enter an API key — Save is disabled until the field is non-empty; tapping Save persists to Keychain; "Saved" green label appears briefly.
- [ ] Toggle the eye icon — masks/unmasks the stored value.
- [ ] Tap Test connection — spinner appears, then either green "Connected" or red error with code/message.
- [ ] Due-date defaults (High / Medium / Low) — each picker persists via UserDefaults and propagates to the Apply sheet in Results.
- [ ] Closing the sheet returns without mutating session state.

## Edge cases
- [ ] Empty API key + Test connection — button is disabled (no hit to the API).
- [ ] Bad API key (`sk-ant-invalid`) — Test connection surfaces an "Error 401" or similar with a readable message.
- [ ] Offline — Test connection surfaces a network error message, not a spinner that hangs.
- [ ] "Custom" due-date target is not offered in the pickers (filtered out) — only absolute buckets (today, tomorrow, next week, etc.).
- [ ] VoiceOver announces the eye toggle as "Show API key" / "Hide API key" based on mask state.

## Known gaps
- No "delete API key" button — user must clear the field; Save is disabled on empty so clearing requires entering a blank then the Save button remains disabled.
