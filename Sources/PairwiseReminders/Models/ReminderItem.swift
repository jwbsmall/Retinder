import Foundation
import EventKit

/// Wraps an EKReminder with metadata added during the prioritisation session.
struct ReminderItem: Identifiable, Equatable {
    let id: String              // EKReminder.calendarItemIdentifier
    let ekReminder: EKReminder  // Reference type — mutations are visible everywhere

    // Computed from ekReminder so edits are reflected without reconstructing the struct.
    var title: String    { ekReminder.title ?? "Untitled" }
    var notes: String?   { ekReminder.notes }
    var dueDate: Date?   { ekReminder.dueDateComponents?.date }
    var listName: String { ekReminder.calendar?.title ?? "Unknown" }

    /// Claude's one-line reasoning for why this item matters.
    var aiReasoning: String?

    /// Position in the final sorted order (0 = highest priority).
    var sortRank: Int?

    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.ekReminder = ekReminder
    }

    static func == (lhs: ReminderItem, rhs: ReminderItem) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Priority Mapping

    /// Maps sortRank to Apple Reminders' 4-level priority system.
    /// Top 25% → High (1), next 25% → Medium (5), next 25% → Low (9), rest → None (0).
    func ekPriority(totalCount: Int) -> Int {
        guard let rank = sortRank, totalCount > 0 else { return 0 }
        let quartile = max(totalCount / 4, 1)
        if rank < quartile         { return 1 }  // High
        if rank < quartile * 2     { return 5 }  // Medium
        if rank < quartile * 3     { return 9 }  // Low
        return 0                                  // None
    }

    func priorityLabel(totalCount: Int) -> String {
        switch ekPriority(totalCount: totalCount) {
        case 1: return "High"
        case 5: return "Medium"
        case 9: return "Low"
        default: return "None"
        }
    }

    func priorityColor(totalCount: Int) -> PriorityColor {
        switch ekPriority(totalCount: totalCount) {
        case 1: return .high
        case 5: return .medium
        case 9: return .low
        default: return .none
        }
    }

    enum PriorityColor {
        case high, medium, low, none
    }
}
