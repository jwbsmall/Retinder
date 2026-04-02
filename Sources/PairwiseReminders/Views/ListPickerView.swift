import SwiftUI
import EventKit

/// Lets the user choose which Reminder list(s) to prioritise.
struct ListPickerView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAPIKeySheet = false
    @State private var showResumeAlert = false
    @State private var pendingStoredOrder: [String]? = nil

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Choose Lists")
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingAPIKeySheet) {
                    APIKeySheet()
                }
                .alert("Resume Previous Ranking?", isPresented: $showResumeAlert) {
                    Button("Resume") {
                        if let order = pendingStoredOrder {
                            session.applyStoredRanking(order)
                            session.phase = .results
                        }
                    }
                    Button("Start Fresh", role: .destructive) {
                        RankingStore.clear(forLists: session.selectedListIDs)
                        session.phase = .filtering
                    }
                    Button("Cancel", role: .cancel) {
                        session.allItems = []
                        pendingStoredOrder = nil
                    }
                } message: {
                    Text("You've ranked these lists before. Pick up where you left off, or start a new comparison.")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch remindersManager.authorizationStatus {
        case .denied, .restricted:
            accessDeniedView
        default:
            if remindersManager.lists.isEmpty {
                emptyListsView
            } else {
                listPickerContent
            }
        }
    }

    // MARK: - Sub-views

    private var listPickerContent: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    AllRemindersRow(isSelected: isAllSelected, onToggle: toggleAll)
                }
                Section("Lists") {
                    ForEach(remindersManager.lists, id: \.calendarIdentifier) { list in
                        ListRow(
                            list: list,
                            isSelected: session.selectedListIDs.contains(list.calendarIdentifier),
                            onToggle: { toggleList(list) }
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

            Button(action: startFiltering) {
                Group {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text("Prioritise \(selectedCount)")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canStart ? Color.blue : Color(.systemGray4))
                .foregroundStyle(canStart ? .white : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
            .disabled(!canStart || isLoading)
        }
    }

    private var accessDeniedView: some View {
        ContentUnavailableView(
            "Reminders Access Denied",
            systemImage: "bell.slash.fill",
            description: Text("Enable Reminders access in\nSettings › Privacy & Security › Reminders.")
        )
    }

    private var emptyListsView: some View {
        ContentUnavailableView(
            "No Reminder Lists",
            systemImage: "checklist",
            description: Text("Create a list in the Reminders app first, then come back.")
        )
        .task { await remindersManager.fetchLists() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingAPIKeySheet = true
            } label: {
                Image(systemName: "key.fill")
            }
            .accessibilityLabel("Change API Key")
        }
    }

    // MARK: - Helpers

    private var canStart: Bool {
        !session.selectedListIDs.isEmpty
    }

    private var isAllSelected: Bool {
        !remindersManager.lists.isEmpty &&
        session.selectedListIDs.count == remindersManager.lists.count
    }

    private var selectedCount: String {
        let n = session.selectedListIDs.count
        if n == 0 { return "" }
        if isAllSelected { return "All Reminders" }
        return n == 1 ? "1 List" : "\(n) Lists"
    }

    private func toggleAll() {
        if isAllSelected {
            session.selectedListIDs.removeAll()
        } else {
            session.selectedListIDs = Set(remindersManager.lists.map(\.calendarIdentifier))
        }
    }

    private func toggleList(_ list: EKCalendar) {
        let id = list.calendarIdentifier
        if session.selectedListIDs.contains(id) {
            session.selectedListIDs.remove(id)
        } else {
            session.selectedListIDs.insert(id)
        }
    }

    private func startFiltering() {
        errorMessage = nil
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let items = try await remindersManager.fetchIncompleteReminders(
                    from: session.selectedListIDs
                )
                guard !items.isEmpty else {
                    errorMessage = "No incomplete reminders found in the selected lists."
                    return
                }
                session.allItems = items
                if let stored = RankingStore.load(forLists: session.selectedListIDs) {
                    pendingStoredOrder = stored
                    showResumeAlert = true
                } else {
                    session.phase = .filtering
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - List Row

private struct ListRow: View {
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

// MARK: - API Key Sheet

private struct APIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newKey = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-api03-...", text: $newKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Enter a new key to replace the one currently stored.")
                }
            }
            .navigationTitle("Update API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            KeychainService.save(apiKey: trimmed)
                        }
                        dismiss()
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
