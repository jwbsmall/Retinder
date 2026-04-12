import Foundation

/// Calls the Anthropic Messages API via raw URLSession.
/// Provides two modes:
/// - `seedRanking`: ranks all items and returns confidence scores to seed Elo ratings.
/// - `filterReminders`: legacy shortlist for use as a fallback.
struct AnthropicService {

    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Shared Types

    /// Sendable snapshot of a reminder — only the fields needed for AI.
    struct ReminderSummary: Sendable {
        let id: String
        let title: String
        let notes: String?
        let dueDateDescription: String?

        init(id: String, title: String, notes: String? = nil, dueDateDescription: String? = nil) {
            self.id = id
            self.title = title
            self.notes = notes
            self.dueDateDescription = dueDateDescription
        }
    }

    // MARK: - AI Seeding

    /// Rank result from the seeding call. `rank` is 1-based (1 = highest priority).
    /// `confidence` is 0–100 (100 = Claude is certain of this item's position).
    struct SeededRank: Sendable {
        let id: String
        let rank: Int
        let confidence: Int
    }

    /// Sends reminder summaries to Claude and returns a full ranked ordering with
    /// per-item confidence scores. Used to seed initial Elo ratings before pairwise
    /// comparisons begin.
    ///
    /// The caller maps rank → Elo via: `1000 + (totalCount - rank) * 20`
    /// and sets kFactor via: `32 * (1 - confidence / 100)` (low confidence → high K).
    func seedRanking(_ summaries: [ReminderSummary], criteria: String? = nil) async throws -> [SeededRank] {
        guard !summaries.isEmpty else { return [] }

        let criteriaClause = criteria.map { c in
            " When ranking, specifically prioritise: \(c)."
        } ?? ""
        let systemPrompt = """
        You are a productivity assistant. Given a list of tasks/reminders, rank them from most \
        to least important, considering urgency, impact, and time-sensitivity.\(criteriaClause) \
        For each item, provide a confidence score 0–100 reflecting how certain you are of its \
        position (100 = definitely right, 0 = could plausibly go anywhere in the list). \
        Return ALL items — do not filter any out.
        """

        let numberedList = summaries.enumerated().map { i, s in
            var line = "\(i + 1). [ID: \(s.id)] \(s.title)"
            if let notes = s.notes, !notes.isEmpty {
                line += " — \(notes)"
            }
            if let due = s.dueDateDescription {
                line += " (due: \(due))"
            }
            return line
        }.joined(separator: "\n")

        let userMessage = "Here are my tasks:\n\n\(numberedList)\n\nRank them and provide confidence scores."

        let tool: [String: Any] = [
            "name": "seed_ranking",
            "description": "Return ALL items ranked from most to least important, with confidence scores.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "id":         ["type": "string", "description": "The item ID exactly as provided"],
                                "rank":       ["type": "integer", "description": "1-based rank (1 = highest priority)"],
                                "confidence": ["type": "integer", "description": "0–100 confidence in this rank"]
                            ],
                            "required": ["id", "rank", "confidence"]
                        ]
                    ]
                ],
                "required": ["items"]
            ]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": "seed_ranking"],
            "messages": [["role": "user", "content": userMessage]]
        ]

        let responseData = try await performRequest(body: requestBody)
        return try parseSeedResponse(responseData)
    }

    // MARK: - Legacy Filtering (fallback)

    /// Sendable result from AI filtering — an ID and optional reasoning string.
    struct FilteredResult: Sendable {
        let id: String
        let reasoning: String?
    }

    /// Sends reminder summaries to Claude and returns the shortlisted IDs with reasoning.
    /// Used as a fallback when seeding is not needed or as a pre-filter for large lists.
    func filterReminders(_ summaries: [ReminderSummary]) async throws -> [FilteredResult] {
        guard !summaries.isEmpty else { return [] }

        let systemPrompt = """
        You are a productivity assistant. Given a list of reminders/tasks, identify the ~15 most \
        important, time-sensitive, or decision-worthy items. Filter out obvious recurring admin tasks, \
        low-stakes errands, and anything that can clearly wait.
        """

        let numberedList = summaries.enumerated().map { i, s in
            "\(i + 1). [ID: \(s.id)] \(s.title)"
        }.joined(separator: "\n")

        let userMessage = "Here are my reminders:\n\n\(numberedList)\n\nIdentify the most important ones."

        let tool: [String: Any] = [
            "name": "shortlist_reminders",
            "description": "Return the shortlisted reminder IDs with one-line reasoning for each.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "id":        ["type": "string"],
                                "title":     ["type": "string"],
                                "reasoning": ["type": "string"]
                            ],
                            "required": ["id", "title", "reasoning"]
                        ]
                    ]
                ],
                "required": ["items"]
            ]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": "shortlist_reminders"],
            "messages": [["role": "user", "content": userMessage]]
        ]

        let responseData = try await performRequest(body: requestBody)
        return try parseFilterResponse(responseData)
    }

    // MARK: - Connection Test

    /// Sends a minimal request to verify the API key and network reachability.
    /// Throws `AnthropicError.apiError` on a bad key, or a URLError on network failure.
    func testConnection() async throws {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        _ = try await performRequest(body: body)
    }

    // MARK: - Private Helpers

    private func performRequest(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message: String
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorBody["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                message = msg
            } else {
                message = String(data: data, encoding: .utf8) ?? "no body"
            }
            throw AnthropicError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
        return data
    }

    private func parseSeedResponse(_ data: Data) throws -> [SeededRank] {
        guard
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentBlocks = envelope["content"] as? [[String: Any]],
            let toolBlock = contentBlocks.first(where: { $0["type"] as? String == "tool_use" }),
            let input = toolBlock["input"] as? [String: Any],
            let items = input["items"] as? [[String: Any]]
        else {
            throw AnthropicError.parseError("Unexpected seed_ranking response structure.")
        }

        return items.compactMap { entry -> SeededRank? in
            guard
                let id = entry["id"] as? String,
                let rank = entry["rank"] as? Int,
                let confidence = entry["confidence"] as? Int
            else { return nil }
            return SeededRank(id: id, rank: rank, confidence: max(0, min(100, confidence)))
        }
    }

    private func parseFilterResponse(_ data: Data) throws -> [FilteredResult] {
        guard
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentBlocks = envelope["content"] as? [[String: Any]],
            let toolBlock = contentBlocks.first(where: { $0["type"] as? String == "tool_use" }),
            let input = toolBlock["input"] as? [String: Any],
            let shortlist = input["items"] as? [[String: Any]]
        else {
            throw AnthropicError.parseError("Unexpected Tool Use response structure.")
        }

        return shortlist.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            return FilteredResult(id: id, reasoning: entry["reasoning"] as? String)
        }
    }

    // MARK: - Errors

    enum AnthropicError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Received an invalid response from the Anthropic API."
            case .apiError(let code, let message):
                switch code {
                case 401: return "Invalid API key — \(message)"
                case 403: return "API key lacks permission — \(message)"
                case 429: return "Rate limit or no credits remaining — \(message)"
                case 500, 529: return "Anthropic API server error — try again shortly"
                default:  return "API error \(code): \(message)"
                }
            case .parseError(let msg):
                return "Failed to parse Claude's response: \(msg)"
            }
        }
    }
}
