import Foundation

/// Central state for a single prioritisation session.
/// All mutations happen on the MainActor to keep UI updates safe.
@MainActor
final class PairwiseSession: ObservableObject {

    enum Phase {
        case listPicking
        case filtering
        case comparing
        case results
    }

    @Published var phase: Phase = .listPicking

    /// Reminder list identifiers the user chose to prioritise.
    @Published var selectedListIDs: Set<String> = []

    /// All incomplete reminders fetched from selected lists.
    @Published var allItems: [ReminderItem] = []

    /// AI shortlist (~15 most decision-worthy items).
    @Published var filteredItems: [ReminderItem] = []

    /// Final ranked list after pairwise comparisons, index 0 = highest priority.
    @Published var rankedItems: [ReminderItem] = []

    /// Non-nil when the filtering step failed.
    @Published var filteringError: String?

    /// True when the AI filtering API call failed and we fell back to all items.
    @Published var aiFilteringFailed = false

    /// Non-nil when writing priorities back to Reminders failed.
    @Published var applyError: String?

    /// True once priorities have been successfully written back.
    @Published var didApply = false

    func reset() {
        phase = .listPicking
        selectedListIDs = []
        allItems = []
        filteredItems = []
        rankedItems = []
        filteringError = nil
        applyError = nil
        didApply = false
        aiFilteringFailed = false
    }
}
