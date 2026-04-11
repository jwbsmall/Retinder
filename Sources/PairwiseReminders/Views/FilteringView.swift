import SwiftUI

/// Shows an animated loading state while the AI seeds initial Elo rankings.
/// This view is active while `PairwiseSession.phase == .seeding`.
/// The session itself handles all seeding logic — this view is purely presentational.
struct FilteringView: View {

    @EnvironmentObject private var session: PairwiseSession

    @State private var statusLine = "Fetching reminders…"

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "sparkles")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative)
            }

            VStack(spacing: 8) {
                Text("Ranking Your Reminders")
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
        .onAppear { updateStatus(count: session.sessionItems.count) }
        .onChange(of: session.sessionItems.count) { _, count in
            updateStatus(count: count)
        }
    }

    private func updateStatus(count: Int) {
        if count == 0 {
            statusLine = "Fetching reminders…"
        } else if session.aiPreference == .none {
            statusLine = "Preparing \(count) item\(count == 1 ? "" : "s")…"
        } else {
            statusLine = "AI is ranking \(count) item\(count == 1 ? "" : "s")…"
        }
    }
}
