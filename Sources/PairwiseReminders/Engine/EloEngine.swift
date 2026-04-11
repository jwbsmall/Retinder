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
/// 4. "Done for now" calls `finish()` at any time — the sort is cancelled and items
///    are returned sorted by their current (AI-seeded) Elo ratings.
///
/// Guarantees:
/// - No pair is ever shown twice (each merge step visits a pair exactly once)
/// - Worst-case comparison count: T(n) = T(⌊n/2⌋) + T(⌈n/2⌉) + (n−1), e.g. 5 for n=4
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

    // MARK: - Private State

    private var items: [ReminderItem] = []
    private var sortTask: Task<Void, Never>?
    private var pendingContinuation: CheckedContinuation<String, Never>?
    private var totalComparisons: Int = 0

    // MARK: - Public Interface

    /// Starts the merge sort. Items are pre-ordered by their Elo rating (AI seed order)
    /// so the sort's first comparisons are the closest calls — the most interesting ones.
    func start(with items: [ReminderItem]) {
        guard !isStarted else { return }
        isStarted = true
        comparisonCount = 0
        self.items = items.sorted { $0.eloRating > $1.eloRating }
        totalComparisons = worstCaseComparisons(self.items.count)
        estimatedRemaining = totalComparisons

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

    /// The user picked `winner` as higher priority. Resumes the suspended sort.
    func choose(winner: ReminderItem) {
        guard pendingContinuation != nil else { return }
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
        currentPair = nil
        comparisonCount = 0
        estimatedRemaining = 0
        isConverged = false
        isStarted = false
        totalComparisons = 0
    }

    // MARK: - Cancel Helper

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
    private func compare(_ a: ReminderItem, _ b: ReminderItem) async -> ReminderItem {
        guard !Task.isCancelled else { return a }
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
        try? context.save()
    }
}
