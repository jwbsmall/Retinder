import Testing
import EventKit
@testable import PairwiseReminders

// MARK: - Helpers

/// Creates a ReminderItem with a stable test ID — bypasses EventKit store.
private func makeItem(id: String, title: String = "") -> ReminderItem {
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)
    reminder.title = title.isEmpty ? id : title
    return ReminderItem(id: id, ekReminder: reminder)
}

// MARK: - PairwiseEngine Tests

@Suite("PairwiseEngine")
struct PairwiseEngineTests {

    @Test("Empty input completes immediately with no comparisons")
    @MainActor func emptyInput() async throws {
        let engine = PairwiseEngine()
        engine.start(with: [])
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.isComplete)
        #expect(engine.sortedItems.isEmpty)
        #expect(engine.comparisonNumber == 0)
    }

    @Test("Single item completes immediately with no comparisons")
    @MainActor func singleItem() async throws {
        let engine = PairwiseEngine()
        let item = makeItem(id: "a", title: "Alpha")
        engine.start(with: [item])
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.isComplete)
        #expect(engine.sortedItems.count == 1)
        #expect(engine.comparisonNumber == 0)
    }

    @Test("Two items: choosing left puts left item first")
    @MainActor func twoItemsChooseLeft() async throws {
        let engine = PairwiseEngine()
        let a = makeItem(id: "a", title: "Alpha")
        let b = makeItem(id: "b", title: "Beta")
        engine.start(with: [a, b])

        try await Task.sleep(for: .milliseconds(50))
        guard let pair = engine.currentPair else {
            Issue.record("Expected engine to present a comparison pair")
            return
        }
        engine.choose(winner: pair.0)

        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.isComplete)
        #expect(engine.sortedItems.count == 2)
        #expect(engine.sortedItems.first?.id == pair.0.id)
    }

    @Test("Two items: choosing right puts right item first")
    @MainActor func twoItemsChooseRight() async throws {
        let engine = PairwiseEngine()
        let a = makeItem(id: "a", title: "Alpha")
        let b = makeItem(id: "b", title: "Beta")
        engine.start(with: [a, b])

        try await Task.sleep(for: .milliseconds(50))
        guard let pair = engine.currentPair else {
            Issue.record("Expected engine to present a comparison pair")
            return
        }
        engine.choose(winner: pair.1)

        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.isComplete)
        #expect(engine.sortedItems.first?.id == pair.1.id)
    }

    @Test("Sorted output contains every input item exactly once")
    @MainActor func outputContainsAllItems() async throws {
        let engine = PairwiseEngine()
        let ids = ["a", "b", "c", "d"]
        let items = ids.map { makeItem(id: $0) }
        engine.start(with: items)

        // Drive all comparisons — always pick the left item.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(20))
            guard !engine.isComplete, let pair = engine.currentPair else { break }
            engine.choose(winner: pair.0)
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.isComplete)
        #expect(engine.sortedItems.count == ids.count)
        let resultIDs = Set(engine.sortedItems.map(\.id))
        #expect(resultIDs == Set(ids))
    }

    @Test("start(with:) is idempotent — second call is ignored")
    @MainActor func startIsIdempotent() async throws {
        let engine = PairwiseEngine()
        let a = makeItem(id: "a")
        engine.start(with: [a])
        let firstEstimate = engine.estimatedTotal
        engine.start(with: [makeItem(id: "b"), makeItem(id: "c")])
        #expect(engine.estimatedTotal == firstEstimate)
    }

    @Test("reset() clears all state")
    @MainActor func resetClearsState() async throws {
        let engine = PairwiseEngine()
        engine.start(with: [makeItem(id: "a"), makeItem(id: "b")])
        try await Task.sleep(for: .milliseconds(50))
        engine.reset()
        #expect(!engine.isStarted)
        #expect(!engine.isComplete)
        #expect(engine.sortedItems.isEmpty)
        #expect(engine.currentPair == nil)
        #expect(engine.comparisonNumber == 0)
    }

    @Test("estimatedTotal is 0 for 0 or 1 items, positive for 2+")
    @MainActor func estimatedTotalFormula() async throws {
        let engine = PairwiseEngine()

        engine.start(with: [])
        #expect(engine.estimatedTotal == 0)
        engine.reset()

        engine.start(with: [makeItem(id: "a")])
        #expect(engine.estimatedTotal == 0)
        engine.reset()

        engine.start(with: [makeItem(id: "a"), makeItem(id: "b")])
        #expect(engine.estimatedTotal >= 1)
        engine.reset()

        engine.start(with: [makeItem(id: "a"), makeItem(id: "b"), makeItem(id: "c"), makeItem(id: "d")])
        #expect(engine.estimatedTotal >= 1)
    }
}
