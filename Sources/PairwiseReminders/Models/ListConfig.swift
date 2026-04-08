import Foundation
import SwiftData

/// Persists per-list write-back configuration. One record per EKCalendar, auto-created on first sync.
@Model final class ListConfig {

    /// EKCalendar.calendarIdentifier.
    var calendarIdentifier: String

    // MARK: - Write-Back: Flags

    /// Set the flag on the top N ranked items. 0 = disabled.
    var flagTopN: Int

    // MARK: - Write-Back: Priority

    /// How to map ranks to the Reminders priority field.
    /// "tiered": top 25% → High, next 25% → Medium, next 25% → Low, rest → None.
    /// "topN": items 1…priorityTopN → High, rest → None.
    /// "none": don't touch priority.
    var priorityMode: String

    /// Number of top items to mark High when priorityMode == "topN". Ignored otherwise.
    var priorityTopN: Int

    // MARK: - Write-Back: Due Dates

    /// Set due dates on the top N ranked items. 0 = disabled.
    var dueDateTopN: Int

    /// Target date offset for the due-date write-back.
    /// "today" | "tomorrow" | "nextWeek"
    var dueDateTarget: String

    // MARK: - Write-Back: Trigger

    /// If true, write-back fires automatically whenever the ranking changes.
    /// If false, the user must tap "Write Back" manually.
    var autoWriteBack: Bool

    init(
        calendarIdentifier: String,
        flagTopN: Int = 0,
        priorityMode: String = "none",
        priorityTopN: Int = 3,
        dueDateTopN: Int = 0,
        dueDateTarget: String = "today",
        autoWriteBack: Bool = false
    ) {
        self.calendarIdentifier = calendarIdentifier
        self.flagTopN = flagTopN
        self.priorityMode = priorityMode
        self.priorityTopN = priorityTopN
        self.dueDateTopN = dueDateTopN
        self.dueDateTarget = dueDateTarget
        self.autoWriteBack = autoWriteBack
    }
}
