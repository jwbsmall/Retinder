import SwiftUI
import SwiftData
import EventKit

/// Entry point for the Prioritise tab. Lets the user select one or more lists,
/// then kicks off the Elo seeding + comparison session.
struct ListPickerView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    @State private var selectedListIDs: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle("Choose Lists")
            .task { await remindersManager.fetchLists() }
    }

    @ViewBuilder
    private var content: some View {
        switch remindersManager.authorizationStatus {
        case .denied, .restricted:
            ContentUnavailableView(
                "Reminders Access Denied",
                systemImage: "bell.slash.fill",
                description: Text("Enable Reminders access in\nSettings › Privacy & Security › Reminders.")
            )
        default:
            if remindersManager.lists.isEmpty {
                ContentUnavailableView(
                    "No Reminder Lists",
                    systemImage: "checklist",
                    description: Text("Create a list in the Reminders app first, then come back.")
                )
            } else {
                listPickerContent
            }
        }
    }

    // MARK: - List Picker

    private var listPickerContent: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    AllRemindersRow(
                        isSelected: isAllSelected,
                        onToggle: toggleAll
                    )
                }
                Section("Lists") {
                    ForEach(remindersManager.lists, id: \.calendarIdentifier) { list in
                        ListPickerRow(
                            list: list,
                            isSelected: selectedListIDs.contains(list.calendarIdentifier),
                            onToggle: { toggle(list) }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Button(action: startSession) {
                Text(startLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canStart ? Color.blue : Color(.systemGray4))
                    .foregroundStyle(canStart ? .white : Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
            .disabled(!canStart)
        }
    }

    // MARK: - Helpers

    private var canStart: Bool { !selectedListIDs.isEmpty }

    private var isAllSelected: Bool {
        !remindersManager.lists.isEmpty &&
        selectedListIDs.count == remindersManager.lists.count
    }

    private var startLabel: String {
        if selectedListIDs.isEmpty { return "Select a list" }
        if isAllSelected { return "Prioritise All Reminders" }
        let n = selectedListIDs.count
        return "Prioritise \(n == 1 ? "1 List" : "\(n) Lists")"
    }

    private func toggleAll() {
        if isAllSelected {
            selectedListIDs.removeAll()
        } else {
            selectedListIDs = Set(remindersManager.lists.map(\.calendarIdentifier))
        }
    }

    private func toggle(_ list: EKCalendar) {
        let id = list.calendarIdentifier
        if selectedListIDs.contains(id) {
            selectedListIDs.remove(id)
        } else {
            selectedListIDs.insert(id)
        }
    }

    private func startSession() {
        errorMessage = nil
        Task {
            await session.start(
                listIDs: selectedListIDs,
                remindersManager: remindersManager,
                eloEngine: eloEngine,
                context: modelContext
            )
            if session.phase == .idle {
                errorMessage = "No incomplete reminders found in the selected lists."
            }
        }
    }
}

// MARK: - List Row

private struct ListPickerRow: View {
    let list: EKCalendar
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(cgColor: list.cgColor))
                    .frame(width: 12, height: 12)
                Text(list.title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                    .font(.title3)
                    .animation(.spring(response: 0.25), value: isSelected)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - All Reminders Row

private struct AllRemindersRow: View {
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 12)
                Text("All Reminders")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                    .font(.title3)
                    .animation(.spring(response: 0.25), value: isSelected)
            }
        }
        .buttonStyle(.plain)
    }
}
