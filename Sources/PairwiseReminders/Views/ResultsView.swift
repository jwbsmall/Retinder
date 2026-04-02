import SwiftUI
import UIKit

/// Shows the final ranked list and lets the user write priorities back to Reminders.
struct ResultsView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var engine: PairwiseEngine

    @State private var showApplySheet = false
    @State private var showSuccessBanner = false
    @State private var isApplying = false
    @State private var didCopy = false
    @State private var editingItem: ReminderItem?
    @Environment(\.editMode) private var editMode

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSuccessBanner {
                    successBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                rankedList

                if let error = session.applyError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                bottomBar
            }
            .navigationTitle("Your Priorities")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showApplySheet) {
                ApplySheet(itemCount: session.rankedItems.count, isApplying: isApplying) { options in
                    applyOptions(options)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingItem, onDismiss: {
                // Force SwiftUI to re-read computed properties after ekReminder mutation
                let items = session.rankedItems
                session.rankedItems = items
            }) { item in
                ReminderEditSheet(item: item)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            // Auto-save ranking as soon as results appear, even if user never taps Apply.
            RankingStore.save(rankedItems: session.rankedItems, forLists: session.selectedListIDs)
        }
    }

    // MARK: - Sub-views

    private var successBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Applied to Reminders!")
                .font(.subheadline.bold())
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.12))
    }

    private var rankedList: some View {
        List {
            ForEach(session.rankedItems) { item in
                RankedRow(
                    item: item,
                    rank: (session.rankedItems.firstIndex(of: item) ?? 0) + 1,
                    total: session.rankedItems.count
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard editMode?.wrappedValue != .active else { return }
                    editingItem = item
                }
            }
            .onMove(perform: moveItems)
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        session.rankedItems.move(fromOffsets: source, toOffset: destination)
        for i in session.rankedItems.indices {
            session.rankedItems[i].sortRank = i
        }
        session.didApply = false
        RankingStore.save(rankedItems: session.rankedItems, forLists: session.selectedListIDs)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider().padding(.bottom, 2)

            Button(action: { showApplySheet = true }) {
                Label(
                    session.didApply ? "Applied!" : "Apply to Reminders…",
                    systemImage: session.didApply ? "checkmark" : "square.and.arrow.down"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(session.didApply ? Color.green : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(session.didApply || isApplying)
            .padding(.horizontal)

            HStack {
                Button(action: copyList) {
                    Label(didCopy ? "Copied!" : "Copy list", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .animation(.default, value: didCopy)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Start Over") { engine.reset(); session.reset() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func applyOptions(_ options: ApplyOptions) {
        isApplying = true
        session.applyError = nil
        showApplySheet = false

        Task { @MainActor in
            defer { isApplying = false }
            do {
                if options.applyPriorities {
                    switch options.priorityMode {
                    case .tiered:
                        try remindersManager.applyPriorities(session.rankedItems)
                    case .urgent:
                        try remindersManager.applyTopNUrgent(session.rankedItems, count: options.urgentCount)
                    }
                }
                if options.applyDueDates {
                    try remindersManager.applyDueDates(
                        session.rankedItems,
                        count: options.dueDateCount,
                        dueDate: options.resolvedDueDate
                    )
                }
                if options.scheduleAlarms {
                    if #available(iOS 26, *) {
                        #if canImport(AlarmKit)
                        try await remindersManager.applyAlarms(session.rankedItems, count: options.alarmCount)
                        #endif
                    }
                }
                session.didApply = true
                withAnimation(.spring(response: 0.4)) { showSuccessBanner = true }
            } catch {
                session.applyError = error.localizedDescription
            }
        }
    }

    private func copyList() {
        let text = session.rankedItems.enumerated()
            .map { "\($0 + 1). \($1.title)" }
            .joined(separator: "\n")
        UIPasteboard.general.string = text
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { didCopy = false }
        }
    }
}

// MARK: - Apply Options

struct ApplyOptions {
    enum PriorityMode { case tiered, urgent }
    enum DueTarget { case today, tomorrow, nextWeek, custom }

    var applyPriorities: Bool = true
    var priorityMode: PriorityMode = .tiered
    var urgentCount: Int = 3

    var applyDueDates: Bool = false
    var dueDateCount: Int = 3
    var dueTarget: DueTarget = .today
    var customDate: Date = .now

    var scheduleAlarms: Bool = false
    var alarmCount: Int = 3

    var resolvedDueDate: Date {
        let cal = Calendar.current
        switch dueTarget {
        case .today:     return cal.startOfDay(for: .now)
        case .tomorrow:  return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        case .nextWeek:  return cal.date(byAdding: .weekOfYear, value: 1, to: cal.startOfDay(for: .now))!
        case .custom:    return cal.startOfDay(for: customDate)
        }
    }
}

// MARK: - Apply Sheet

private struct ApplySheet: View {

    let itemCount: Int
    let isApplying: Bool
    let onApply: (ApplyOptions) -> Void

    @State private var options = ApplyOptions()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Priorities
                Section {
                    Toggle("Set priorities", isOn: $options.applyPriorities)

                    if options.applyPriorities {
                        Picker("Mode", selection: $options.priorityMode) {
                            Text("Tiered").tag(ApplyOptions.PriorityMode.tiered)
                            Text("Top N urgent").tag(ApplyOptions.PriorityMode.urgent)
                        }
                        .pickerStyle(.segmented)

                        if options.priorityMode == .urgent {
                            Stepper(
                                "Top \(options.urgentCount) → High, rest → None",
                                value: $options.urgentCount,
                                in: 1...max(1, itemCount)
                            )
                        }
                    }
                } header: {
                    Text("Priorities")
                } footer: {
                    if options.applyPriorities {
                        Text(options.priorityMode == .tiered
                            ? "Top 25% → High, next 25% → Medium, next 25% → Low, rest → None."
                            : "Items 1–\(options.urgentCount) → High priority. All others → None.")
                    }
                }

                // Due Dates
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
                            DatePicker(
                                "Date",
                                selection: $options.customDate,
                                in: Date.now...,
                                displayedComponents: .date
                            )
                        }
                    }
                } header: {
                    Text("Due Dates")
                } footer: {
                    if options.applyDueDates {
                        Text("Sets the due date on the top \(options.dueDateCount) item\(options.dueDateCount == 1 ? "" : "s"). Does not set a time or notification.")
                    }
                }

                // Alarms
                if #available(iOS 26, *) {
                    Section {
                        Toggle("Set urgent alerts", isOn: $options.scheduleAlarms)

                        if options.scheduleAlarms {
                            Stepper(
                                "Top \(options.alarmCount) item\(options.alarmCount == 1 ? "" : "s")",
                                value: $options.alarmCount,
                                in: 1...max(1, itemCount)
                            )
                        }
                    } header: {
                        Text("Alarms")
                    } footer: {
                        if options.scheduleAlarms {
                            Text("Schedules an alarm for the top \(options.alarmCount) item\(options.alarmCount == 1 ? "" : "s") that fires even when Do Not Disturb is on.")
                        }
                    }
                }
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
                        .disabled(isApplying || (!options.applyPriorities && !options.applyDueDates && !options.scheduleAlarms))
                }
            }
        }
    }
}

// MARK: - Reminder Edit Sheet

private struct ReminderEditSheet: View {

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

// MARK: - Ranked Row

private struct RankedRow: View {
    let item: ReminderItem
    let rank: Int
    let total: Int

    private var priorityLabel: String { item.priorityLabel(totalCount: total) }
    private var priorityColor: Color  { mapColor(item.priorityColor(totalCount: total)) }

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

                HStack(spacing: 6) {
                    Text(item.listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let reasoning = item.aiReasoning {
                        Text("·").foregroundStyle(Color(.tertiaryLabel))
                        Text(reasoning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(priorityLabel)
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

    private func mapColor(_ c: ReminderItem.PriorityColor) -> Color {
        switch c {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        case .none:   return Color(.secondaryLabel)
        }
    }
}
