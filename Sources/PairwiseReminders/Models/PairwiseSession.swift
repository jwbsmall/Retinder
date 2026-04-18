import Foundation
import EventKit
import SwiftData

/// Session-level state for a single pairwise ranking run on one or more lists.
///
/// Lifecycle:
///   idle → seeding → (comparing →)? done
///
/// For `.aiOnly` mode the comparing phase is skipped entirely.
@MainActor
final class PairwiseSession: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case seeding
        case comparing
        case done
    }

    @Published private(set) var phase: Phase = .idle

    // MARK: - Session Data

    /// List identifiers included in the active session.
    @Published private(set) var selectedListIDs: Set<String> = []

    /// All items fetched for the active session (across all selected lists).
    @Published private(set) var sessionItems: [ReminderItem] = []

    /// Set from outside (e.g. ListDetailView) to pre-select lists in ListPickerView
    /// and switch the tab bar to the Prioritise tab.
    @Published var pendingListIDs: Set<String> = []

    /// Items sorted by Elo after the session finishes (index 0 = highest priority).
    @Published private(set) var rankedItems: [ReminderItem] = []

    // MARK: - Refinement State

    /// When non-nil, a pairwise refinement is in progress over a subset.
    /// Holds the full list so `finish()` can splice the refined order back in.
    private var parentRankedItems: [ReminderItem]?
    /// Original indices (into `parentRankedItems`) of the items being refined.
    private var refinementSlots: [Int] = []

    // MARK: - Seeding Status

    /// True when no AI backend was available or seeding failed — Elo ratings start at default 1000.
    @Published private(set) var seedingFailed: Bool = false
    @Published var seedingError: String?

    // MARK: - Mode

    /// Session mode. Persisted via UserDefaults.
    enum Mode: String, CaseIterable {
        case aiOnly   = "ai_only"
        case pairwise = "pairwise"
        case both     = "both"

        var displayName: String {
            switch self {
            case .aiOnly:   return "AI Only"
            case .pairwise: return "Pairwise"
            case .both:     return "Both"
            }
        }
    }

    var mode: Mode {
        get {
            Mode(rawValue: UserDefaults.standard.string(forKey: "session_mode") ?? "") ?? .both
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "session_mode")
        }
    }

    /// Optional criteria text passed to AI seeding (e.g. "work tasks, deadlines this week").
    var aiCriteria: String {
        get { UserDefaults.standard.string(forKey: "ai_criteria") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ai_criteria") }
    }

    /// Limit items to the top N. For AI modes, filtered by seed rank. For pairwise-only,
    /// filtered by existing Elo (highest Elo = most prior evidence of importance).
    /// Nil = no limit.
    var topN: Int? {
        get {
            let v = UserDefaults.standard.integer(forKey: "ai_top_n")
            return v > 0 ? v : nil
        }
        set {
            if let v = newValue, v > 0 {
                UserDefaults.standard.set(v, forKey: "ai_top_n")
            } else {
                UserDefaults.standard.removeObject(forKey: "ai_top_n")
            }
        }
    }

    // MARK: - Due-date Defaults

    var defaultHighDueTarget: DueTarget {
        get { DueTarget(rawValue: UserDefaults.standard.string(forKey: "due_default_high") ?? "") ?? .today }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "due_default_high") }
    }

    var defaultMediumDueTarget: DueTarget {
        get { DueTarget(rawValue: UserDefaults.standard.string(forKey: "due_default_medium") ?? "") ?? .tomorrow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "due_default_medium") }
    }

    var defaultLowDueTarget: DueTarget {
        get { DueTarget(rawValue: UserDefaults.standard.string(forKey: "due_default_low") ?? "") ?? .nextWeek }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "due_default_low") }
    }

    // MARK: - Starting a Session

    /// Begins a session for the given lists. Fetches items, runs AI seeding (unless pairwise-only),
    /// then transitions to `.comparing` or `.done` depending on the mode.
    func start(
        listIDs: Set<String>,
        remindersManager: RemindersManager,
        eloEngine: EloEngine,
        context: ModelContext
    ) async {
        selectedListIDs = listIDs
        sessionItems = []
        rankedItems = []
        seedingFailed = false
        seedingError = nil
        eloEngine.reset()
        phase = .seeding

        // 1. Fetch items with Elo ratings loaded from SwiftData.
        do {
            sessionItems = try await remindersManager.fetchIncompleteReminders(
                from: listIDs, context: context
            )
        } catch {
            phase = .idle
            return
        }

        guard !sessionItems.isEmpty else {
            phase = .idle
            return
        }

        await continueStart(eloEngine: eloEngine, context: context)
    }

    /// Begins a session for a specific pre-loaded set of items (individual selection path).
    /// Skips the fetch step — items are already in memory.
    func start(
        items: [ReminderItem],
        eloEngine: EloEngine,
        context: ModelContext
    ) async {
        selectedListIDs = Set(items.compactMap { $0.ekReminder.calendar?.calendarIdentifier })
        sessionItems = items
        rankedItems = []
        seedingFailed = false
        seedingError = nil
        eloEngine.reset()
        phase = .seeding

        guard !sessionItems.isEmpty else {
            phase = .idle
            return
        }

        await continueStart(eloEngine: eloEngine, context: context)
    }

    /// Starts a pairwise refinement over a selected subset of already-ranked items.
    /// Saves the full ranked list so `finish()` can splice refined positions back in.
    func startRefinement(items: [ReminderItem], eloEngine: EloEngine) {
        guard items.count >= 2 else { return }
        let selectedIDs = Set(items.map(\.id))
        parentRankedItems = rankedItems
        refinementSlots = rankedItems.enumerated().compactMap {
            selectedIDs.contains($0.element.id) ? $0.offset : nil
        }
        selectedListIDs = Set(items.compactMap { $0.ekReminder.calendar?.calendarIdentifier })
        sessionItems = items
        eloEngine.reset()
        eloEngine.start(with: items)
        phase = .comparing
    }

    /// Called by PairwiseView when the user taps "Done for now" or the engine converges.
    func finish(eloEngine: EloEngine, context: ModelContext) {
        let refined = eloEngine.finish(context: context)
        if var parent = parentRankedItems, !refinementSlots.isEmpty {
            // Splice the refined ordering back into the original positions.
            for (slotIndex, slot) in refinementSlots.enumerated() where slotIndex < refined.count {
                parent[slot] = refined[slotIndex]
            }
            rankedItems = parent
            parentRankedItems = nil
            refinementSlots = []
        } else {
            rankedItems = refined
        }
        phase = .done
    }

    /// Reorders `rankedItems` in response to a user drag, updating persistent Elo ratings.
    func reorderRankedItems(from source: IndexSet, to destination: Int, context: ModelContext) {
        rankedItems.move(fromOffsets: source, toOffset: destination)

        let allRecords = (try? context.fetch(FetchDescriptor<RankedItemRecord>())) ?? []
        let recordsByID = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.calendarItemIdentifier, $0) })

        let spread = 20.0
        let top = (rankedItems.first?.eloRating ?? 1000.0) + spread * Double(rankedItems.count)
        for (i, item) in rankedItems.enumerated() {
            let newRating = top - spread * Double(i)
            rankedItems[i].eloRating = newRating
            recordsByID[item.id]?.eloRating = newRating
        }
        try? context.save()
    }

    /// Resets all session state back to idle.
    func reset(eloEngine: EloEngine) {
        eloEngine.reset()
        phase = .idle
        selectedListIDs = []
        sessionItems = []
        rankedItems = []
        seedingFailed = false
        seedingError = nil
        parentRankedItems = nil
        refinementSlots = []
    }

    // MARK: - Private

    private func continueStart(eloEngine: EloEngine, context: ModelContext) async {
        // For pairwise-only: apply top-N by prior Elo before starting.
        if mode == .pairwise, let n = topN, n > 0, sessionItems.count > n {
            sessionItems = Array(
                sessionItems
                    .sorted { $0.eloRating != $1.eloRating ? $0.eloRating > $1.eloRating : $0.title < $1.title }
                    .prefix(n)
            )
        }

        // Run AI seeding unless this is pairwise-only.
        if mode != .pairwise {
            await runSeeding(context: context)
        }

        guard !Task.isCancelled else {
            phase = .idle
            return
        }

        switch mode {
        case .aiOnly:
            // Skip pairwise — rank directly by seeded Elo.
            rankedItems = sessionItems.sorted { $0.eloRating > $1.eloRating }
            phase = .done
        case .pairwise, .both:
            eloEngine.start(with: sessionItems)
            phase = .comparing
        }
    }

    private func runSeeding(context: ModelContext) async {
        let summaries = sessionItems.map { item in
            AnthropicService.ReminderSummary(
                id: item.id,
                title: item.title,
                notes: item.notes,
                dueDateDescription: item.dueDate.map { formatDate($0) }
            )
        }

        let criteria = aiCriteria.isEmpty ? nil : aiCriteria
        let seeds = await tryAPISeeding(summaries: summaries, criteria: criteria)

        guard let seeds, !seeds.isEmpty else {
            seedingFailed = true
            return
        }

        applySeedRatings(seeds, context: context)

        // Truncate to top N if configured — only keep the highest-ranked items.
        if let n = topN, n > 0, sessionItems.count > n {
            let topIDs = Set(seeds.sorted { $0.rank < $1.rank }.prefix(n).map(\.id))
            sessionItems = sessionItems.filter { topIDs.contains($0.id) }
        }
    }

    private func tryAPISeeding(
        summaries: [AnthropicService.ReminderSummary],
        criteria: String?
    ) async -> [AnthropicService.SeededRank]? {
        guard let apiKey = KeychainService.load(), !apiKey.isEmpty else { return nil }
        do {
            return try await AnthropicService(apiKey: apiKey).seedRanking(summaries, criteria: criteria)
        } catch {
            seedingError = "API: \(error.localizedDescription)"
            return nil
        }
    }

    /// Maps AI seed ranks and confidence scores into initial Elo ratings and K-factors,
    /// updates `sessionItems` in place, and persists the new values to SwiftData.
    private func applySeedRatings(_ seeds: [AnthropicService.SeededRank], context: ModelContext) {
        let total = seeds.count
        let seedByID = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, $0) })

        let idsSet = Set(sessionItems.map(\.id))
        let existing = ((try? context.fetch(FetchDescriptor<RankedItemRecord>())) ?? [])
            .filter { idsSet.contains($0.calendarItemIdentifier) }
        let recordByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.calendarItemIdentifier, $0) })

        for i in sessionItems.indices {
            let item = sessionItems[i]
            guard let seed = seedByID[item.id] else { continue }

            // Rank 1 → highest Elo. Spread items by 20 Elo points per rank step.
            let elo = 1000.0 + Double(total - seed.rank) * 20.0
            // Lower confidence → higher K → easier for user to move this item.
            let k = max(8.0, 32.0 * (1.0 - Double(seed.confidence) / 100.0))

            sessionItems[i].eloRating   = elo
            sessionItems[i].kFactor     = k
            sessionItems[i].aiSeedRank  = seed.rank
            sessionItems[i].aiConfidence = seed.confidence
            sessionItems[i].aiReasoning = seed.reasoning

            if let record = recordByID[item.id] {
                record.eloRating   = elo
                record.kFactor     = k
                record.aiSeedRank  = seed.rank
                record.aiConfidence = seed.confidence
                record.aiReasoning  = seed.reasoning
            }
        }
        try? context.save()
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }
}
