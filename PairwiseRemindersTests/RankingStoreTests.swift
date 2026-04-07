import Testing
import Foundation
@testable import PairwiseReminders

@Suite("RankingStore")
struct RankingStoreTests {

    // Unique prefix per test run to avoid cross-test pollution.
    private let listIDs: Set<String> = ["test-cal-A", "test-cal-B"]
    private let expectedKey = "ranking_v1_test-cal-A,test-cal-B"

    @Test("load returns nil when nothing is stored")
    func loadReturnsNilWhenEmpty() {
        UserDefaults.standard.removeObject(forKey: expectedKey)
        #expect(RankingStore.load(forLists: listIDs) == nil)
    }

    @Test("save and load round-trip preserves order")
    func saveLoadRoundTrip() {
        let storedIDs = ["id-1", "id-2", "id-3"]
        // Write directly via UserDefaults to avoid needing real ReminderItem instances.
        UserDefaults.standard.set(storedIDs, forKey: expectedKey)

        let loaded = RankingStore.load(forLists: listIDs)
        #expect(loaded == storedIDs)

        UserDefaults.standard.removeObject(forKey: expectedKey)
    }

    @Test("clear removes stored ranking")
    func clearRemovesData() {
        UserDefaults.standard.set(["id-x"], forKey: expectedKey)
        RankingStore.clear(forLists: listIDs)
        #expect(RankingStore.load(forLists: listIDs) == nil)
    }

    @Test("list ID insertion order does not affect the storage key")
    func keyIsOrderIndependent() {
        let setAB: Set<String> = ["test-cal-A", "test-cal-B"]
        let setBA: Set<String> = ["test-cal-B", "test-cal-A"]

        UserDefaults.standard.set(["id-1"], forKey: expectedKey)
        // Both orderings must resolve to the same key and find the same data.
        #expect(RankingStore.load(forLists: setAB) == ["id-1"])
        #expect(RankingStore.load(forLists: setBA) == ["id-1"])

        UserDefaults.standard.removeObject(forKey: expectedKey)
    }

    @Test("different list ID sets produce different storage keys")
    func differentListsDontCollide() {
        let listsAB: Set<String> = ["test-cal-A", "test-cal-B"]
        let listsAC: Set<String> = ["test-cal-A", "test-cal-C"]
        let keyAB = "ranking_v1_test-cal-A,test-cal-B"
        let keyAC = "ranking_v1_test-cal-A,test-cal-C"

        UserDefaults.standard.set(["id-AB"], forKey: keyAB)
        UserDefaults.standard.set(["id-AC"], forKey: keyAC)

        #expect(RankingStore.load(forLists: listsAB) == ["id-AB"])
        #expect(RankingStore.load(forLists: listsAC) == ["id-AC"])

        UserDefaults.standard.removeObject(forKey: keyAB)
        UserDefaults.standard.removeObject(forKey: keyAC)
    }

    @Test("empty list ID set produces a valid key and round-trips")
    func emptyListSet() {
        let empty: Set<String> = []
        RankingStore.clear(forLists: empty)
        #expect(RankingStore.load(forLists: empty) == nil)

        UserDefaults.standard.set(["solo"], forKey: "ranking_v1_")
        #expect(RankingStore.load(forLists: empty) == ["solo"])
        UserDefaults.standard.removeObject(forKey: "ranking_v1_")
    }
}
