import SwiftUI

/// Shows an animated loading state while the Anthropic API filters reminders.
/// Transitions to `.comparing` on success.
struct FilteringView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var engine: PairwiseEngine

    @State private var statusLine = "Sending your reminders to Claude…"

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "sparkles")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative)
            }

            // Status text
            VStack(spacing: 8) {
                Text("Analysing Your Reminders")
                    .font(.title2.bold())

                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: statusLine)
            }

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)


            Spacer()
        }
        .padding()
        .task { await runFiltering() }
    }

    // MARK: - Filtering Logic

    private func runFiltering() async {
        let items = session.allItems
        statusLine = "Found \(items.count) reminder\(items.count == 1 ? "" : "s"). Asking Claude to identify the most important…"

        // Attempt AI filtering. Any failure (no key, network error, rate limit, etc.)
        // falls through to the fallback — the pairwise comparison always proceeds.
        let aiResult: [ReminderItem]?
        if let apiKey = KeychainService.load() {
            let service = AnthropicService(apiKey: apiKey)
            aiResult = try? await service.filterReminders(items)
        } else {
            aiResult = nil
        }

        if let filtered = aiResult, !filtered.isEmpty {
            session.filteredItems = filtered
            let count = filtered.count
            statusLine = "Claude identified \(count) key item\(count == 1 ? "" : "s"). Ready to compare!"
            try? await Task.sleep(for: .milliseconds(900))
        } else {
            // Fallback: cap at 20 items (random sample when there are more).
            session.aiFilteringFailed = true
            let fallback = items.count <= 20 ? items : Array(items.shuffled().prefix(20))
            session.filteredItems = fallback
            let count = fallback.count
            statusLine = "AI filtering unavailable — using \(count) item\(count == 1 ? "" : "s")."
            try? await Task.sleep(for: .milliseconds(600))
        }

        engine.reset()
        session.phase = .comparing
    }
}
