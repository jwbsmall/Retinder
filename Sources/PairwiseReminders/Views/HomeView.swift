import SwiftUI
import SwiftData
import EventKit

/// Home tab: shows all imported Reminders lists with ranking progress and staleness.
struct HomeView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @Query private var allRecords: [RankedItemRecord]

    @State private var selectedList: EKCalendar?

    var body: some View {
        NavigationStack {
            Group {
                if remindersManager.lists.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Retinder")
            .navigationDestination(item: $selectedList) { calendar in
                ListDetailView(calendar: calendar)
            }
            .task { await remindersManager.syncWithEventKit(context: modelContext) }
        }
    }

    // MARK: - Content

    private var listContent: some View {
        List {
            Section("Your Lists") {
                ForEach(remindersManager.lists, id: \.calendarIdentifier) { calendar in
                    ListRowView(
                        calendar: calendar,
                        records: records(for: calendar)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedList = calendar }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await remindersManager.syncWithEventKit(context: modelContext)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Reminders Lists")
                .font(.title2.bold())
            Text("Your Reminders lists will appear here once access is granted.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func records(for calendar: EKCalendar) -> [RankedItemRecord] {
        allRecords.filter { $0.listCalendarIdentifier == calendar.calendarIdentifier }
    }
}

// MARK: - List Row

private struct ListRowView: View {
    let calendar: EKCalendar
    let records: [RankedItemRecord]

    private var rankedCount: Int { records.filter { $0.comparisonCount > 0 }.count }
    private var totalCount: Int { records.count }

    var body: some View {
        HStack(spacing: 12) {
            // List colour dot
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(calendar.title)
                    .font(.body.bold())

                if totalCount > 0 {
                    Text("\(rankedCount)/\(totalCount) ranked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(rankedCount), total: Double(max(totalCount, 1)))
                        .tint(Color(cgColor: calendar.cgColor))
                } else {
                    Text("No items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

