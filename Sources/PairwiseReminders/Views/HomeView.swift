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
    @State private var selectedListIDs: Set<String> = []
    @State private var itemSelection: Set<String> = []  // item IDs bound to List(selection:)
    @State private var editMode: EditMode = .inactive
    @State private var itemsByList: [String: [ReminderItem]] = [:]
    @State private var loadingListIDs: Set<String> = []

    private var isSelecting: Bool { editMode == .active }

    @State private var groupingMode: GroupingMode = {
        GroupingMode(rawValue: UserDefaults.standard.string(forKey: "grouping_mode") ?? "") ?? .byList
    }()

    private var allExpanded: Bool {
        !remindersManager.lists.isEmpty &&
        remindersManager.lists.allSatisfy { expandedListIDs.contains($0.calendarIdentifier) }
    }

    // MARK: - Cross-list data (flat + date modes)

    private var allItems: [ReminderItem] {
        itemsByList.values.flatMap { $0 }.sorted { $0.eloRating > $1.eloRating }
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
                    groupingPickerBar

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
                            selectedListIDs = []
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
                            Button { showSettings = true } label: {
                                Image(systemName: "gear")
                            }
                        }
                        Button(isSelecting ? "Done" : "Select") {
                            if editMode == .active {
                                editMode = .inactive
                                selectedListIDs = []
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
                    if !itemSelection.isEmpty {
                        // Item-level selection: pass pre-loaded items directly.
                        let ids = itemSelection
                        let items = itemsByList.values.flatMap { $0 }.filter { ids.contains($0.id) }
                        itemSelection = []
                        Task {
                            await session.start(
                                items: items,
                                eloEngine: eloEngine,
                                context: modelContext
                            )
                        }
                    } else {
                        Task {
                            await session.start(
                                listIDs: selectedListIDs,
                                remindersManager: remindersManager,
                                eloEngine: eloEngine,
                                context: modelContext
                            )
                        }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            // Bridge: when ListDetailView sets pendingListIDs, pre-select + open options.
            .onChange(of: session.pendingListIDs) { _, ids in
                guard !ids.isEmpty else { return }
                selectedListIDs.formUnion(ids)
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
            .task { await remindersManager.fetchLists() }
            .refreshable {
                itemsByList = [:]
                loadingListIDs = []
                await remindersManager.syncWithEventKit(context: modelContext)
            }
        }
    }

    // MARK: - Grouping Picker

    private var groupingPickerBar: some View {
        Picker("Group by", selection: $groupingMode) {
            ForEach(GroupingMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - List Content (by list)

    private var listContent: some View {
        List(selection: $itemSelection) {
            ForEach(remindersManager.lists, id: \.calendarIdentifier) { calendar in
                let id = calendar.calendarIdentifier
                let listRecords = records(for: calendar)

                Section {
                    if expandedListIDs.contains(id) {
                        expandedContent(for: id, calendar: calendar, records: listRecords)
                    }
                } header: {
                    Button {
                        if expandedListIDs.contains(id) {
                            expandedListIDs.remove(id)
                        } else {
                            expandedListIDs.insert(id)
                            loadItemsIfNeeded(for: id)
                        }
                    } label: {
                        CollapsedListHeader(
                            calendar: calendar,
                            records: listRecords,
                            isSelected: selectedListIDs.contains(id),
                            isSelecting: isSelecting,
                            onToggleSelect: { toggleSelect(id) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
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
            let ranked = items.filter { $0.comparisonCount > 0 }
                              .sorted { $0.eloRating > $1.eloRating }
            let unranked = items.filter { $0.comparisonCount == 0 }
            let eloMin = ranked.last?.eloRating ?? 1000
            let eloMax = ranked.first?.eloRating ?? 1000

            if items.isEmpty {
                Text("No incomplete reminders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, item in
                    ExpandedItemRow(item: item, rank: index + 1, eloMin: eloMin, eloMax: eloMax)
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

    private var hasSelection: Bool { !selectedListIDs.isEmpty || !itemSelection.isEmpty }

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
        if !itemSelection.isEmpty {
            let n = itemSelection.count
            return "Prioritise \(n == 1 ? "1 Item" : "\(n) Items")"
        }
        if !selectedListIDs.isEmpty {
            let n = selectedListIDs.count
            return "Prioritise \(n == 1 ? "1 List" : "\(n) Lists")"
        }
        return "Select to Prioritise"
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

    private func toggleSelect(_ id: String) {
        if selectedListIDs.contains(id) {
            selectedListIDs.remove(id)
        } else {
            selectedListIDs.insert(id)
        }
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

/// Pre-session configuration: compare-by mode and AI/pairwise method.
/// Tapping Start applies settings and triggers the session.
private struct PrioritiseOptionsSheet: View {

    let selectionLabel: String
    let onStart: () -> Void

    @EnvironmentObject private var session: PairwiseSession
    @Environment(\.dismiss) private var dismiss

    @State private var rankingMode: PairwiseSession.RankingMode
    @State private var useAI: Bool
    @State private var criteria: String
    @State private var topNEnabled: Bool
    @State private var topN: Int

    private static let topNOptions = [5, 10, 15, 20, 30]

    init(selectionLabel: String, onStart: @escaping () -> Void) {
        self.selectionLabel = selectionLabel
        self.onStart = onStart
        let defaults = UserDefaults.standard
        _rankingMode = State(initialValue:
            PairwiseSession.RankingMode(rawValue: defaults.string(forKey: "ranking_mode") ?? "") ?? .overall
        )
        _useAI = State(initialValue:
            (defaults.string(forKey: "ai_preference") ?? "") != PairwiseSession.AIPreference.none.rawValue
        )
        _criteria = State(initialValue: defaults.string(forKey: "ai_criteria") ?? "")
        let savedN = defaults.integer(forKey: "ai_top_n")
        _topNEnabled = State(initialValue: savedN > 0)
        _topN = State(initialValue: savedN > 0 ? savedN : 10)
    }

    private var aiAvailabilityNote: String {
        let hasKey = (KeychainService.load() ?? "").isEmpty == false
        let hasOnDevice = FoundationModelService.isAvailable
        if hasOnDevice && hasKey { return "On-device AI + Anthropic API available." }
        if hasOnDevice { return "On-device AI available." }
        if hasKey { return "Anthropic API available." }
        return "No AI backend configured. Add an API key in Settings."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Compare by", selection: $rankingMode) {
                        ForEach(PairwiseSession.RankingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Compare by")
                } footer: {
                    Text(rankingMode.comparisonQuestion)
                        .foregroundStyle(.secondary)
                }

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
                            Picker("Items to compare", selection: $topN) {
                                ForEach(Self.topNOptions, id: \.self) { n in
                                    Text("\(n) items").tag(n)
                                }
                            }
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
                        Text("Start Prioritising \(selectionLabel)")
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
        session.rankingMode = rankingMode
        session.aiCriteria = criteria
        session.aiTopN = (useAI && topNEnabled) ? topN : nil
        if useAI {
            // Always recompute — pick the best available backend.
            session.aiPreference = FoundationModelService.isAvailable ? .onDeviceFirst : .apiFirst
        } else {
            session.aiPreference = .none
        }
        dismiss()
        onStart()
    }
}

// MARK: - Collapsed List Header

private struct CollapsedListHeader: View {
    let calendar: EKCalendar
    let records: [RankedItemRecord]
    let isSelected: Bool
    let isSelecting: Bool
    let onToggleSelect: () -> Void

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
            eloSparkline
                .fixedSize(horizontal: true, vertical: false)

            Spacer()

            // Selection circle — only visible in selection mode (cleaner idle state)
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                    .font(.title3)
                    .animation(.spring(response: 0.25), value: isSelected)
                    .highPriorityGesture(TapGesture().onEnded { onToggleSelect() })
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
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
    /// 1-based rank for items that have been compared; nil for unranked items.
    let rank: Int?
    let eloMin: Double
    let eloMax: Double
    /// Show the list name as a subtitle — useful in flat/date grouping modes.
    var showListName: Bool = false
    var isSelecting: Bool = false
    var isSelected: Bool = false

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
            // In selection mode: checkmark circle. Otherwise: rank badge or plain circle.
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                    .font(.title3)
                    .animation(.spring(response: 0.2), value: isSelected)
            } else if let r = rank {
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
