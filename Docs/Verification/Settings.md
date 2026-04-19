# Verification — Settings

**Last verified:** 2026-04-19 against `7a291db`
**Source:** `Sources/PairwiseReminders/Views/SettingsView.swift`
**Related issues:** #114

## Scope
Sheet launched from the Home gear icon: Anthropic API key entry + masking + connection test, interaction defaults (Home tap-default, Pairwise tap-default), and due-date defaults per priority tier.

## Golden path
- [ ] Enter an API key — Save is disabled until the field is non-empty; tapping Save persists to Keychain; "Saved" green label appears briefly.
- [ ] Toggle the eye icon — masks/unmasks the stored value.
- [ ] Tap Test connection — spinner appears, then either green "Connected" or red error with code/message.
- [ ] Home tap default picker — switching between `.edit` / `.select` immediately changes Home row tap behaviour without restart.
- [ ] Pairwise tap default picker — switching between `.choose` / `.edit` immediately changes Pairwise card tap behaviour.
- [ ] Due-date defaults (High / Medium / Low) — each picker persists via UserDefaults and propagates to the Apply sheet in Results.
- [ ] Closing the sheet returns to Home without mutating session state.

## Edge cases
- [ ] Empty API key + Test connection — button is disabled (no hit to the API).
- [ ] Bad API key (`sk-ant-invalid`) — Test connection surfaces an "Error 401" or similar with a readable message.
- [ ] Offline — Test connection surfaces a network error message, not a spinner that hangs.
- [ ] "Custom" due-date target is not offered in the pickers (filtered out) — only absolute buckets (today, tomorrow, next week, etc.).
- [ ] Footer hints are visible under both sections (Keychain storage note; long-press note for tap defaults).

## Known gaps
- No "delete API key" button — user must clear the field and Save an empty string (not currently possible — Save is disabled on empty).
- No per-tier "do not set due date" option.
