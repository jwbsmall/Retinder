import SwiftUI
import SwiftData
import EventKit

/// Root view. Shows all imported Reminders lists (or all items flattened) with ranking progress.
/// Houses the Settings sheet (gear icon) and Prioritise flow (fullScreenCover).
struct HomeView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @Query private var allRecords: [RankedItemRecord]

    @State private var selectedList: EKCalendar?
    @State private var showPrioritise = false
    @State private var showSettings = false
    @State private var viewMode: ViewMode = .lists

    private enum ViewMode { case lists, all }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter controls — switch between the two home views.
                Picker("View", selection: $viewMode) {
                    Text("Lists").tag(ViewMode.lists)
                    Text("All Reminders").tag(ViewMode.all)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                if remindersManager.lists.isEmpty {
                    emptyState
                } else if viewMode == .lists {
                    listsContent
                } else {
                    AllRemindersView(onPrioritise: openPrioritise)
                }
            }
            .navigationTitle("Retinder")
            .navigationDestination(item: $selectedList) { calendar in
                ListDetailView(calendar: calendar)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            showPrioritise = true
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.title3)
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.title3)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showPrioritise) {
                PrioritiseFlow()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            // Pre-select lists forwarded from ListDetailView / AllRemindersView.
            .onChange(of: session.pendingListIDs) { _, ids in
                if !ids.isEmpty, !showPrioritise {
                    showPrioritise = true
                }
            }
            // Dismiss the Prioritise flow when the session resets to idle.
            .onChange(of: session.phase) { _, phase in
                if phase == .idle { showPrioritise = false }
            }
        }
    }

    // MARK: - Lists Content

    private var listsContent: some View {
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

    /// Called by AllRemindersView when the user taps "Prioritise N items".
    /// Sets pendingListIDs to the distinct lists of the selected items so the
    /// Prioritise flow opens pre-populated. Note: this brings ALL items from
    /// those lists into the session, not just the selected subset (v1 limitation).
    private func openPrioritise(listIDs: Set<String>) {
        session.pendingListIDs = listIDs
    }
}

// MARK: - Prioritise Flow

/// Full-screen session flow: list selection → AI seeding → pairwise comparison → results.
/// Presented as a fullScreenCover from HomeView to avoid gesture conflicts with PairwiseView.
private struct PrioritiseFlow: View {

    @EnvironmentObject private var session: PairwiseSession

    var body: some View {
        NavigationStack {
            switch session.phase {
            case .idle:      ListPickerView()
            case .seeding:   FilteringView()
            case .comparing: PairwiseView()
            case .done:      ResultsView()
            }
        }
    }
}

// MARK: - All Reminders View

/// Flattened cross-list view of all reminders, sorted by Elo rating.
/// Ranked items (comparisonCount > 0) are shown first; unranked items below.
/// Multi-select → "Prioritise N items" collects the distinct list IDs and
/// opens the Prioritise flow pre-populated with those lists.
private struct AllRemindersView: View {

    var onPrioritise: (Set<String>) -> Void

    @EnvironmentObject private var remindersManager: RemindersManager
    @Environment(\.modelContext) private var modelContext

    @State private var items: [ReminderItem] = []
    @State private var isLoading = true
    @State private var selectedIDs = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var editingItem: ReminderItem?

    private var rankedItems: [ReminderItem] {
        items.filter { $0.comparisonCount > 0 }.sorted { $0.eloRating > $1.eloRating }
    }

    private var unrankedItems: [ReminderItem] {
        items.filter { $0.comparisonCount == 0 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    allEmptyState
                } else {
                    itemList
                }
            }

            // Bottom bar: appears when items are selected in edit mode.
            if editMode == .active && !selectedIDs.isEmpty {
                prioritiseBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .environment(\.editMode, $editMode)
        .onChange(of: editMode) { _, mode in
            if mode == .inactive { selectedIDs = [] }
        }
        .task { await load() }
        .sheet(item: $editingItem) { item in
            ReminderEditSheet(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .onDisappear { Task { await load() } }
        }
    }

    // MARK: - Item List

    private var itemList: some View {
        List(selection: $selectedIDs) {
            if !rankedItems.isEmpty {
                Section("Ranked — \(rankedItems.count)") {
                    ForEach(rankedItems) { item in
                        AllRemindersRow(item: item, rank: rankIndex(item))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if editMode == .inactive { editingItem = item }
                            }
                    }
                }
            }
            if !unrankedItems.isEmpty {
                Section("Unranked — \(unrankedItems.count)") {
                    ForEach(unrankedItems) { item in
                        AllRemindersRow(item: item, rank: nil)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if editMode == .inactive { editingItem = item }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private var allEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No reminders")
                .font(.title2.bold())
            Text("Incomplete reminders from all your lists will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var prioritiseBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                let listIDs = Set(
                    items
                        .filter { selectedIDs.contains($0.id) }
                        .compactMap { $0.ekReminder.calendar?.calendarIdentifier }
                )
                editMode = .inactive
                selectedIDs = []
                onPrioritise(listIDs)
            } label: {
                Text("Prioritise \(selectedIDs.count) item\(selectedIDs.count == 1 ? "" : "s")…")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .background(.regularMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: selectedIDs.isEmpty)
    }

    // MARK: - Helpers

    private func rankIndex(_ item: ReminderItem) -> Int? {
        rankedItems.firstIndex(where: { $0.id == item.id }).map { $0 + 1 }
    }

    private func load() async {
        isLoading = true
        let allListIDs = Set(remindersManager.lists.map(\.calendarIdentifier))
        items = (try? await remindersManager.fetchIncompleteReminders(
            from: allListIDs, context: modelContext
        )) ?? []
        isLoading = false
    }
}

// MARK: - All Reminders Row

private struct AllRemindersRow: View {
    let item: ReminderItem
    let rank: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                ZStack {
                    Circle()
                        .fill(badgeColor(rank: rank))
                        .frame(width: 32, height: 32)
                    Text("\(rank)")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.white)
                }
            } else {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "minus")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    // List colour dot + name
                    if let cal = item.ekReminder.calendar {
                        Circle()
                            .fill(Color(cgColor: cal.cgColor))
                            .frame(width: 8, height: 8)
                    }
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
        }
        .padding(.vertical, 2)
    }

    private func badgeColor(rank: Int) -> Color {
        switch rank {
        case 1: return .blue
        case 2: return .indigo
        case 3: return .purple
        default: return Color(.systemGray3)
        }
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
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(calendar.title)
                    .font(.body.bold())

                if rankedCount > 0 {
                    Text("\(rankedCount) ranked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    eloSparkline
                } else if totalCount > 0 {
                    Text("\(totalCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var eloSparkline: some View {
        let ranked = records.filter { $0.comparisonCount > 0 }
                            .sorted { $0.eloRating > $1.eloRating }
        if ranked.count >= 2 {
            let maxR = ranked[0].eloRating
            let minR = ranked[ranked.count - 1].eloRating
            let range = max(maxR - minR, 1.0)
            let listColor = Color(cgColor: calendar.cgColor)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(ranked.prefix(10).enumerated()), id: \.offset) { _, record in
                    let h = 4.0 + 12.0 * ((record.eloRating - minR) / range)
                    Capsule()
                        .fill(listColor.opacity(0.75))
                        .frame(width: 4, height: h)
                }
            }
            .frame(height: 16, alignment: .bottom)
        }
    }
}
