import Foundation

/// Merge-sort-inspired pairwise comparison engine.
///
/// How it works:
/// 1. `start(with:)` kicks off an async merge sort on the MainActor.
/// 2. Each time two items need to be compared, `askUser` suspends the task
///    and publishes `currentPair` for the UI to display.
/// 3. When the user calls `choose(winner:)`, the continuation is resumed
///    with the result, and the sort proceeds to the next comparison.
/// 4. When the sort finishes, `isComplete` becomes true and `sortedItems`
///    holds the fully ranked array (index 0 = most important).
///
/// All published-property mutations happen on the MainActor, keeping
/// SwiftUI updates safe without extra `DispatchQueue.main` calls.
@MainActor
final class PairwiseEngine: ObservableObject {

    // MARK: - Published State

    /// The two items currently being compared. Nil between comparisons.
    @Published private(set) var currentPair: (ReminderItem, ReminderItem)?

    /// How many comparisons have been made so far.
    @Published private(set) var comparisonNumber: Int = 0

    /// Rough upper bound on total comparisons (n * ceil(log₂n) / 2).
    @Published private(set) var estimatedTotal: Int = 0

    /// True once the sort has finished.
    @Published private(set) var isComplete: Bool = false

    /// Fully sorted items, most important first. Valid when `isComplete` is true.
    @Published private(set) var sortedItems: [ReminderItem] = []

    /// True once `start` has been called (prevents double-starting on view re-appear).
    @Published private(set) var isStarted: Bool = false

    // MARK: - Private State

    /// Holds the suspended continuation until the user makes a choice.
    private var pendingContinuation: CheckedContinuation<Bool, Never>?

    // MARK: - Public Interface

    /// Begins the pairwise sort. Call only once per session; call `reset()` to restart.
    func start(with items: [ReminderItem]) {
        guard !isStarted else { return }
        isStarted = true

        let n = items.count
        // Average-case estimate: n * ceil(log₂n) / 2
        estimatedTotal = n <= 1 ? 0 : max(1, Int(Double(n) * ceil(log2(Double(n))) / 2.0))
        comparisonNumber = 0
        isComplete = false
        sortedItems = []
        currentPair = nil

        Task {
            let result = await mergeSort(Array(items))
            self.sortedItems = result
            self.isComplete = true
            self.currentPair = nil
        }
    }

    /// Call when the user picks the more important item from `currentPair`.
    /// `winner` is the item that should rank higher (appear earlier in results).
    func choose(winner: ReminderItem) {
        guard let continuation = pendingContinuation,
              let pair = currentPair else { return }
        pendingContinuation = nil
        currentPair = nil
        // Resume with true if the left item won, false if the right item won
        continuation.resume(returning: winner.id == pair.0.id)
    }

    /// Resets all state so the engine can be reused for a new session.
    func reset() {
        // Resume any pending continuation to avoid leaking it before we discard it
        pendingContinuation?.resume(returning: false)
        pendingContinuation = nil
        currentPair = nil
        isStarted = false
        isComplete = false
        sortedItems = []
        comparisonNumber = 0
        estimatedTotal = 0
    }

    // MARK: - Merge Sort

    private func mergeSort(_ arr: [ReminderItem]) async -> [ReminderItem] {
        guard arr.count > 1 else { return arr }
        let mid = arr.count / 2
        let left  = await mergeSort(Array(arr[..<mid]))
        let right = await mergeSort(Array(arr[mid...]))
        return await merge(left, right)
    }

    private func merge(_ left: [ReminderItem], _ right: [ReminderItem]) async -> [ReminderItem] {
        var result: [ReminderItem] = []
        result.reserveCapacity(left.count + right.count)
        var li = 0
        var ri = 0

        while li < left.count && ri < right.count {
            let leftWon = await askUser(left: left[li], right: right[ri])
            if leftWon {
                result.append(left[li]);  li += 1
            } else {
                result.append(right[ri]); ri += 1
            }
        }

        result.append(contentsOf: left[li...])
        result.append(contentsOf: right[ri...])
        return result
    }

    /// Suspends the sort Task and publishes the pair for the UI.
    /// Returns true if the left item should rank higher.
    private func askUser(left: ReminderItem, right: ReminderItem) async -> Bool {
        comparisonNumber += 1
        currentPair = (left, right)

        return await withCheckedContinuation { continuation in
            // The continuation is stored here on the MainActor.
            // choose(winner:) — also called on the MainActor — will resume it.
            self.pendingContinuation = continuation
        }
    }
}
