import Foundation
import SwiftData

/// Persists a single pairwise comparison decision.
///
/// All decisions from one Prioritise session share the same `sessionID`.
/// Written in batch when the session finishes (converged or "Done for now").
@Model
final class ComparisonRecord {

    /// Groups all decisions from the same session. Generated once per `EloEngine.start()`.
    var sessionID: String

    /// When the session ended — used as the section header in HistoryView.
    var sessionDate: Date

    /// Position of this comparison within the session (0-based). Preserves decision order.
    var order: Int

    // MARK: - Winner

    var winnerID: String
    var winnerTitle: String

    // MARK: - Loser

    var loserID: String
    var loserTitle: String

    init(
        sessionID: String,
        sessionDate: Date,
        order: Int,
        winnerID: String,
        winnerTitle: String,
        loserID: String,
        loserTitle: String
    ) {
        self.sessionID   = sessionID
        self.sessionDate = sessionDate
        self.order       = order
        self.winnerID    = winnerID
        self.winnerTitle = winnerTitle
        self.loserID     = loserID
        self.loserTitle  = loserTitle
    }
}
