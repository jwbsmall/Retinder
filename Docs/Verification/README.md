# Verification docs

Per-surface manual checklists. One `.md` per user-facing screen. We run these by hand on a simulator (and occasionally a device) before merging anything that touches that surface.

## Why these exist

The app is SwiftUI + EventKit + SwiftData + Anthropic API — hard to cover with unit tests past the `EloEngine` / `AnthropicService` seams. The gap is filled by running the app and eyeballing the interaction. These docs make that process repeatable instead of ad-hoc.

## Structure of a doc

Every doc uses the same shape. Keep each list focused on **things a regression would break** — not every possible interaction.

```markdown
# Verification — <Surface>

**Last verified:** YYYY-MM-DD against `<short-sha>`
**Source:** `Sources/PairwiseReminders/Views/<File>.swift`
**Related issues:** #nnn

## Scope
One paragraph: what this doc covers, where the feature lives.

## Golden path
- [ ] Step — expected outcome

## Edge cases
- [ ] Condition — expected outcome

## Known gaps
- Deferred behaviour, link to issue.
```

## When you must update a doc

**Any PR that changes a file under `Sources/PairwiseReminders/Views/` must update the matching verification doc** — even if the update is just bumping `Last verified` because you re-ran the checklist. The mapping is maintained in [`.github/scripts/check-verification.sh`](../../.github/scripts/check-verification.sh) and enforced by the `Verification sync` GitHub Action.

If a PR is genuinely out of scope (pure refactor, no user-visible change), add the line

```
[verification: n/a — <reason>]
```

to the PR body. The workflow will skip the check.

## Adding a new surface

1. Create `Docs/Verification/<Surface>.md` from the template above.
2. Add a line to [`pull_request_template.md`](../../.github/pull_request_template.md) under **Surfaces touched**.
3. Map the source file(s) to the new doc in [`.github/scripts/check-verification.sh`](../../.github/scripts/check-verification.sh).

## Index

| Surface | Doc | Primary source |
|---|---|---|
| Bootstrap / splash | [Bootstrap.md](Bootstrap.md) | `ContentView.swift` |
| Home | [Home.md](Home.md) | `HomeView.swift` |
| Prioritise start | [PrioritiseStart.md](PrioritiseStart.md) | `ListPickerView.swift`, `FilteringView.swift` |
| Pairwise comparison | [Pairwise.md](Pairwise.md) | `PairwiseView.swift` |
| Results | [Results.md](Results.md) | `ResultsView.swift` |
| List detail | [ListDetail.md](ListDetail.md) | `ListDetailView.swift` |
| Settings | [Settings.md](Settings.md) | `SettingsView.swift` |
| History | [History.md](History.md) | `HistoryView.swift` |
