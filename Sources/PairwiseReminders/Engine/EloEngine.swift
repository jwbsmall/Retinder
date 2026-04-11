import Foundation
import SwiftData

/// Merge-sort-based pairwise ranking engine.
///
/// How it works:
/// 1. `start(with:)` sorts items by AI-seeded Elo rating and begins an async merge sort.
///    The sort suspends at each comparison, waiting for the user to pick a winner.
/// 2. The UI calls `choose(winner:)`, `equal()`, or `skip()` to resume the sort.
/// 3. When the sort finishes, Elo ratings are assigned from the final rank and
///    `isConverged` becomes true, signalling PairwiseView to transition to results.
/// 4. "Done for now" calls `finish()` at any time — partial Elo deltas accumulated
///    during the session produce a meaningful partial ordering.
/// 5. `undo()` replays the sort up to the prior decision, then suspends at the new frontier.
///
/// Guarantees:
/// - No pair is ever shown twice (each merge step visits a pair exactly once)
/// - Worst-case comparison count: T(n) = T(⌊n/2⌋) + T(⌈n/2⌉) + (n−1), e.g. 5 for n=4
/// - Bail-out at any point produces a meaningful partial ordering via live Elo deltas
@MainActor
final class EloEngine: ObservableObject {

    // MARK: - Published State

    /// The two items currently being compared. Nil between comparisons or before start.
    @Published private(set) var currentPair: (ReminderItem, ReminderItem)?

    /// How many comparisons have been made this session.
    @Published private(set) var comparisonCount: Int = 0

    /// Exact remaining comparisons (worst case). Counts down as decisions are made.
    @Published private(set) var estimatedRemaining: Int = 0

    /// True once the merge sort finishes — triggers session.finish() in PairwiseView.
    @Published private(set) var isConverged: Bool = false

    /// True once `start` has been called.
    @Published private(set) var isStarted: Bool = false

    /// True when at least one comparison has been made and can be undone.
    @Published private(set) var canUndo: Bool = false

    // MARK: - Private State

    private var items: [ReminderItem] = []
    /// Snapshot of items with original Elo ratings at the moment start() is called.
    /// Used to restore clean state on undo before re-applying remaining deltas.
    private var startItems: [ReminderItem] = []
    private var sortTask: Task<Void, Never>?
    private var pendingContinuation: CheckedContinuation<String, Never>?
    private var totalComparisons: Int = 0

    /// Ordered record of every user decision. Each entry stores both IDs so Elo
    /// deltas can be re-applied correctly after an undo resets items to startItems.
    private var decisionHistory: [(pairKey: String, winnerID: String, loserID: String)] = []

    /// UUID identifying all decisions from this session. Generated fresh each `start()`.
    private var sessionID: String = ""

    // MARK: - Public Interface

    /// Starts the merge sort. Items are pre-ordered by their Elo rating (AI seed order)
    /// so the sort's first comparisons are the closest calls — the most interesting ones.
    func start(with items: [ReminderItem]) {
        guard !isStarted else { return }
        comparisonCount = 0
        sessionID = UUID().uuidString
        self.items = items.sorted { $0.eloRating > $1.eloRating }
        startItems = self.items
        totalComparisons = worstCaseComparisons(self.items.count)
        estimatedRemaining = totalComparisons
        launchSort()
    }

    /// The user picked `winner` as higher priority. Resumes the suspended sort
    /// and updates live Elo ratings so bail-out always returns a meaningful order.
    func choose(winner: ReminderItem) {
        guard let pair = currentPair, pendingContinuation != nil else { return }
        let loser = pair.0.id == winner.id ? pair.1 : pair.0

        // Live Elo delta — ensures "Done for now" returns a meaningful partial ordering.
        applyEloDelta(winnerID: winner.id, loserID: loser.id)

        decisionHistory.append((pairKey(pair.0, pair.1), winner.id, loser.id))
        canUndo = true

        pendingContinuation?.resume(returning: winner.id)
        pendingContinuation = nil
        comparisonCount += 1
        estimatedRemaining = max(0, totalComparisons - comparisonCount)
    }

    /// The user considers the two items equal. Breaks the tie using the AI-seeded Elo order.
    func equal() {
        guard let pair = currentPair else { return }
        let tiebreaker = pair.0.eloRating >= pair.1.eloRating ? pair.0 : pair.1
        choose(winner: tiebreaker)
    }

    /// Skips without expressing a preference. Behaves like `equal()`.
    func skip() { equal() }

    /// Undoes the last comparison. Cancels the running sort, restores Elo ratings to the
    /// pre-decision state, and restarts the sort — auto-replaying all remaining history
    /// before suspending at the new comparison frontier.
    func undo() {
        guard !decisionHistory.isEmpty else { return }
        decisionHistory.removeLast()
        comparisonCount = max(0, comparisonCount - 1)
        estimatedRemaining = min(totalComparisons, estimatedRemaining + 1)
        canUndo = !decisionHistory.isEmpty

        cancelSort()

        // Restore original ratings, then replay Elo deltas for decisions still in history.
        items = startItems
        for decision in decisionHistory {
            applyEloDelta(winnerID: decision.winnerID, loserID: decision.loserID)
        }

        isStarted = false
        isConverged = false
        launchSort()
    }

    /// Cancels the sort (if running), persists current ratings, and returns items
    /// sorted by Elo. Safe to call at any point — partial rankings are always valid.
    func finish(context: ModelContext) -> [ReminderItem] {
        cancelSort()
        persist(context: context)
        return items.sorted { $0.eloRating > $1.eloRating }
    }

    /// Resets all state so the engine can be reused for a new session.
    func reset() {
        cancelSort()
        items = []
        startItems = []
        currentPair = nil
        comparisonCount = 0
        estimatedRemaining = 0
        isConverged = false
        isStarted = false
        totalComparisons = 0
        decisionHistory = []
        canUndo = false
        sessionID = ""
    }

    // MARK: - Private Helpers

    /// Extracts sort Task creation so both `start()` and `undo()` can launch it.
    private func launchSort() {
        isStarted = true
        sortTask = Task { [weak self] in
            guard let self else { return }
            let sorted = await self.mergeSort(self.items)
            guard !Task.isCancelled else { return }
            // Assign Elo from final rank so sparklines and cross-session history still work.
            let n = sorted.count
            for (rank, item) in sorted.enumerated() {
                if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[idx].eloRating = 1000.0 + Double(n - 1 - rank) * 20.0
                    self.items[idx].kFactor = 8.0  // Settled; low K means future sessions move it less.
                }
            }
            self.currentPair = nil
            self.estimatedRemaining = 0
            self.isConverged = true
        }
    }

    /// Applies a standard Elo delta (K=32) to winner and loser in `self.items`.
    private func applyEloDelta(winnerID: String, loserID: String) {
        guard let wi = items.firstIndex(where: { $0.id == winnerID }),
              let li = items.firstIndex(where: { $0.id == loserID }) else { return }
        let rW = items[wi].eloRating, rL = items[li].eloRating
        let expected = 1.0 / (1.0 + pow(10.0, (rL - rW) / 400.0))
        let k = 32.0
        items[wi].eloRating += k * (1.0 - expected)
        items[li].eloRating -= k * (1.0 - expected)
    }

    /// Canonical order-independent key for a pair — used to match replay history entries.
    private func pairKey(_ a: ReminderItem, _ b: ReminderItem) -> String {
        [a.id, b.id].sorted().joined(separator: "|")
    }

    private func cancelSort() {
        sortTask?.cancel()
        sortTask = nil
        // Resume any suspended continuation so the Task can exit cleanly.
        if let pair = currentPair {
            let tiebreaker = pair.0.eloRating >= pair.1.eloRating ? pair.0 : pair.1
            pendingContinuation?.resume(returning: tiebreaker.id)
        } else {
            pendingContinuation?.resume(returning: "")
        }
        pendingContinuation = nil
        currentPair = nil
    }

    // MARK: - Merge Sort

    private func mergeSort(_ arr: [ReminderItem]) async -> [ReminderItem] {
        guard !Task.isCancelled, arr.count > 1 else { return arr }
        let mid = arr.count / 2
        let left  = await mergeSort(Array(arr[..<mid]))
        let right = await mergeSort(Array(arr[mid...]))
        return await merge(left, right)
    }

    private func merge(_ left: [ReminderItem], _ right: [ReminderItem]) async -> [ReminderItem] {
        var result: [ReminderItem] = []
        var li = 0, ri = 0
        while li < left.count && ri < right.count {
            guard !Task.isCancelled else { break }
            let winner = await compare(left[li], right[ri])
            if winner.id == left[li].id {
                result.append(left[li]); li += 1
            } else {
                result.append(right[ri]); ri += 1
            }
        }
        result += Array(left[li...])
        result += Array(right[ri...])
        return result
    }

    /// Suspends the sort Task and waits for the user to pick a winner via `choose(winner:)`.
    /// During undo replay, auto-resolves recorded decisions without suspending.
    private func compare(_ a: ReminderItem, _ b: ReminderItem) async -> ReminderItem {
        guard !Task.isCancelled else { return a }
        let key = pairKey(a, b)
        // Auto-replay a prior decision (happens when sort restarts after undo).
        // Does NOT call choose() — avoids double-counting comparisonCount.
        if let recorded = decisionHistory.first(where: { $0.pairKey == key }) {
            return recorded.winnerID == a.id ? a : b
        }
        currentPair = (a, b)
        let winnerID = await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
        return winnerID == a.id ? a : b
    }

    // MARK: - Comparison Count

    /// Worst-case merge-step count: T(1) = 0, T(n) = T(⌊n/2⌋) + T(⌈n/2⌉) + (n − 1).
    private func worstCaseComparisons(_ n: Int) -> Int {
        guard n > 1 else { return 0 }
        let mid = n / 2
        return (n - 1) + worstCaseComparisons(mid) + worstCaseComparisons(n - mid)
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
        }

        // Persist comparison decisions for the history log.
        if !decisionHistory.isEmpty && !sessionID.isEmpty {
            let titleByID = Dictionary(items.map { ($0.id, $0.title) },
                                      uniquingKeysWith: { first, _ in first })
            for (index, decision) in decisionHistory.enumerated() {
                let record = ComparisonRecord(
                    sessionID: sessionID,
                    sessionDate: now,
                    order: index,
                    winnerID: decision.winnerID,
                    winnerTitle: titleByID[decision.winnerID] ?? decision.winnerID,
                    loserID: decision.loserID,
                    loserTitle: titleByID[decision.loserID] ?? decision.loserID
                )
                context.insert(record)
            }
        }

        try? context.save()
    }
}
