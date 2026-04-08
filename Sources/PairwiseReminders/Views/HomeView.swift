import SwiftUI
import SwiftData
import EventKit

/// Home tab: shows all imported Reminders lists with ranking progress and staleness.
struct HomeView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ListConfig.calendarIdentifier)
    private var allConfigs: [ListConfig]
    private var importedConfigs: [ListConfig] { allConfigs.filter(\.isImported) }

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
                        records: records(for: calendar),
                        config: config(for: calendar)
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

    private func config(for calendar: EKCalendar) -> ListConfig? {
        allConfigs.first { $0.calendarIdentifier == calendar.calendarIdentifier }
    }
}

// MARK: - List Row

private struct ListRowView: View {
    let calendar: EKCalendar
    let records: [RankedItemRecord]
    let config: ListConfig?

    private var rankedCount: Int { records.filter { $0.comparisonCount > 0 }.count }
    private var totalCount: Int { records.count }

    private var stalenessDate: Date? {
        records.compactMap(\.lastComparedAt).max()
    }

    private var isStale: Bool {
        guard let config, let last = stalenessDate else { return false }
        let threshold = TimeInterval(config.stalenessThresholdDays * 86400)
        return Date().timeIntervalSince(last) > threshold
    }

    private var stalenessText: String? {
        guard let last = stalenessDate else { return nil }
        let days = Int(Date().timeIntervalSince(last) / 86400)
        return days == 0 ? "Ranked today" : "Ranked \(days)d ago"
    }

    var body: some View {
        HStack(spacing: 12) {
            // List colour dot
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(calendar.title)
                    .font(.body.bold())

                HStack(spacing: 8) {
                    if totalCount > 0 {
                        Text("\(rankedCount)/\(totalCount) ranked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let text = stalenessText {
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(isStale ? .orange : .secondary)
                    }
                }

                if totalCount > 0 {
                    ProgressView(value: Double(rankedCount), total: Double(max(totalCount, 1)))
                        .tint(isStale ? .orange : Color(cgColor: calendar.cgColor))
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

// MARK: - List Import View

/// Lets the user toggle which Reminders lists to import for ranking.
struct ListImportView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @Environment(\.modelContext) private var modelContext

    @Query private var allConfigs: [ListConfig]

    var body: some View {
        List(remindersManager.lists, id: \.calendarIdentifier) { calendar in
            let config = allConfigs.first { $0.calendarIdentifier == calendar.calendarIdentifier }
            let isImported = config?.isImported ?? false
            HStack {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
                Spacer()
                if isImported {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(calendar: calendar, currentConfig: config) }
        }
        .navigationTitle("Import Lists")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(calendar: EKCalendar, currentConfig: ListConfig?) {
        if let config = currentConfig {
            config.isImported.toggle()
        } else {
            let config = ListConfig(calendarIdentifier: calendar.calendarIdentifier, isImported: true)
            modelContext.insert(config)
        }
        try? modelContext.save()
    }
}
