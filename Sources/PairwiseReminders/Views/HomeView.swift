import SwiftUI
import SwiftData
import EventKit

/// Root view. Shows all Reminders lists as collapsible rows.
/// Lists are collapsed by default; tap a header to expand and see ranked items.
/// Select lists via the circle checkmark, then tap the prominent Prioritise button.
struct HomeView: View {

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
    @State private var itemsByList: [String: [ReminderItem]] = [:]
    @State private var loadingListIDs: Set<String> = []

    private var allExpanded: Bool {
        !remindersManager.lists.isEmpty &&
        remindersManager.lists.allSatisfy { expandedListIDs.contains($0.calendarIdentifier) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if remindersManager.lists.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    listContent
                        .frame(maxHeight: .infinity)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showHistory = true } label: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gear")
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
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showPrioritiseOptions) {
                PrioritiseOptionsSheet(listIDs: selectedListIDs) {
                    showPrioritiseOptions = false
                    showPrioritise = true
                    Task {
                        await session.start(
                            listIDs: selectedListIDs,
                            remindersManager: remindersManager,
                            eloEngine: eloEngine,
                            context: modelContext
                        )
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
            .task { await remindersManager.fetchLists() }
            .refreshable {
                itemsByList = [:]
                loadingListIDs = []
                await remindersManager.syncWithEventKit(context: modelContext)
            }
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            ForEach(remindersManager.lists, id: \.calendarIdentifier) { calendar in
                let id = calendar.calendarIdentifier
                let listRecords = records(for: calendar)

                DisclosureGroup(isExpanded: expandBinding(for: id)) {
                    expandedContent(for: id, calendar: calendar, records: listRecords)
                } label: {
                    CollapsedListHeader(
                        calendar: calendar,
                        records: listRecords,
                        isSelected: selectedListIDs.contains(id),
                        onToggleSelect: { toggleSelect(id) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
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
                        .contentShape(Rectangle())
                        .onTapGesture { selectedList = calendar }
                }
                ForEach(unranked, id: \.id) { item in
                    ExpandedItemRow(item: item, rank: nil, eloMin: eloMin, eloMax: eloMax)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedList = calendar }
                }
            }
        }
    }

    // MARK: - Prioritise Button

    private var prioritiseButton: some View {
        VStack(spacing: 0) {
            Button {
                showPrioritiseOptions = true
            } label: {
                Text(prioritiseLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedListIDs.isEmpty ? Color(.systemGray4) : Color.blue)
                    .foregroundStyle(selectedListIDs.isEmpty ? Color.secondary : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .disabled(selectedListIDs.isEmpty)
        }
        .background(.regularMaterial)
    }

    private var prioritiseLabel: String {
        if selectedListIDs.isEmpty { return "Select lists to prioritise" }
        let n = selectedListIDs.count
        return "Prioritise \(n == 1 ? "1 List" : "\(n) Lists")"
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

    private func expandBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedListIDs.contains(id) },
            set: { expanding in
                if expanding {
                    expandedListIDs.insert(id)
                    loadItemsIfNeeded(for: id)
                } else {
                    expandedListIDs.remove(id)
                }
            }
        )
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

    let listIDs: Set<String>
    let onStart: () -> Void

    @EnvironmentObject private var session: PairwiseSession
    @Environment(\.dismiss) private var dismiss

    @State private var rankingMode: PairwiseSession.RankingMode
    @State private var useAI: Bool

    init(listIDs: Set<String>, onStart: @escaping () -> Void) {
        self.listIDs = listIDs
        self.onStart = onStart
        _rankingMode = State(initialValue:
            PairwiseSession.RankingMode(rawValue: UserDefaults.standard.string(forKey: "ranking_mode") ?? "") ?? .overall
        )
        _useAI = State(initialValue:
            (UserDefaults.standard.string(forKey: "ai_preference") ?? "") != PairwiseSession.AIPreference.none.rawValue
        )
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
                } header: {
                    Text("AI seeding")
                } footer: {
                    Text(useAI
                        ? "AI will estimate an initial ranking before you start comparing pairs."
                        : "Items start with equal ratings. No AI is used.")
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        applyAndStart()
                    } label: {
                        Text("Start Prioritising \(listIDs.count == 1 ? "1 List" : "\(listIDs.count) Lists")")
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
        if useAI {
            // Prefer on-device if available, else API, using existing preference as a hint.
            if session.aiPreference == .none {
                session.aiPreference = FoundationModelService.isAvailable ? .onDeviceFirst : .apiFirst
            }
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
    let onToggleSelect: () -> Void

    private var rankedRecords: [RankedItemRecord] {
        records.filter { $0.comparisonCount > 0 }.sorted { $0.eloRating > $1.eloRating }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(cgColor: calendar.cgColor))
                        .frame(width: 10, height: 10)
                    Text(calendar.title)
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                }
                eloSparkline
            }

            Spacer()

            // Selection toggle — high priority gesture prevents DisclosureGroup from intercepting
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                .font(.title3)
                .animation(.spring(response: 0.25), value: isSelected)
                .highPriorityGesture(TapGesture().onEnded { onToggleSelect() })
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
            // Rank badge for compared items; plain circle for unranked (matches Reminders.app)
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

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

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
