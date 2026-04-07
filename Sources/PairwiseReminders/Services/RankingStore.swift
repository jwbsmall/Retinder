import Foundation

/// Persists the ranked order of reminders between sessions using UserDefaults.
///
/// Key: sorted, comma-joined list of EKCalendar identifiers for the chosen lists.
/// Value: ordered array of EKReminder calendarItemIdentifiers (most → least important).
///
/// On next session with the same lists, call `load` to reconstruct the ranking.
/// New reminders (not in the stored list) can be appended at the end.
/// Completed reminders (not returned by EventKit) simply won't appear.
enum RankingStore {

    private static let keyPrefix = "ranking_v1_"

    static func save(rankedItems: [ReminderItem], forLists listIDs: Set<String>) {
        let ids = rankedItems.map { $0.id }
        UserDefaults.standard.set(ids, forKey: key(for: listIDs))
    }

    /// Returns ordered calendarItemIdentifiers, or nil if no ranking is stored.
    static func load(forLists listIDs: Set<String>) -> [String]? {
        UserDefaults.standard.stringArray(forKey: key(for: listIDs))
    }

    static func clear(forLists listIDs: Set<String>) {
        UserDefaults.standard.removeObject(forKey: key(for: listIDs))
    }

    private static func key(for listIDs: Set<String>) -> String {
        keyPrefix + listIDs.sorted().joined(separator: ",")
    }
}
