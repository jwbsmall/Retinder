#!/usr/bin/env bash
# Enforces that PRs touching user-facing view files also update the matching
# Docs/Verification/*.md. Opt-out by adding `[verification: n/a ...]` to the PR body.
#
# Inputs (from the GitHub Action):
#   BASE_SHA   — base ref the PR targets
#   HEAD_SHA   — tip of the PR branch
#   PR_BODY    — raw PR body text
#
# Portable across bash 3 (macOS default) and bash 5 (Ubuntu CI) — no associative arrays.

set -euo pipefail

BASE_SHA="${BASE_SHA:?BASE_SHA required}"
HEAD_SHA="${HEAD_SHA:?HEAD_SHA required}"
PR_BODY="${PR_BODY:-}"

# Escape hatch: [verification: n/a ...] anywhere in the body skips the check.
if printf '%s' "$PR_BODY" | grep -qiE '\[verification:[[:space:]]*n/?a'; then
    echo "Opt-out marker found in PR body — skipping verification-doc check."
    exit 0
fi

# View -> doc mapping. One pair per line, separated by a tab. Extend when a new surface is added.
VIEW_TO_DOC=$(cat <<'EOF'
Sources/PairwiseReminders/Views/ContentView.swift	Docs/Verification/Bootstrap.md
Sources/PairwiseReminders/Views/HomeView.swift	Docs/Verification/Home.md
Sources/PairwiseReminders/Views/ListPickerView.swift	Docs/Verification/PrioritiseStart.md
Sources/PairwiseReminders/Views/FilteringView.swift	Docs/Verification/PrioritiseStart.md
Sources/PairwiseReminders/Views/PairwiseView.swift	Docs/Verification/Pairwise.md
Sources/PairwiseReminders/Views/ResultsView.swift	Docs/Verification/Results.md
Sources/PairwiseReminders/Views/ListDetailView.swift	Docs/Verification/ListDetail.md
Sources/PairwiseReminders/Views/SettingsView.swift	Docs/Verification/Settings.md
Sources/PairwiseReminders/Views/HistoryView.swift	Docs/Verification/History.md
EOF
)

changed=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA" || true)

# Collect known view paths from the map so we can flag unmapped Views/*.swift files.
known_views=$(printf '%s\n' "$VIEW_TO_DOC" | awk -F'\t' '{ print $1 }')

missing=""

# 1. For each (view, doc) pair: if the view changed, the doc must also change.
while IFS=$'\t' read -r view doc; do
    [ -z "$view" ] && continue
    if printf '%s\n' "$changed" | grep -qxF "$view"; then
        if ! printf '%s\n' "$changed" | grep -qxF "$doc"; then
            missing="${missing}${view} → expected matching update to ${doc}\n"
        fi
    fi
done <<EOF
$VIEW_TO_DOC
EOF

# 2. Catch any changed Views/*.swift not in the map — forces the map to stay current.
while IFS= read -r path; do
    [ -z "$path" ] && continue
    case "$path" in
        Sources/PairwiseReminders/Views/*.swift)
            if ! printf '%s\n' "$known_views" | grep -qxF "$path"; then
                missing="${missing}${path} → no verification doc mapped; add it to .github/scripts/check-verification.sh and Docs/Verification/\n"
            fi
            ;;
    esac
done <<EOF
$changed
EOF

if [ -n "$missing" ]; then
    {
        echo "❌ Verification sync check failed."
        echo ""
        echo "The following view files changed but their verification doc(s) did not:"
        echo ""
        printf '%b' "$missing" | sed 's/^/  • /'
        echo ""
        echo "Fix: update the matching doc under Docs/Verification/ (at minimum, bump 'Last verified'),"
        echo "or add '[verification: n/a — <reason>]' to the PR body if this PR is genuinely out of scope."
    } >&2
    exit 1
fi

echo "✅ Verification-doc sync OK."
