import SwiftUI
import SwiftData

/// Compact log of every pairwise comparison decision, grouped by session.
struct HistoryView: View {

    @Query(sort: \ComparisonRecord.sessionDate, order: .reverse) private var records: [ComparisonRecord]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Comparison History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        // Group records by sessionID, preserving descending session date order.
        let grouped = groupedSessions()
        return List {
            ForEach(grouped, id: \.id) { session in
                Section {
                    ForEach(Array(session.decisions.enumerated()), id: \.offset) { _, decision in
                        DecisionRow(winner: decision.winnerTitle, loser: decision.loserTitle)
                    }
                } header: {
                    SessionHeader(date: session.date, count: session.decisions.count)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No history yet")
                .font(.title3.bold())
            Text("Comparison decisions are saved here after each Prioritise session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Grouping

    private struct SessionGroup: Identifiable {
        let id: String          // sessionID
        let date: Date
        let decisions: [ComparisonRecord]
    }

    private func groupedSessions() -> [SessionGroup] {
        var seen: [String: SessionGroup] = [:]
        var order: [String] = []

        for record in records {
            if seen[record.sessionID] == nil {
                seen[record.sessionID] = SessionGroup(id: record.sessionID,
                                                      date: record.sessionDate,
                                                      decisions: [])
                order.append(record.sessionID)
            }
        }

        // Collect decisions per session in ascending order (the stored `order` field).
        var buckets: [String: [ComparisonRecord]] = [:]
        for record in records {
            buckets[record.sessionID, default: []].append(record)
        }
        for key in buckets.keys {
            buckets[key]?.sort { $0.order < $1.order }
        }

        return order.compactMap { id in
            guard let group = seen[id], let decisions = buckets[id] else { return nil }
            return SessionGroup(id: id, date: group.date, decisions: decisions)
        }
    }
}

// MARK: - Sub-views

private struct SessionHeader: View {
    let date: Date
    let count: Int

    var body: some View {
        HStack {
            Text(date, style: .date)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(date, style: .time)
            Spacer()
            Text("\(count) comparison\(count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct DecisionRow: View {
    let winner: String
    let loser: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(winner)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(loser)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
