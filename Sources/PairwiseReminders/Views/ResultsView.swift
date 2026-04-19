import SwiftUI
import SwiftData

/// Session summary shown after the session finishes.
/// Displays the ranked list and lets the user write results back to Reminders.
struct ResultsView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @State private var showApplySheet = false
    @State private var showHistory = false
    @State private var applyError: String?
    @State private var applied = false
    @State private var detailItem: ReminderItem?
    @State private var editingItem: ReminderItem?
    @State private var isSelectingForRefinement = false
    @State private var selectedForRefinement: Set<String> = []
    @State private var editModeValue: EditMode = .inactive

    @AppStorage("home_tap_default") private var homeTapDefaultRaw: String = TapDefault.edit.rawValue
    private var homeTapDefault: TapDefault { TapDefault(rawValue: homeTapDefaultRaw) ?? .edit }

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
            rankedList
                .frame(maxHeight: .infinity)
                .environment(\.editMode, $editModeValue)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle("Session Results")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Return to pairwise comparison with current session items.
                    session.continueComparing(eloEngine: eloEngine)
                } label: {
                    Label("Back to Compare", systemImage: "arrow.uturn.backward")
                }
                .accessibilityLabel("Continue comparing")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if isSelectingForRefinement {
                        Button("Cancel") {
                            isSelectingForRefinement = false
                            selectedForRefinement = []
                        }
                    } else {
                        Button("Select") {
                            isSelectingForRefinement = true
                            selectedForRefinement = []
                            editModeValue = .inactive
                        }
                        Button {
                            if editModeValue == .active {
                                editModeValue = .inactive
                            } else {
                                editModeValue = .active
                                isSelectingForRefinement = false
                                selectedForRefinement = []
                            }
                        } label: {
                            Text(editModeValue == .active ? "Done" : "Edit")
                        }
                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                        .accessibilityLabel("Comparison history")
                    }
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showApplySheet) {
            ApplySheet(items: session.rankedItems) { options in
                applyOptions(options)
                showApplySheet = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, onEdit: { editingItem = item })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingItem) { item in
            ReminderEditSheet(item: item)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Write-back failed", isPresented: .constant(applyError != nil)) {
            Button("OK") { applyError = nil }
        } message: {
            Text(applyError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Seeding failure banner — orange with specific error when available.
            if session.seedingFailed && session.mode != .pairwise {
                if let errorMessage = session.seedingError {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                } else {
                    Label("AI seeding was unavailable — rankings may be less accurate", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            }
            // Criteria recap — only when seeding succeeded.
            if !session.aiCriteria.isEmpty, session.mode != .pairwise, !session.seedingFailed {
                let n = session.rankedItems.count
                let limitText = session.topN != nil ? "top \(n)" : "all \(n)"
                Text("Ranked by: \(session.aiCriteria) · \(limitText) item\(n == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            if applied {
                Label("Applied to Reminders!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: applied)
    }

    // MARK: - Ranked List

    private var rankedList: some View {
        let ratings = session.rankedItems.map(\.eloRating)
        let minR = ratings.min() ?? 1000
        let maxR = ratings.max() ?? 1000
        return List {
            ForEach(Array(session.rankedItems.enumerated()), id: \.element.id) { index, item in
                let isSelected = selectedForRefinement.contains(item.id)
                SessionRankedRow(item: item, rank: index + 1, total: session.rankedItems.count,
                                 minRating: minR, maxRating: maxR,
                                 isSelecting: isSelectingForRefinement,
                                 isSelected: isSelected)
                    .onTapGesture { handlePrimaryTap(for: item) }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            handleSecondaryTap(for: item)
                        }
                    )
            }
            .onMove { from, to in
                session.reorderRankedItems(from: from, to: to, context: modelContext)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if isSelectingForRefinement {
                let count = selectedForRefinement.count
                FloatingGlassButton(
                    title: count >= 2 ? "Refine \(count) items with Pairwise" : "Select at least 2 items",
                    systemImage: "arrow.left.arrow.right",
                    prominent: count >= 2,
                    disabled: count < 2
                ) {
                    let items = session.rankedItems.filter { selectedForRefinement.contains($0.id) }
                    isSelectingForRefinement = false
                    selectedForRefinement = []
                    session.startRefinement(items: items, eloEngine: eloEngine)
                }

                Button("Cancel") {
                    isSelectingForRefinement = false
                    selectedForRefinement = []
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 22)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            } else {
                HStack(spacing: 12) {
                    FloatingGlassButton(
                        title: "Done",
                        systemImage: "checkmark",
                        prominent: false
                    ) { session.reset(eloEngine: eloEngine) }

                    FloatingGlassButton(
                        title: "Apply",
                        systemImage: "square.and.arrow.down",
                        prominent: true
                    ) { showApplySheet = true }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Tap Handling

    private func handlePrimaryTap(for item: ReminderItem) {
        if isSelectingForRefinement {
            toggleRefinementSelection(item.id)
            return
        }
        switch homeTapDefault {
        case .edit:
            detailItem = item
        case .select:
            isSelectingForRefinement = true
            toggleRefinementSelection(item.id)
        }
    }

    private func handleSecondaryTap(for item: ReminderItem) {
        // Long-press = opposite of primary.
        if isSelectingForRefinement {
            detailItem = item
            return
        }
        switch homeTapDefault {
        case .edit:
            isSelectingForRefinement = true
            toggleRefinementSelection(item.id)
        case .select:
            detailItem = item
        }
    }

    private func toggleRefinementSelection(_ id: String) {
        if selectedForRefinement.contains(id) {
            selectedForRefinement.remove(id)
        } else {
            selectedForRefinement.insert(id)
        }
    }

    // MARK: - Apply

    private func applyOptions(_ options: ApplyOptions) {
        let items = session.rankedItems.filter {
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
            withAnimation(.spring(response: 0.4)) { applied = true }
        } catch {
            applyError = error.localizedDescription
        }
    }
}

// MARK: - Session Ranked Row

private struct SessionRankedRow: View {
    let item: ReminderItem
    let rank: Int
    let total: Int
    let minRating: Double
    let maxRating: Double
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var strength: Double {
        maxRating > minRating ? (item.eloRating - minRating) / (maxRating - minRating) : 0.5
    }

    var strengthColor: Color {
        strength > 0.66 ? .blue : strength > 0.33 ? .indigo : Color(.systemGray3)
    }

    var body: some View {
        HStack(spacing: 14) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                    .frame(width: 28)
            } else {
                ZStack {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 38, height: 38)
                    Text("\(rank)")
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)
                Text(item.listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isSelecting {
                    ProgressView(value: strength)
                        .tint(strengthColor)
                        .frame(width: 80)
                }
            }

            Spacer()

            if !isSelecting {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.priorityLabel(totalCount: total))
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(priorityColor.opacity(0.15))
                        .foregroundStyle(priorityColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    if let confidence = item.aiConfidence {
                        Text("\(confidence)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var badgeColor: Color {
        switch rank {
        case 1: return .blue
        case 2: return .indigo
        case 3: return .purple
        default: return Color(.systemGray3)
        }
    }

    private var priorityColor: Color {
        switch item.priorityColor(totalCount: total) {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return Color(.secondaryLabel)
        }
    }
}

// MARK: - Item Detail Sheet

private struct ItemDetailSheet: View {
    let item: ReminderItem
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(item.title)
                        .font(.title3.bold())
                        .listRowBackground(Color.clear)
                }

                if item.aiConfidence != nil || item.aiSeedRank != nil || item.aiReasoning != nil {
                    Section("AI Assessment") {
                        if let rank = item.aiSeedRank {
                            LabeledContent("AI Rank", value: "#\(rank)")
                        }
                        if let confidence = item.aiConfidence {
                            LabeledContent("Confidence") {
                                HStack(spacing: 8) {
                                    ProgressView(value: Double(confidence), total: 100)
                                        .tint(confidence > 66 ? .blue : confidence > 33 ? .indigo : .secondary)
                                        .frame(width: 60)
                                    Text("\(confidence)%")
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let reasoning = item.aiReasoning, !reasoning.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reasoning")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(reasoning)
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Ranking") {
                    LabeledContent("Elo Rating", value: String(format: "%.0f", item.eloRating))
                    LabeledContent("Comparisons", value: "\(item.comparisonCount)")
                }

                Section {
                    Button {
                        dismiss()
                        onEdit()
                    } label: {
                        Label("Edit Reminder…", systemImage: "pencil")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Item Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Due Date Target (top-level for use in ApplyOptions + PairwiseSession defaults)

enum DueTarget: String, CaseIterable {
    case none     = "none"
    case today    = "today"
    case tomorrow = "tomorrow"
    case nextWeek = "next_week"
    case custom   = "custom"

    var displayName: String {
        switch self {
        case .none:     return "None"
        case .today:    return "Today"
        case .tomorrow: return "Tomorrow"
        case .nextWeek: return "Next week"
        case .custom:   return "Custom…"
        }
    }
}

// MARK: - Apply Options (shared with ListDetailView)

struct ApplyOptions {
    // MARK: Priorities
    enum PriorityMode { case tiered, topN }

    var applyPriorities: Bool = true
    var priorityMode: PriorityMode = .tiered
    /// Top N → High (topN mode)
    var urgentCount: Int = 3
    /// Custom tier counts for tiered mode (remainder gets None).
    var highCount: Int = 1
    var mediumCount: Int = 2
    var lowCount: Int = 2

    // MARK: Due Dates
    var applyDueDates: Bool = false
    /// Count used in topN / priorities-off path.
    var dueDateCount: Int = 3
    var dueTarget: DueTarget = .today
    var customDate: Date = .now
    var includeTime: Bool = false
    var dueTime: Date = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: .now
    ) ?? .now

    // Per-tier due dates — used when priorityMode == .tiered && applyPriorities == true.
    var highDueTarget: DueTarget = .today
    var mediumDueTarget: DueTarget = .tomorrow
    var lowDueTarget: DueTarget = .nextWeek
    var highCustomDate: Date = .now
    var mediumCustomDate: Date = .now
    var lowCustomDate: Date = .now

    /// When true, adds an EKAlarm at the due date on each item that receives a date.
    var addAlarms: Bool = false

    /// Calendar identifiers whose items should be skipped during write-back.
    var excludedListIDs: Set<String> = []

    /// Resolves a DueTarget to a concrete Date, or nil for `.none`.
    func resolvedDate(for target: DueTarget, custom: Date) -> Date? {
        guard target != .none else { return nil }
        let cal = Calendar.current
        let dayStart: Date
        switch target {
        case .none:     return nil
        case .today:    dayStart = cal.startOfDay(for: .now)
        case .tomorrow: dayStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        case .nextWeek: dayStart = cal.date(byAdding: .weekOfYear, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        case .custom:   dayStart = cal.startOfDay(for: custom)
        }
        guard includeTime else { return dayStart }
        let timeComps = cal.dateComponents([.hour, .minute], from: dueTime)
        return cal.date(bySettingHour: timeComps.hour ?? 9,
                        minute: timeComps.minute ?? 0,
                        second: 0, of: dayStart) ?? dayStart
    }

    var resolvedDueDate: Date? { resolvedDate(for: dueTarget, custom: customDate) }

    // MARK: Flags
    var applyFlags: Bool = false
    var flagCount: Int = 1
}

// MARK: - Apply Sheet (shared with ListDetailView)

struct ApplySheet: View {

    let items: [ReminderItem]
    let onApply: (ApplyOptions) -> Void

    @State private var options = ApplyOptions()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: PairwiseSession

    var itemCount: Int { items.count }

    /// True when the due dates section should show per-tier pickers rather than a single date.
    private var useTieredDates: Bool {
        options.applyPriorities && options.priorityMode == .tiered
    }

    /// Distinct lists (calendar ID → name + color) present in the ranked items.
    private var distinctLists: [(id: String, name: String, color: CGColor)] {
        var seen = Set<String>()
        return items.compactMap { item -> (String, String, CGColor)? in
            guard let cal = item.ekReminder.calendar else { return nil }
            let id = cal.calendarIdentifier
            guard seen.insert(id).inserted else { return nil }
            return (id, cal.title, cal.cgColor)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // List exclusion — only shown when items span more than one list.
                if distinctLists.count > 1 {
                    Section {
                        ForEach(distinctLists, id: \.id) { list in
                            let excluded = options.excludedListIDs.contains(list.id)
                            Button {
                                if excluded {
                                    options.excludedListIDs.remove(list.id)
                                } else {
                                    options.excludedListIDs.insert(list.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(cgColor: list.color))
                                        .frame(width: 10, height: 10)
                                    Text(list.name)
                                        .foregroundStyle(excluded ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: excluded ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(excluded ? Color(.tertiaryLabel) : .blue)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Apply to")
                    } footer: {
                        let n = distinctLists.count - options.excludedListIDs.count
                        Text("Write-back will affect \(n) of \(distinctLists.count) list\(distinctLists.count == 1 ? "" : "s"). Excluded lists are ranked but left untouched.")
                    }
                }

                prioritiesSection
                dueDatesSection
                flagsSection
            }
            .onAppear {
                options.highDueTarget   = session.defaultHighDueTarget
                options.mediumDueTarget = session.defaultMediumDueTarget
                options.lowDueTarget    = session.defaultLowDueTarget
            }
            .navigationTitle("Apply to Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(options) }
                        .bold()
                        .disabled(!options.applyPriorities && !options.applyDueDates && !options.applyFlags)
                }
            }
        }
    }

    // MARK: - Sections

    private var prioritiesSection: some View {
        Section {
            Toggle("Set priorities", isOn: $options.applyPriorities)
            if options.applyPriorities {
                Picker("Mode", selection: $options.priorityMode) {
                    Text("Tiered").tag(ApplyOptions.PriorityMode.tiered)
                    Text("Top N").tag(ApplyOptions.PriorityMode.topN)
                }
                .pickerStyle(.segmented)
                if options.priorityMode == .topN {
                    Stepper(
                        "Top \(options.urgentCount) → High, rest → None",
                        value: $options.urgentCount,
                        in: 1...max(1, itemCount)
                    )
                } else {
                    Stepper("High: \(options.highCount)", value: $options.highCount,
                            in: 0...max(0, itemCount - options.mediumCount - options.lowCount))
                    Stepper("Medium: \(options.mediumCount)", value: $options.mediumCount,
                            in: 0...max(0, itemCount - options.highCount - options.lowCount))
                    Stepper("Low: \(options.lowCount)", value: $options.lowCount,
                            in: 0...max(0, itemCount - options.highCount - options.mediumCount))
                    let noneCount = max(0, itemCount - options.highCount - options.mediumCount - options.lowCount)
                    LabeledContent("None (remainder)", value: "\(noneCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Priorities")
        } footer: {
            if options.applyPriorities && options.priorityMode == .topN {
                Text("Items 1–\(options.urgentCount) → High. All others → None.")
            }
        }
    }

    private var dueDatesSection: some View {
        Section {
            Toggle("Set due dates", isOn: $options.applyDueDates)
            if options.applyDueDates {
                if useTieredDates {
                    // Per-tier date pickers — counts are inherited from the Priorities section.
                    tierDuePicker(label: "High",   target: $options.highDueTarget,   custom: $options.highCustomDate)
                    tierDuePicker(label: "Medium", target: $options.mediumDueTarget, custom: $options.mediumCustomDate)
                    tierDuePicker(label: "Low",    target: $options.lowDueTarget,    custom: $options.lowCustomDate)
                    timeAndAlarmControls
                } else {
                    Stepper(
                        "Top \(options.dueDateCount) item\(options.dueDateCount == 1 ? "" : "s")",
                        value: $options.dueDateCount,
                        in: 1...max(1, itemCount)
                    )
                    Picker("Due", selection: $options.dueTarget) {
                        ForEach(DueTarget.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    if options.dueTarget == .custom {
                        DatePicker("Date", selection: $options.customDate,
                                   in: Date.now...,
                                   displayedComponents: options.includeTime ? [.date, .hourAndMinute] : .date)
                    }
                    if options.dueTarget != .none {
                        timeAndAlarmControls
                    }
                }
            }
        } header: {
            Text("Due Dates")
        } footer: {
            if options.applyDueDates {
                if useTieredDates {
                    Text("Each priority tier receives its own due date.")
                } else if options.dueTarget == .none {
                    Text("No due dates will be set.")
                        .foregroundStyle(.secondary)
                } else {
                    let n = options.dueDateCount
                    Text("Sets date\(options.includeTime ? " + time" : "") on the top \(n) item\(n == 1 ? "" : "s").")
                }
            }
        }
    }

    @ViewBuilder
    private var timeAndAlarmControls: some View {
        Toggle("Set time", isOn: $options.includeTime)
            .onChange(of: options.includeTime) { _, hasTime in
                if !hasTime { options.addAlarms = false }
            }
        if options.includeTime && !useTieredDates && options.dueTarget != .custom {
            DatePicker("Time", selection: $options.dueTime,
                       displayedComponents: .hourAndMinute)
        }
        Toggle("Add reminder alert", isOn: $options.addAlarms)
            .disabled(!options.includeTime)
        if !options.includeTime {
            Text("Set a time above to enable reminder alerts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func tierDuePicker(
        label: String,
        target: Binding<DueTarget>,
        custom: Binding<Date>
    ) -> some View {
        Picker(label, selection: target) {
            ForEach(DueTarget.allCases, id: \.self) { t in
                Text(t.displayName).tag(t)
            }
        }
        if target.wrappedValue == .custom {
            DatePicker("Date (\(label))", selection: custom,
                       in: Date.now...,
                       displayedComponents: options.includeTime ? [.date, .hourAndMinute] : .date)
        }
    }

    private var flagsSection: some View {
        Section {
            Toggle("Flag top items", isOn: $options.applyFlags)
            if options.applyFlags {
                Stepper(
                    "Flag top \(options.flagCount) item\(options.flagCount == 1 ? "" : "s")",
                    value: $options.flagCount,
                    in: 1...max(1, itemCount)
                )
            }
        } header: {
            Text("Flags")
        } footer: {
            if options.applyFlags {
                Text("Flags the top \(options.flagCount) item\(options.flagCount == 1 ? "" : "s") in Reminders. Clears flags from all others in the session.")
            }
        }
    }
}

// MARK: - Floating Glass Button (shared across views)

/// Large tasteful floating-material button. Used at the bottom of Home, Results,
/// and Pairwise screens for the primary action.
struct FloatingGlassButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = true
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.headline)
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().fill(prominent ? Color.blue.opacity(0.85) : Color.clear)
                    )
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            )
            .opacity(disabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Reminder Edit Sheet (shared across views)

struct ReminderEditSheet: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @Environment(\.dismiss) private var dismiss

    let item: ReminderItem

    @State private var title: String
    @State private var notes: String
    @State private var selectedCalendarID: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var saveError: String?

    init(item: ReminderItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes ?? "")
        _selectedCalendarID = State(initialValue: item.ekReminder.calendar?.calendarIdentifier ?? "")
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("List") {
                    Picker("List", selection: $selectedCalendarID) {
                        ForEach(remindersManager.lists, id: \.calendarIdentifier) { list in
                            Text(list.title).tag(list.calendarIdentifier)
                        }
                    }
                }
                Section {
                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                }
                if let error = saveError {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            try remindersManager.updateReminder(
                item,
                title: title.trimmingCharacters(in: .whitespaces),
                notes: notes.isEmpty ? nil : notes,
                calendarID: selectedCalendarID,
                dueDate: hasDueDate ? dueDate : nil
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
