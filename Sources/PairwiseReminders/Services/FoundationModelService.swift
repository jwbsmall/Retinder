import Foundation
import FoundationModels

/// On-device AI ranking using the iOS 26 Foundation Models framework.
/// Produces the same SeededRank output as AnthropicService.seedRanking so the
/// caller can use either interchangeably.
///
/// Usage: call `isAvailable` before using — returns false on devices without a
/// capable on-device model.
struct FoundationModelService {

    /// True when the device supports the Foundation Models framework with a capable model.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - Seeding

    /// Ranks items using the on-device language model and returns confidence-weighted results.
    /// Throws if no capable model is available, times out, or the model fails to produce parseable output.
    func seedRanking(_ summaries: [AnthropicService.ReminderSummary], criteria: String? = nil) async throws -> [AnthropicService.SeededRank] {
        guard !summaries.isEmpty else { return [] }
        guard FoundationModelService.isAvailable else {
            throw FoundationModelError.modelUnavailable
        }

        let modelSession = LanguageModelSession()

        let numberedList = summaries.enumerated().map { i, s in
            var line = "\(i + 1). [ID: \(s.id)] \(s.title)"
            if let notes = s.notes, !notes.isEmpty { line += " — \(notes)" }
            if let due = s.dueDateDescription { line += " (due: \(due))" }
            return line
        }.joined(separator: "\n")

        let criteriaClause = criteria.map { c in
            " When ranking, specifically prioritise: \(c)."
        } ?? ""

        let prompt = """
        You are a productivity assistant. Rank these tasks from most to least important.\(criteriaClause) \
        For each, provide a confidence score 0-100 (100 = certain of position, 0 = could go anywhere). \
        Return ALL items. Respond ONLY with a JSON array, no other text:
        [{"id":"<id>","rank":<1-based>,"confidence":<0-100>}, ...]

        Tasks:
        \(numberedList)
        """

        // Race the model response against a 10-second timeout to avoid hanging the seeding phase.
        return try await withThrowingTaskGroup(of: [AnthropicService.SeededRank].self) { group in
            group.addTask {
                let response = try await modelSession.respond(to: prompt)
                return try self.parseResponse(response.content, summaries: summaries)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw FoundationModelError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Parsing

    private func parseResponse(
        _ text: String,
        summaries: [AnthropicService.ReminderSummary]
    ) throws -> [AnthropicService.SeededRank] {
        // Extract the JSON array from the model's response — it may include surrounding text.
        let jsonString: String
        if let start = text.range(of: "["), let end = text.range(of: "]", options: .backwards) {
            jsonString = String(text[start.lowerBound...end.upperBound])
        } else {
            throw FoundationModelError.parseError("No JSON array found in model response.")
        }

        guard
            let data = jsonString.data(using: .utf8),
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw FoundationModelError.parseError("Could not decode JSON from model response.")
        }

        let knownIDs = Set(summaries.map(\.id))
        return array.compactMap { entry -> AnthropicService.SeededRank? in
            guard
                let id = entry["id"] as? String,
                knownIDs.contains(id),
                let rank = entry["rank"] as? Int,
                let confidence = entry["confidence"] as? Int
            else { return nil }
            return AnthropicService.SeededRank(
                id: id,
                rank: rank,
                confidence: max(0, min(100, confidence))
            )
        }
    }

    // MARK: - Errors

    enum FoundationModelError: LocalizedError {
        case modelUnavailable
        case timeout
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable:
                return "On-device AI model is not available on this device."
            case .timeout:
                return "On-device model timed out."
            case .parseError(let msg):
                return "Failed to parse on-device model response: \(msg)"
            }
        }
    }
}
