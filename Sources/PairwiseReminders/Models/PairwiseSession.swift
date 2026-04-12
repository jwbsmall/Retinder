import Foundation
import EventKit
import SwiftData

/// Session-level state for a single pairwise ranking run on one or more lists.
///
/// Lifecycle:
///   idle → seeding → comparing → done
///
/// `PrioritiseTab` observes this object to navigate between
/// FilteringView → PairwiseView → ResultsView (session summary).
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

    // MARK: - Seeding Status

    /// True when no AI backend was available or seeding failed — Elo ratings start at default 1000.
    @Published private(set) var seedingFailed: Bool = false
    @Published var seedingError: String?

    // MARK: - AI Preference

    // MARK: - Ranking Mode

    /// The axis by which the user compares pairs. Changes only the comparison question text.
    /// Persisted via UserDefaults so the last-used mode is remembered across sessions.
    enum RankingMode: String, CaseIterable {
        case overall    = "overall"
        case urgency    = "urgency"
        case importance = "importance"

        var displayName: String {
            switch self {
            case .overall:    return "Overall"
            case .urgency:    return "Urgency"
            case .importance: return "Importance"
            }
        }

        /// The question shown at the top of PairwiseView during each comparison.
        var comparisonQuestion: String {
            switch self {
            case .overall:    return "Which matters more?"
            case .urgency:    return "Which is more urgent?"
            case .importance: return "Which is more important?"
            }
        }
    }

    var rankingMode: RankingMode {
        get {
            RankingMode(rawValue: UserDefaults.standard.string(forKey: "ranking_mode") ?? "") ?? .overall
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ranking_mode")
        }
    }

    // MARK: - AI Preference

    /// Which AI backend to prefer for seeding. Persisted via UserDefaults.
    enum AIPreference: String, CaseIterable {
        case onDeviceFirst = "on_device_first"
        case apiFirst = "api_first"
        case none = "none"

        var displayName: String {
            switch self {
            case .onDeviceFirst: return "On-device first"
            case .apiFirst: return "Anthropic API first"
            case .none: return "No AI seeding"
            }
        }
    }

    var aiPreference: AIPreference {
        get {
            AIPreference(rawValue: UserDefaults.standard.string(forKey: "ai_preference") ?? "") ?? .onDeviceFirst
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ai_preference")
        }
    }

    /// Optional criteria text passed to AI seeding (e.g. "work tasks, deadlines this week").
    var aiCriteria: String {
        get { UserDefaults.standard.string(forKey: "ai_criteria") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ai_criteria") }
    }

    /// Limit comparisons to the top N AI-ranked items. Nil = no limit (all items).
    var aiTopN: Int? {
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

    // MARK: - Starting a Session

    /// Begins a session for the given lists. Fetches items, runs AI seeding, then
    /// transitions to `.comparing`.
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

        // 2. Attempt AI seeding to set initial Elo ratings.
        await runSeeding(context: context)

        // Guard: if the task was cancelled (e.g. user dismissed) while seeding, bail out cleanly.
        guard !Task.isCancelled else {
            phase = .idle
            return
        }

        // 3. Start the Elo engine with (possibly seeded) items.
        eloEngine.start(with: sessionItems)
        phase = .comparing
    }

    /// Called by PairwiseView when the user taps "Done for now" or the engine converges.
    func finish(eloEngine: EloEngine, context: ModelContext) {
        rankedItems = eloEngine.finish(context: context)
        phase = .done
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
    }

    // MARK: - Private Seeding

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
        var seeds: [AnthropicService.SeededRank]?

        switch aiPreference {
        case .onDeviceFirst:
            seeds = await tryOnDeviceSeeding(summaries: summaries, criteria: criteria)
            if seeds == nil { seeds = await tryAPISeeding(summaries: summaries, criteria: criteria) }
        case .apiFirst:
            seeds = await tryAPISeeding(summaries: summaries, criteria: criteria)
            if seeds == nil { seeds = await tryOnDeviceSeeding(summaries: summaries, criteria: criteria) }
        case .none:
            break
        }

        guard let seeds, !seeds.isEmpty else {
            seedingFailed = true
            return
        }

        applySeedRatings(seeds, context: context)

        // Truncate to top N if configured — only keep the highest-ranked items.
        if let n = aiTopN, n > 0, sessionItems.count > n {
            let topIDs = Set(seeds.sorted { $0.rank < $1.rank }.prefix(n).map(\.id))
            sessionItems = sessionItems.filter { topIDs.contains($0.id) }
        }
    }

    private func tryOnDeviceSeeding(
        summaries: [AnthropicService.ReminderSummary],
        criteria: String?
    ) async -> [AnthropicService.SeededRank]? {
        guard FoundationModelService.isAvailable else { return nil }
        return try? await FoundationModelService().seedRanking(summaries, criteria: criteria)
    }

    private func tryAPISeeding(
        summaries: [AnthropicService.ReminderSummary],
        criteria: String?
    ) async -> [AnthropicService.SeededRank]? {
        guard let apiKey = KeychainService.load(), !apiKey.isEmpty else { return nil }
        return try? await AnthropicService(apiKey: apiKey).seedRanking(summaries, criteria: criteria)
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

            sessionItems[i].eloRating = elo
            sessionItems[i].kFactor = k

            if let record = recordByID[item.id] {
                record.eloRating = elo
                record.kFactor = k
                record.aiSeedRank = seed.rank
                record.aiConfidence = seed.confidence
            }
        }
        try? context.save()
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }
}
