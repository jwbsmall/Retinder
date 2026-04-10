import Foundation
import SwiftData

/// Elo-based pairwise ranking engine.
///
/// How it works:
/// 1. `start(with:)` loads Elo ratings from SwiftData (or defaults to 1000) and
///    selects the most uncertain pair (closest ratings) to show first.
/// 2. The UI calls `choose(winner:)`, `equal()`, or `skip()` after the user decides.
/// 3. Each choice updates both items' Elo ratings and K-factors, then selects the
///    next most uncertain pair.
/// 4. The user can call `finish()` at any time — the current ratings are persisted
///    and the sorted list is returned. Partial ranking is always valid.
/// 5. `isConverged` becomes true when no pair has a rating gap < 50 (all orderings
///    are reasonably settled).
///
/// All published-property mutations happen on the MainActor for SwiftUI safety.
@MainActor
final class EloEngine: ObservableObject {

    // MARK: - Published State

    /// The two items currently being compared. Nil between comparisons or before start.
    @Published private(set) var currentPair: (ReminderItem, ReminderItem)?

    /// How many comparisons have been made this session.
    @Published private(set) var comparisonCount: Int = 0

    /// Estimate of how many more comparisons would meaningfully change the ranking.
    /// Derived from how many pairs still have close ratings.
    @Published private(set) var estimatedRemaining: Int = 0

    /// True when all pairs have a rating gap ≥ 50 — further comparisons yield diminishing returns.
    @Published private(set) var isConverged: Bool = false

    /// True once `start` has been called.
    @Published private(set) var isStarted: Bool = false

    // MARK: - Private State

    private var items: [ReminderItem] = []
    /// Prevents showing the exact same pair twice in a row.
    private var lastPairKey: String?

    // MARK: - Public Interface

    /// Initialises the engine with items, loading their Elo ratings from SwiftData.
    /// Safe to call again after `reset()`.
    func start(with items: [ReminderItem]) {
        guard !isStarted else { return }
        isStarted = true
        comparisonCount = 0
        self.items = items
        updateConvergenceAndAdvance()
    }

    /// The user picked `winner` as higher priority. Updates both items' ratings and
    /// advances to the next comparison.
    func choose(winner: ReminderItem) {
        guard let pair = currentPair else { return }
        let loser = winner.id == pair.0.id ? pair.1 : pair.0
        applyEloUpdate(winner: winner.id, loser: loser.id, outcome: 1.0)
        comparisonCount += 1
        updateConvergenceAndAdvance()
    }

    /// The user considers the two items roughly equal. Applies a small symmetric update.
    func equal() {
        guard let pair = currentPair else { return }
        applyEloUpdate(winner: pair.0.id, loser: pair.1.id, outcome: 0.5)
        // Force a small spread if ratings are still too close — prevents zero-delta re-selection.
        if let wi = items.firstIndex(where: { $0.id == pair.0.id }),
           let li = items.firstIndex(where: { $0.id == pair.1.id }),
           abs(items[wi].eloRating - items[li].eloRating) < 50.0 {
            items[wi].eloRating += 25.0
            items[li].eloRating -= 25.0
        }
        comparisonCount += 1
        updateConvergenceAndAdvance()
    }

    /// The user skips without expressing a preference. No rating change; moves on.
    func skip() {
        guard currentPair != nil else { return }
        comparisonCount += 1
        updateConvergenceAndAdvance()
    }

    /// Persists all current Elo ratings to SwiftData and returns items sorted by
    /// rating descending (highest priority first). Call when the user taps "Done for now".
    func finish(context: ModelContext) -> [ReminderItem] {
        persist(context: context)
        return items.sorted { $0.eloRating > $1.eloRating }
    }

    /// Resets all engine state so it can be reused.
    func reset() {
        items = []
        currentPair = nil
        comparisonCount = 0
        estimatedRemaining = 0
        isConverged = false
        isStarted = false
        lastPairKey = nil
    }

    // MARK: - Elo Maths

    /// Applies a standard Elo update.
    /// `outcome` is from the first-listed player's perspective: 1.0 = win, 0.5 = draw.
    private func applyEloUpdate(winner winnerID: String, loser loserID: String, outcome: Double) {
        guard
            let wi = items.firstIndex(where: { $0.id == winnerID }),
            let li = items.firstIndex(where: { $0.id == loserID })
        else { return }

        let rA = items[wi].eloRating
        let rB = items[li].eloRating
        let expected = 1.0 / (1.0 + pow(10.0, (rB - rA) / 400.0))

        let kA = items[wi].kFactor
        let kB = items[li].kFactor

        items[wi].eloRating += kA * (outcome - expected)
        items[li].eloRating -= kB * (outcome - expected)

        // Decay K-factor toward a floor of 8.
        items[wi].kFactor = max(8.0, kA * 0.95)
        items[li].kFactor = max(8.0, kB * 0.95)
    }

    // MARK: - Pair Selection + Convergence (combined to sort once per comparison)

    /// Sorts items once, counts uncertain adjacent pairs, and selects the next pair to show.
    /// Skips the most-recently-shown pair if any other uncertain pair exists — prevents
    /// the same two items appearing back-to-back when their gap is still the smallest.
    private func updateConvergenceAndAdvance() {
        currentPair = nil
        guard items.count >= 2 else { isConverged = true; return }

        let sorted = items.sorted { $0.eloRating > $1.eloRating }

        var uncertainCount = 0
        var bestGap = Double.infinity
        var bestPair: (ReminderItem, ReminderItem)?
        var fallbackGap = Double.infinity
        var fallbackPair: (ReminderItem, ReminderItem)?

        for i in 0..<(sorted.count - 1) {
            let gap = sorted[i].eloRating - sorted[i + 1].eloRating
            guard gap < 50.0 else { continue }
            uncertainCount += 1
            let key = pairKey(sorted[i], sorted[i + 1])
            if gap < bestGap {
                // Prefer a pair we haven't just shown.
                if key != lastPairKey {
                    bestGap = gap
                    bestPair = (sorted[i], sorted[i + 1])
                } else if gap < fallbackGap {
                    fallbackGap = gap
                    fallbackPair = (sorted[i], sorted[i + 1])
                }
            }
        }

        estimatedRemaining = uncertainCount

        if let pair = bestPair ?? fallbackPair {
            lastPairKey = pairKey(pair.0, pair.1)
            currentPair = pair
        } else {
            isConverged = true
        }
    }

    private func pairKey(_ a: ReminderItem, _ b: ReminderItem) -> String {
        a.id < b.id ? "\(a.id)|\(b.id)" : "\(b.id)|\(a.id)"
    }

    // MARK: - Persistence

    private func persist(context: ModelContext) {
        let idsSet = Set(items.map(\.id))
        let existing = ((try? context.fetch(FetchDescriptor<RankedItemRecord>())) ?? [])
            .filter { idsSet.contains($0.calendarItemIdentifier) }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.calendarItemIdentifier, $0) })

        let now = Date()
        for item in items {
            if let record = existingByID[item.id] {
                record.eloRating = item.eloRating
                record.kFactor = item.kFactor
                record.comparisonCount += 1
                record.lastComparedAt = now
            }
            // New records are inserted by RemindersManager.syncWithEventKit —
            // we only update here, not insert.
        }
        try? context.save()
    }
}
