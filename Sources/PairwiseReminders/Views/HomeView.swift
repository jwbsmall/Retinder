import SwiftUI
import SwiftData
import EventKit

/// Root view. Shows all Reminders lists with configurable grouping.
/// Default: grouped by list with collapsible sections.
/// Alternate modes: flat (all reminders sorted by Elo) or grouped by due date.
struct HomeView: View {

    // MARK: - Grouping

    enum GroupingMode: String, CaseIterable {
        case byList    = "by_list"
        case flat      = "flat"
        case byDueDate = "by_due_date"

        var label: String {
            switch self {
            case .byList:    return "List"
            case .flat:      return "All"
            case .byDueDate: return "Due Date"
            }
        }
    }

    enum SortMode: String, CaseIterable {
        case priority = "priority"
        case title    = "title"
        case dueDate  = "due_date"

        var label: String {
            switch self {
            case .priority: return "Priority"
            case .title:    return "Title"
            case .dueDate:  return "Due Date"
            }
        }
    }

    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @Query private var allRecords: [RankedItemRecord]

    @State private var selectedList: EKCalendar?
    @State private var showPrioritise = false
    @State private var showSettings = false
    @State private var showPrioritiseOptions = false
    @State private var showHistory = false

    @State private var expandedListIDs: Set<String> = []
    // Unified selection — contains calendar IDs (lists) and/or reminder item IDs.
    // Callers split by checking against remindersManager.lists to distinguish the two.
    @State private var itemSelection: Set<String> = []
    @State private var editMode: EditMode = .inactive
    @State private var itemsByList: [String: [ReminderItem]] = [:]
    @State private var loadingListIDs: Set<String> = []

    private var isSelecting: Bool { editMode == .active }

    @State private var groupingMode: GroupingMode = {
        GroupingMode(rawValue: UserDefaults.standard.string(forKey: "grouping_mode") ?? "") ?? .byList
    }()

    @State private var sortMode: SortMode = {
        SortMode(rawValue: UserDefaults.standard.string(forKey: "sort_mode") ?? "") ?? .priority
    }()

    private var allExpanded: Bool {
        !remindersManager.lists.isEmpty &&
        remindersManager.lists.allSatisfy { expandedListIDs.contains($0.calendarIdentifier) }
    }

    // MARK: - Cross-list data (flat + date modes)

    private var allItems: [ReminderItem] {
        sortItems(itemsByList.values.flatMap { $0 })
    }

    private func sortItems(_ items: [ReminderItem]) -> [ReminderItem] {
        switch sortMode {
        case .priority:
            return items.sorted { $0.eloRating > $1.eloRating }
        case .title:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .dueDate:
            return items.sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (_?, nil):   return true
                case (nil, _?):   return false
                case (nil, nil):  return $0.eloRating > $1.eloRating
                }
            }
        }
    }

    private var globalEloMin: Double { allItems.filter { $0.comparisonCount > 0 }.last?.eloRating ?? 1000 }
    private var globalEloMax: Double { allItems.filter { $0.comparisonCount > 0 }.first?.eloRating ?? 1000 }

    private struct DateSection: Identifiable {
        let id: String
        let items: [ReminderItem]
    }

    private var dueDateSections: [DateSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let nextWeek = cal.date(byAdding: .day, value: 7, to: today)!

        var buckets: [String: [ReminderItem]] = [
            "Today": [], "Tomorrow": [], "This Week": [], "Later": [], "No Date": []
        ]
        let order = ["Today", "Tomorrow", "This Week", "Later", "No Date"]

        for item in allItems {
            if let due = item.dueDate {
                let day = cal.startOfDay(for: due)
                if day <= today          { buckets["Today"]!.append(item) }
                else if day <= tomorrow  { buckets["Tomorrow"]!.append(item) }
                else if day < nextWeek   { buckets["This Week"]!.append(item) }
                else                     { buckets["Later"]!.append(item) }
            } else {
                buckets["No Date"]!.append(item)
            }
        }
        return order.compactMap { key -> DateSection? in
            guard let items = buckets[key], !items.isEmpty else { return nil }
            return DateSection(id: key, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if remindersManager.lists.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    switch groupingMode {
                    case .byList:    listContent.frame(maxHeight: .infinity)
                    case .flat:      flatContent.frame(maxHeight: .infinity)
                    case .byDueDate: dueDateContent.frame(maxHeight: .infinity)
                    }
                }
                Divider()
                prioritiseButton
            }
            .navigationTitle("Retinder")
            .navigationDestination(item: $selectedList) { calendar in
                ListDetailView(calendar: calendar)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelecting {
                        Button("Cancel") {
                            editMode = .inactive
                            itemSelection = []
                        }
                        .font(.subheadline)
                    } else if groupingMode == .byList {
                        Button(allExpanded ? "Collapse All" : "Expand All") {
                            if allExpanded {
                                expandedListIDs = []
                            } else {
                                let ids = Set(remindersManager.lists.map(\.calendarIdentifier))
                                expandedListIDs = ids
                                ids.forEach { loadItemsIfNeeded(for: $0) }
                            }
                        }
                        .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if isSelecting {
                            EmptyView()
                        } else {
                            Button { showHistory = true } label: {
                                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            }
                            .accessibilityLabel("Comparison history")
                            Menu {
                                Picker("Group By", selection: $groupingMode) {
                                    ForEach(GroupingMode.allCases, id: \.self) { mode in
                                        Text(mode.label).tag(mode)
                                    }
                                }
                                Picker("Sort By", selection: $sortMode) {
                                    ForEach(SortMode.allCases, id: \.self) { mode in
                                        Text(mode.label).tag(mode)
                                    }
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                            .accessibilityLabel("Group and sort options")
                            Button { showSettings = true } label: {
                                Image(systemName: "gear")
                            }
                            .accessibilityLabel("Settings")
                        }
                        Button(isSelecting ? "Done" : "Select") {
                            if editMode == .active {
                                editMode = .inactive
                                itemSelection = []
                            } else {
                                editMode = .active
                            }
                        }
                        .font(.subheadline.weight(isSelecting ? .semibold : .regular))
                    }
                }
            }
            .fullScreenCover(isPresented: $showPrioritise) {
                PrioritiseFlow()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showPrioritiseOptions) {
                PrioritiseOptionsSheet(selectionLabel: prioritiseLabel) {
                    showPrioritiseOptions = false
                    showPrioritise = true
                    editMode = .inactive
                    // Split unified selection into calendar IDs (lists) vs reminder item IDs.
                    let listCalendarIDs = Set(remindersManager.lists.map(\.calendarIdentifier))
                    let selectedItemIDs = itemSelection.filter { !listCalendarIDs.contains($0) }
                    let selectedListIDs = itemSelection.filter { listCalendarIDs.contains($0) }
                    itemSelection = []
                    if !selectedItemIDs.isEmpty {
                        let items = itemsByList.values.flatMap { $0 }.filter { selectedItemIDs.contains($0.id) }
                        Task {
                            await session.start(
                                items: items,
                                eloEngine: eloEngine,
                                context: modelContext
                            )
                        }
                    } else {
                        let lists = selectedListIDs
                        Task {
                            await session.start(
                                listIDs: lists,
                                remindersManager: remindersManager,
                                eloEngine: eloEngine,
                                context: modelContext
                            )
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            // Bridge: when ListDetailView sets pendingListIDs, pre-select + open options.
            .onChange(of: session.pendingListIDs) { _, ids in
                guard !ids.isEmpty else { return }
                itemSelection.formUnion(ids)
                session.pendingListIDs = []
                if !showPrioritise { showPrioritiseOptions = true }
            }
            // Dismiss fullScreenCover when session resets to idle.
            .onChange(of: session.phase) { _, phase in
                if phase == .idle { showPrioritise = false }
            }
            .onChange(of: groupingMode) { _, mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "grouping_mode")
                if mode != .byList { loadAllItemsIfNeeded() }
            }
            .onChange(of: sortMode) { _, mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "sort_mode")
            }
            .task { await remindersManager.fetchLists() }
            .refreshable {
                itemsByList = [:]
                loadingListIDs = []
                await remindersManager.syncWithEventKit(context: modelContext)
            }
        }
    }

    // MARK: - List Content (by list)

    private var listContent: some View {
        List(selection: $itemSelection) {
            ForEach(remindersManager.lists, id: \.calendarIdentifier) { calendar in
                let id = calendar.calendarIdentifier
                let listRecords = records(for: calendar)

                Section {
                    DisclosureGroup(isExpanded: disclosureBinding(for: id)) {
                        expandedContent(for: id, calendar: calendar, records: listRecords)
                    } label: {
                        CollapsedListHeader(calendar: calendar, records: listRecords)
                    }
                    .tag(id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
    }

    private func disclosureBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedListIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedListIDs.insert(id)
                    loadItemsIfNeeded(for: id)
                } else {
                    expandedListIDs.remove(id)
                }
            }
        )
    }

    @ViewBuilder
    private func expandedContent(
        for id: String,
        calendar: EKCalendar,
        records: [RankedItemRecord]
    ) -> some View {
        if loadingListIDs.contains(id) {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
        } else {
            let items = itemsByList[id] ?? []
            let eloSorted = items.filter { $0.comparisonCount > 0 }.sorted { $0.eloRating > $1.eloRating }
            let eloRankByID = Dictionary(uniqueKeysWithValues: eloSorted.enumerated().map { ($1.id, $0 + 1) })
            let ranked = sortItems(eloSorted)
            let unranked = sortItems(items.filter { $0.comparisonCount == 0 })
            let eloMin = eloSorted.last?.eloRating ?? 1000
            let eloMax = eloSorted.first?.eloRating ?? 1000

            if items.isEmpty {
                Text("No incomplete reminders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(ranked, id: \.id) { item in
                    ExpandedItemRow(item: item, rank: eloRankByID[item.id], eloMin: eloMin, eloMax: eloMax)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard editMode == .inactive else { return }
                            selectedList = calendar
                        }
                }
                ForEach(unranked, id: \.id) { item in
                    ExpandedItemRow(item: item, rank: nil, eloMin: eloMin, eloMax: eloMax)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard editMode == .inactive else { return }
                            selectedList = calendar
                        }
                }
            }
        }
    }

    // MARK: - Flat Content (all reminders sorted by Elo)

    private var flatContent: some View {
        List(selection: $itemSelection) {
            if allItems.isEmpty {
                Text("No incomplete reminders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let ranked = allItems.filter { $0.comparisonCount > 0 }
                let unranked = allItems.filter { $0.comparisonCount == 0 }
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
                    ExpandedItemRow(
                        item: item, rank: index + 1,
                        eloMin: globalEloMin, eloMax: globalEloMax,
                        showListName: true
                    )
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard editMode == .inactive else { return }
                        selectedList = remindersManager.lists
                            .first { $0.calendarIdentifier == item.ekReminder.calendar?.calendarIdentifier }
                    }
                }
                ForEach(unranked, id: \.id) { item in
                    ExpandedItemRow(
                        item: item, rank: nil,
                        eloMin: globalEloMin, eloMax: globalEloMax,
                        showListName: true
                    )
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard editMode == .inactive else { return }
                        selectedList = remindersManager.lists
                            .first { $0.calendarIdentifier == item.ekReminder.calendar?.calendarIdentifier }
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .task { loadAllItemsIfNeeded() }
    }

    // MARK: - Due Date Content (sections by date bucket)

    private var dueDateContent: some View {
        List(selection: $itemSelection) {
            if allItems.isEmpty {
                Text("No incomplete reminders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dueDateSections) { section in
                    Section(section.id) {
                        let ranked = section.items.filter { $0.comparisonCount > 0 }
                        let unranked = section.items.filter { $0.comparisonCount == 0 }
                        ForEach(ranked, id: \.id) { item in
                            ExpandedItemRow(
                                item: item, rank: nil,
                                eloMin: globalEloMin, eloMax: globalEloMax,
                                showListName: true
                            )
                            .tag(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editMode == .inactive else { return }
                                selectedList = remindersManager.lists
                                    .first { $0.calendarIdentifier == item.ekReminder.calendar?.calendarIdentifier }
                            }
                        }
                        ForEach(unranked, id: \.id) { item in
                            ExpandedItemRow(
                                item: item, rank: nil,
                                eloMin: globalEloMin, eloMax: globalEloMax,
                                showListName: true
                            )
                            .tag(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editMode == .inactive else { return }
                                selectedList = remindersManager.lists
                                    .first { $0.calendarIdentifier == item.ekReminder.calendar?.calendarIdentifier }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .task { loadAllItemsIfNeeded() }
    }

    // MARK: - Prioritise Button

    private var hasSelection: Bool { !itemSelection.isEmpty }

    private var prioritiseButton: some View {
        VStack(spacing: 0) {
            Button {
                if !hasSelection {
                    // Shortcut: tapping the button starts selection mode
                    editMode = .active
                } else {
                    showPrioritiseOptions = true
                }
            } label: {
                Text(prioritiseLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(hasSelection ? Color.blue : Color(.systemGray4))
                    .foregroundStyle(hasSelection ? .white : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
    }

    private var prioritiseLabel: String {
        guard !itemSelection.isEmpty else { return "Select to Prioritise" }
        let listCalendarIDs = Set(remindersManager.lists.map(\.calendarIdentifier))
        let listCount = itemSelection.filter { listCalendarIDs.contains($0) }.count
        let itemCount = itemSelection.count - listCount
        if itemCount > 0 {
            return "Prioritise \(itemCount == 1 ? "1 Item" : "\(itemCount) Items")"
        }
        return "Prioritise \(listCount == 1 ? "1 List" : "\(listCount) Lists")"
    }

    // MARK: - Empty State

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
    }

    // MARK: - Helpers

    private func records(for calendar: EKCalendar) -> [RankedItemRecord] {
        allRecords.filter { $0.listCalendarIdentifier == calendar.calendarIdentifier }
    }

    private func loadItemsIfNeeded(for id: String) {
        guard itemsByList[id] == nil, !loadingListIDs.contains(id) else { return }
        loadingListIDs.insert(id)
        Task {
            let loaded = (try? await remindersManager.fetchIncompleteReminders(
                from: [id], context: modelContext
            )) ?? []
            itemsByList[id] = loaded
            loadingListIDs.remove(id)
        }
    }

    private func loadAllItemsIfNeeded() {
        for list in remindersManager.lists {
            loadItemsIfNeeded(for: list.calendarIdentifier)
        }
    }
}

// MARK: - Prioritise Flow

/// Full-screen session flow: AI seeding → pairwise comparison → results.
/// List selection and session options are handled before this cover opens.
private struct PrioritiseFlow: View {

    @EnvironmentObject private var session: PairwiseSession

    var body: some View {
        NavigationStack {
            switch session.phase {
            case .idle:      EmptyView()
            case .seeding:   FilteringView()
            case .comparing: PairwiseView()
            case .done:      ResultsView()
            }
        }
    }
}

// MARK: - Prioritise Options Sheet

/// Pre-session configuration: AI seeding options.
/// Tapping Start applies settings and triggers the session.
private struct PrioritiseOptionsSheet: View {

    let selectionLabel: String
    let onStart: () -> Void

    @EnvironmentObject private var session: PairwiseSession
    @Environment(\.dismiss) private var dismiss

    @State private var useAI: Bool
    @State private var criteria: String
    @State private var topNEnabled: Bool
    @State private var topN: Int

    init(selectionLabel: String, onStart: @escaping () -> Void) {
        self.selectionLabel = selectionLabel
        self.onStart = onStart
        let defaults = UserDefaults.standard
        _useAI = State(initialValue:
            (defaults.string(forKey: "ai_preference") ?? "") != PairwiseSession.AIPreference.none.rawValue
        )
        _criteria = State(initialValue: defaults.string(forKey: "ai_criteria") ?? "")
        let savedN = defaults.integer(forKey: "ai_top_n")
        _topNEnabled = State(initialValue: savedN > 0)
        _topN = State(initialValue: savedN > 0 ? savedN : 20)
    }

    private var aiAvailabilityNote: String {
        let hasKey = (KeychainService.load() ?? "").isEmpty == false
        return hasKey
            ? "Anthropic API available."
            : "No API key configured. Add one in Settings."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use AI to pre-rank items", isOn: $useAI)
                    if useAI {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Prioritise criteria")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("e.g. work tasks, deadlines this week", text: $criteria)
                                .textFieldStyle(.plain)
                        }
                        .padding(.vertical, 2)

                        Toggle("Limit to top N items", isOn: $topNEnabled)
                        if topNEnabled {
                            Stepper("Compare top \(topN) items", value: $topN, in: 2...200)
                        }
                    }
                } header: {
                    Text("AI seeding")
                } footer: {
                    if useAI {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(aiAvailabilityNote)
                            if topNEnabled {
                                Text("AI will rank all items but only the top \(topN) will be compared.")
                            } else {
                                Text("AI will estimate an initial ranking before you start comparing pairs.")
                            }
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Items start with equal ratings. No AI is used.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        applyAndStart()
                    } label: {
                        Text("Start — \(selectionLabel)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .navigationTitle("Prioritise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func applyAndStart() {
        session.aiCriteria = criteria
        session.aiTopN = (useAI && topNEnabled) ? topN : nil
        session.aiPreference = useAI ? .api : .none
        dismiss()
        onStart()
    }
}

// MARK: - Collapsed List Header

private struct CollapsedListHeader: View {
    let calendar: EKCalendar
    let records: [RankedItemRecord]

    private var rankedRecords: [RankedItemRecord] {
        records.filter { $0.comparisonCount > 0 }.sorted { $0.eloRating > $1.eloRating }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 10, height: 10)
            Text(calendar.title)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            eloSparkline
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var eloSparkline: some View {
        if rankedRecords.count >= 2 {
            let maxR = rankedRecords[0].eloRating
            let minR = rankedRecords[rankedRecords.count - 1].eloRating
            let range = max(maxR - minR, 1.0)
            let listColor = Color(cgColor: calendar.cgColor)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(rankedRecords.prefix(10).enumerated()), id: \.offset) { _, record in
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

// MARK: - Expanded Item Row

private struct ExpandedItemRow: View {
    let item: ReminderItem
    /// 1-based Elo rank; nil for unranked items.
    let rank: Int?
    let eloMin: Double
    let eloMax: Double
    /// Show the list name as a subtitle — useful in flat/date grouping modes.
    var showListName: Bool = false

    @Environment(\.editMode) private var editMode

    private var isSelecting: Bool { editMode?.wrappedValue == .active }

    private var eloStrength: Double {
        guard rank != nil, eloMax > eloMin else { return 0 }
        return max(0, min(1, (item.eloRating - eloMin) / (eloMax - eloMin)))
    }

    private var barTint: Color {
        if eloStrength > 0.66 { return .blue }
        if eloStrength > 0.33 { return .indigo }
        return Color(.systemGray3)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Hide rank badge in selection mode — SwiftUI draws its own selection circle.
            if !isSelecting {
                if let r = rank {
                    ZStack {
                        Circle()
                            .fill(badgeColor(r))
                            .frame(width: 28, height: 28)
                        Text("\(r)")
                            .font(.system(.caption, design: .rounded).bold())
                            .foregroundStyle(.white)
                    }
                } else {
                    Circle()
                        .strokeBorder(Color(.tertiaryLabel), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if showListName {
                    Text(item.listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Continuous Elo strength bar — only for ranked items
                if rank != nil {
                    ProgressView(value: eloStrength)
                        .tint(barTint)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func badgeColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .blue
        case 2: return .indigo
        case 3: return .purple
        default: return Color(.systemGray3)
        }
    }
}
