import SwiftUI

/// Session summary shown after the Elo comparison finishes ("Done for now" or convergence).
/// Displays the ranked list and lets the user write results back to Reminders,
/// then returns to idle so the Prioritise tab resets.
struct ResultsView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var eloEngine: EloEngine

    @State private var showApplySheet = false
    @State private var showHistory = false
    @State private var applyError: String?
    @State private var applied = false
    @State private var editingItem: ReminderItem?

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
            rankedList
                .frame(maxHeight: .infinity)
            bottomBar
        }
        .navigationTitle("Session Results")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                .accessibilityLabel("Comparison history")
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
        VStack(spacing: 6) {
            if session.seedingFailed && session.aiPreference != .none {
                Label("AI seeding was unavailable — rankings may be less accurate", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
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
                SessionRankedRow(item: item, rank: index + 1, total: session.rankedItems.count,
                                 minRating: minR, maxRating: maxR)
                    .onTapGesture { editingItem = item }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider().padding(.bottom, 2)

            Button {
                showApplySheet = true
            } label: {
                Label("Apply to Reminders…", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)

            Button("Done") {
                session.reset(eloEngine: eloEngine)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
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
                try remindersManager.applyDueDates(
                    items,
                    count: options.dueDateCount,
                    dueDate: options.resolvedDueDate,
                    includeTime: options.includeTime
                )
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

    var strength: Double {
        maxRating > minRating ? (item.eloRating - minRating) / (maxRating - minRating) : 0.5
    }

    var strengthColor: Color {
        strength > 0.66 ? .blue : strength > 0.33 ? .indigo : Color(.systemGray3)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 38, height: 38)
                Text("\(rank)")
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)
                Text(item.listName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: strength)
                    .tint(strengthColor)
                    .frame(width: 80)
            }

            Spacer()

            Text(item.priorityLabel(totalCount: total))
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(priorityColor.opacity(0.15))
                .foregroundStyle(priorityColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
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
    var dueDateCount: Int = 3
    var dueTarget: DueTarget = .today
    var customDate: Date = .now
    var includeTime: Bool = false
    var dueTime: Date = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: .now
    ) ?? .now

    /// Calendar identifiers whose items should be skipped during write-back.
    var excludedListIDs: Set<String> = []

    enum DueTarget { case today, tomorrow, nextWeek, custom }

    var resolvedDueDate: Date {
        let cal = Calendar.current
        let dayStart: Date
        switch dueTarget {
        case .today:    dayStart = cal.startOfDay(for: .now)
        case .tomorrow: dayStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        case .nextWeek: dayStart = cal.date(byAdding: .weekOfYear, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        case .custom:   dayStart = cal.startOfDay(for: customDate)
        }
        guard includeTime else { return dayStart }
        let timeComps = cal.dateComponents([.hour, .minute], from: dueTime)
        return cal.date(bySettingHour: timeComps.hour ?? 9,
                        minute: timeComps.minute ?? 0,
                        second: 0, of: dayStart) ?? dayStart
    }

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

    var itemCount: Int { items.count }

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
            .navigationTitle("Apply to Reminders")
            .navigationBarTitleDisplayMode(.inline)
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
                    Text("Distribute").tag(ApplyOptions.PriorityMode.tiered)
                    Text("Top N only").tag(ApplyOptions.PriorityMode.topN)
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
                }
            }
        } header: {
            Text("Priorities")
        } footer: {
            if options.applyPriorities {
                if options.priorityMode == .topN {
                    Text("Items 1–\(options.urgentCount) → High. All others → None.")
                } else {
                    let h = options.highCount, m = options.mediumCount, l = options.lowCount
                    let none = max(0, itemCount - h - m - l)
                    Text("High: \(h)  Medium: \(m)  Low: \(l)  None: \(none)")
                }
            }
        }
    }

    private var dueDatesSection: some View {
        Section {
            Toggle("Set due dates", isOn: $options.applyDueDates)
            if options.applyDueDates {
                Stepper(
                    "Top \(options.dueDateCount) item\(options.dueDateCount == 1 ? "" : "s")",
                    value: $options.dueDateCount,
                    in: 1...max(1, itemCount)
                )
                Picker("Due", selection: $options.dueTarget) {
                    Text("Today").tag(ApplyOptions.DueTarget.today)
                    Text("Tomorrow").tag(ApplyOptions.DueTarget.tomorrow)
                    Text("Next week").tag(ApplyOptions.DueTarget.nextWeek)
                    Text("Custom…").tag(ApplyOptions.DueTarget.custom)
                }
                if options.dueTarget == .custom {
                    DatePicker("Date", selection: $options.customDate,
                               in: Date.now...,
                               displayedComponents: options.includeTime ? [.date, .hourAndMinute] : .date)
                }
                Toggle("Set time", isOn: $options.includeTime)
                if options.includeTime && options.dueTarget != .custom {
                    DatePicker("Time", selection: $options.dueTime,
                               displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text("Due Dates")
        } footer: {
            if options.applyDueDates {
                let n = options.dueDateCount
                if options.includeTime {
                    Text("Sets date + time on the top \(n) item\(n == 1 ? "" : "s").")
                } else {
                    Text("Sets date (no time) on the top \(n) item\(n == 1 ? "" : "s").")
                }
            }
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
