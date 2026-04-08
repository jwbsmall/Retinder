import Foundation
import SwiftData

/// Persists Elo ranking metadata for a single reminder across sessions.
/// Keyed to EKReminder.calendarItemIdentifier. Deleted when the reminder is removed from EventKit.
@Model final class RankedItemRecord {

    /// EKReminder.calendarItemIdentifier — stable identifier for the reminder.
    var calendarItemIdentifier: String

    /// EKCalendar.calendarIdentifier of the list this reminder belongs to.
    var listCalendarIdentifier: String

    /// Elo rating. Higher = higher priority. Starts at 1000.
    var eloRating: Double

    /// K-factor controlling how much each comparison shifts the rating.
    /// Starts at 32.0 (highly movable), decays toward 8.0 as more comparisons are made.
    var kFactor: Double

    /// Total number of pairwise comparisons this item has participated in.
    var comparisonCount: Int

    /// Timestamp of the most recent comparison involving this item.
    var lastComparedAt: Date?

    /// AI-suggested rank (1 = highest priority) from the most recent seeding pass.
    /// Nil if no AI seeding has been performed.
    var aiSeedRank: Int?

    /// AI confidence in aiSeedRank, 0–100. Lower → item more likely to benefit from
    /// human comparison. Nil if no AI seeding has been performed.
    var aiConfidence: Int?

    init(
        calendarItemIdentifier: String,
        listCalendarIdentifier: String,
        eloRating: Double = 1000.0,
        kFactor: Double = 32.0,
        comparisonCount: Int = 0,
        lastComparedAt: Date? = nil,
        aiSeedRank: Int? = nil,
        aiConfidence: Int? = nil
    ) {
        self.calendarItemIdentifier = calendarItemIdentifier
        self.listCalendarIdentifier = listCalendarIdentifier
        self.eloRating = eloRating
        self.kFactor = kFactor
        self.comparisonCount = comparisonCount
        self.lastComparedAt = lastComparedAt
        self.aiSeedRank = aiSeedRank
        self.aiConfidence = aiConfidence
    }
}
