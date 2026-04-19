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
        items.filter { $0.comparisonCount > 0 }
             .sorted { $0.eloRating > $1.eloRating }
    }

    private var unrankedItems: [ReminderItem] {
        items.filter { $0.comparisonCount == 0 }
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
                let eloMin = rankedItems.last?.eloRating ?? 1000
                let eloMax = rankedItems.first?.eloRating ?? 1000
                Section("Ranked — \(rankedItems.count)") {
                    ForEach(Array(rankedItems.enumerated()), id: \.element.id) { index, item in
                        RankedRowView(item: item, rank: index + 1, eloMin: eloMin, eloMax: eloMax)
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
                .font(.largeTitle)
                .imageScale(.large)
                .dynamicTypeSize(.small ... .accessibility2)
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
                    addToPrioritise()
                } label: {
                    Label("Add to Prioritise", systemImage: "arrow.up.arrow.down")
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
            .accessibilityLabel("More options")
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

    /// Pre-selects this list in the Prioritise tab and switches to it.
    /// The user can add more lists before starting the session.
    private func addToPrioritise() {
        session.pendingListIDs.insert(calendar.calendarIdentifier)
    }

    private func applyWriteBack(_ options: ApplyOptions) {
        let items = rankedItems.filter {
            !options.excludedListIDs.contains($0.ekReminder.calendar?.calendarIdentifier ?? "")
        }
        do {
            if options.applyPriorities {
                switch options.priorityMode {
                case .tiered:
                    try remindersManager.applyPrioritiesCustom(
                        items,
                        highCount: options.highCount,
                        mediumCount: options.mediumCount,
                        lowCount: options.lowCount
                    )
                case .topN:
                    try remindersManager.applyTopNUrgent(items, count: options.urgentCount)
                }
            }
            if options.applyDueDates {
                if options.applyPriorities && options.priorityMode == .tiered {
                    let high   = min(options.highCount,   items.count)
                    let medium = min(options.mediumCount, items.count - high)
                    let low    = min(options.lowCount,    items.count - high - medium)
                    var assignments: [(ReminderItem, Date)] = []
                    for i in 0..<high {
                        if let d = options.resolvedDate(for: options.highDueTarget, custom: options.highCustomDate) {
                            assignments.append((items[i], d))
                        }
                    }
                    for i in high..<(high + medium) {
                        if let d = options.resolvedDate(for: options.mediumDueTarget, custom: options.mediumCustomDate) {
                            assignments.append((items[i], d))
                        }
                    }
                    for i in (high + medium)..<(high + medium + low) {
                        if let d = options.resolvedDate(for: options.lowDueTarget, custom: options.lowCustomDate) {
                            assignments.append((items[i], d))
                        }
                    }
                    if !assignments.isEmpty {
                        try remindersManager.applyTieredDueDates(
                            assignments,
                            includeTime: options.includeTime,
                            addAlarms: options.addAlarms
                        )
                    }
                } else if let dueDate = options.resolvedDueDate {
                    try remindersManager.applyDueDates(
                        items,
                        count: options.dueDateCount,
                        dueDate: dueDate,
                        includeTime: options.includeTime,
                        addAlarms: options.addAlarms
                    )
                }
            }
            if options.applyFlags {
                try remindersManager.applyFlags(items, count: options.flagCount)
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

        // Load all records once — avoids N separate SwiftData fetches inside the loop.
        let allRecords = (try? modelContext.fetch(FetchDescriptor<RankedItemRecord>())) ?? []
        let recordsByID = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.calendarItemIdentifier, $0) })

        let spread = 20.0
        let top = (mutable.first?.eloRating ?? 1000.0) + spread * Double(mutable.count)
        for (i, item) in mutable.enumerated() {
            guard let idx = self.items.firstIndex(where: { $0.id == item.id }) else { continue }
            let newRating = top - spread * Double(i)
            self.items[idx].eloRating = newRating
            recordsByID[item.id]?.eloRating = newRating
        }
        try? modelContext.save()
    }
}

// MARK: - Ranked Row

private struct RankedRowView: View {
    let item: ReminderItem
    let rank: Int
    let eloMin: Double
    let eloMax: Double

    private var eloStrength: Double {
        guard eloMax > eloMin else { return 0 }
        return max(0, min(1, (item.eloRating - eloMin) / (eloMax - eloMin)))
    }

    private var barTint: Color {
        if eloStrength > 0.66 { return .blue }
        if eloStrength > 0.33 { return .indigo }
        return Color(.systemGray3)
    }

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

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let due = item.dueDate {
                        Label(due.formatted(.dateTime.day().month()), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                    }
                    Text(item.listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: eloStrength)
                    .tint(barTint)
                    .frame(height: 3)
            }
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
}
