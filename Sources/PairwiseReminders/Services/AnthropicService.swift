import Foundation

/// Calls the Anthropic Messages API via raw URLSession to pre-filter reminders.
struct AnthropicService {

    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Public Interface

    /// Sends the full reminder list to Claude and returns a shortlist of the
    /// ~15 most important, time-sensitive, or decision-worthy items.
    func filterReminders(_ items: [ReminderItem]) async throws -> [ReminderItem] {
        guard !items.isEmpty else { return [] }

        let systemPrompt = """
        You are a productivity assistant. Given a list of reminders/tasks, identify the ~15 most \
        important, time-sensitive, or decision-worthy items. Filter out obvious recurring admin tasks, \
        low-stakes errands, and anything that can clearly wait. \
        Return a JSON array of objects: \
        [{"id": "<original_id>", "title": "<title>", "reasoning": "<optional: one short tag ONLY if clear from the title, e.g. 'time-sensitive', 'blocks others', 'decision needed', 'high stakes' — omit the field entirely if the title is vague>"}]. \
        Return only the JSON array, no other text, no markdown fences.
        """

        let numberedList = items.enumerated().map { i, item in
            "\(i + 1). [ID: \(item.id)] \(item.title)"
        }.joined(separator: "\n")

        let userMessage = "Here are my reminders:\n\n\(numberedList)\n\nIdentify the most important ones."

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        let responseData = try await performRequest(body: requestBody)
        return try parseFilterResponse(responseData, originalItems: items)
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
            // Extract human-readable message from Anthropic's error envelope when possible.
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

    private func parseFilterResponse(_ data: Data, originalItems: [ReminderItem]) throws -> [ReminderItem] {
        // Unwrap the Claude API envelope: { content: [{ type: "text", text: "..." }] }
        guard
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentBlocks = envelope["content"] as? [[String: Any]],
            let firstBlock = contentBlocks.first,
            let rawText = firstBlock["text"] as? String
        else {
            throw AnthropicError.parseError("Unexpected API response structure.")
        }

        // Claude returns a JSON array; strip any accidental markdown fences
        let cleanText = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let jsonData = cleanText.data(using: .utf8),
            let shortlist = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else {
            throw AnthropicError.parseError("Could not parse shortlist JSON from Claude's response.")
        }

        let itemsByID = Dictionary(uniqueKeysWithValues: originalItems.map { ($0.id, $0) })

        var filtered: [ReminderItem] = []
        for entry in shortlist {
            guard
                let id = entry["id"] as? String,
                var item = itemsByID[id]
            else { continue }
            item.aiReasoning = entry["reasoning"] as? String
            filtered.append(item)
        }

        // Fallback: if Claude returned no matching IDs, return the first 15 items
        if filtered.isEmpty {
            return Array(originalItems.prefix(15))
        }
        return filtered
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
