import SwiftUI
import SwiftData
import EventKit

/// Shows a single imported list's ranked and unranked items.
/// Ranked items are sorted by Elo rating descending; unranked items appear in a
/// separate section at the bottom.
struct ListDetailView: View {

    let calendar: EKCalendar

    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @State private var items: [ReminderItem] = []
    @State private var isLoading = true
    @State private var editingItem: ReminderItem?
    @State private var showApplySheet = false
    @State private var applyError: String?

    private var rankedItems: [ReminderItem] {
        items.filter { $0.eloRating != 1000.0 || hasRecord($0) }
             .sorted { $0.eloRating > $1.eloRating }
    }

    private var unrankedItems: [ReminderItem] {
        items.filter { !rankedItems.contains($0) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .navigationTitle(calendar.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .task { await loadItems() }
        .sheet(item: $editingItem) { item in
            ReminderEditSheet(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onDisappear { Task { await loadItems() } }
        }
        .sheet(isPresented: $showApplySheet) {
            ApplySheet(items: rankedItems) { options in
                applyWriteBack(options)
            }
        }
        .alert("Write-back failed", isPresented: .constant(applyError != nil), actions: {
            Button("OK") { applyError = nil }
        }, message: {
            Text(applyError ?? "")
        })
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            if !rankedItems.isEmpty {
                Section("Ranked — \(rankedItems.count)") {
                    ForEach(Array(rankedItems.enumerated()), id: \.element.id) { index, item in
                        RankedRowView(item: item, rank: index + 1, total: rankedItems.count)
                            .swipeActions(edge: .leading) {
                                Button {
                                    complete(item)
                                } label: {
                                    Label("Done", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                            .onTapGesture { editingItem = item }
                    }
                    .onMove { from, to in
                        reorder(items: &items, rankedItems: rankedItems, from: from, to: to)
                    }
                }
            }

            if !unrankedItems.isEmpty {
                Section("Unranked — \(unrankedItems.count)") {
                    ForEach(unrankedItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.body)
                                if let due = item.dueDate {
                                    Text(due.formatted(.dateTime.day().month()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                complete(item)
                            } label: {
                                Label("Done", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                        .onTapGesture { editingItem = item }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .refreshable { await loadItems() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("All done!")
                .font(.title2.bold())
            Text("No incomplete reminders in this list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    startSession()
                } label: {
                    Label("Prioritise", systemImage: "arrow.up.arrow.down")
                }
                if !rankedItems.isEmpty {
                    Button {
                        showApplySheet = true
                    } label: {
                        Label("Write Back…", systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func loadItems() async {
        isLoading = true
        let listID = calendar.calendarIdentifier
        items = (try? await remindersManager.fetchIncompleteReminders(
            from: [listID], context: modelContext
        )) ?? []
        isLoading = false
    }

    private func complete(_ item: ReminderItem) {
        try? remindersManager.complete(item)
        items.removeAll { $0.id == item.id }
    }

    private func startSession() {
        Task {
            await session.start(
                listIDs: [calendar.calendarIdentifier],
                remindersManager: remindersManager,
                eloEngine: eloEngine,
                context: modelContext
            )
        }
    }

    private func applyWriteBack(_ options: ApplyOptions) {
        do {
            if options.applyPriorities {
                switch options.priorityMode {
                case .tiered: try remindersManager.applyPriorities(rankedItems)
                case .topN:   try remindersManager.applyTopNUrgent(rankedItems, count: options.urgentCount)
                }
            }
            if options.applyDueDates {
                let date = options.resolvedDueDate
                try remindersManager.applyDueDates(rankedItems, count: options.dueDateCount, dueDate: date)
            }
        } catch {
            applyError = error.localizedDescription
        }
    }

    // MARK: - Reorder

    /// When the user drags to reorder ranked items, nudge Elo ratings to match the new order.
    private func reorder(
        items: inout [ReminderItem],
        rankedItems: [ReminderItem],
        from source: IndexSet,
        to destination: Int
    ) {
        var mutable = rankedItems
        mutable.move(fromOffsets: source, toOffset: destination)

        // Distribute ratings evenly across the new order so the ranking is preserved on next load.
        let spread = 20.0
        let top = (mutable.first?.eloRating ?? 1000.0) + spread * Double(mutable.count)
        for (i, item) in mutable.enumerated() {
            guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { continue }
            let newRating = top - spread * Double(i)
            self.items[idx].eloRating = newRating

            // Persist
            let id = item.id
            let record = ((try? modelContext.fetch(FetchDescriptor<RankedItemRecord>())) ?? [])
                .first { $0.calendarItemIdentifier == id }
            if let record {
                record.eloRating = newRating
                try? modelContext.save()
            }
        }
    }

    private func hasRecord(_ item: ReminderItem) -> Bool {
        let id = item.id
        return ((try? modelContext.fetch(FetchDescriptor<RankedItemRecord>())) ?? [])
            .contains { $0.calendarItemIdentifier == id }
    }
}

// MARK: - Ranked Row

private struct RankedRowView: View {
    let item: ReminderItem
    let rank: Int
    let total: Int

    private var priorityLabel: String { item.priorityLabel(totalCount: total) }
    private var priorityColor: Color  { mapColor(item.priorityColor(totalCount: total)) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 34, height: 34)
                Text("\(rank)")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let due = item.dueDate {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(due.formatted(.dateTime.day().month()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(priorityLabel)
                .font(.caption.bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(priorityColor.opacity(0.15))
                .foregroundStyle(priorityColor)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.vertical, 3)
    }

    private var badgeColor: Color {
        switch rank {
        case 1: return .blue
        case 2: return .indigo
        case 3: return .purple
        default: return Color(.systemGray3)
        }
    }

    private func mapColor(_ c: ReminderItem.PriorityColor) -> Color {
        switch c {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return Color(.secondaryLabel)
        }
    }
}
