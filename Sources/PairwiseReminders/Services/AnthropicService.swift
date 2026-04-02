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
        low-stakes errands, and anything that can clearly wait.
        """

        let numberedList = items.enumerated().map { i, item in
            "\(i + 1). [ID: \(item.id)] \(item.title)"
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
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw AnthropicError.apiError(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }

    private func parseFilterResponse(_ data: Data, originalItems: [ReminderItem]) throws -> [ReminderItem] {
        // Unwrap the Tool Use envelope: { content: [{ type: "tool_use", input: { items: [...] } }] }
        guard
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentBlocks = envelope["content"] as? [[String: Any]],
            let toolBlock = contentBlocks.first(where: { $0["type"] as? String == "tool_use" }),
            let input = toolBlock["input"] as? [String: Any],
            let shortlist = input["items"] as? [[String: Any]]
        else {
            throw AnthropicError.parseError("Unexpected Tool Use response structure.")
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

        // Fallback: if no IDs matched, return the first 15 items
        if filtered.isEmpty {
            return Array(originalItems.prefix(15))
        }
        return filtered
    }

    // MARK: - Errors

    enum AnthropicError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, body: String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Received an invalid response from the Anthropic API."
            case .apiError(let code, let body):
                return "API error \(code): \(body)"
            case .parseError(let msg):
                return "Failed to parse Claude's response: \(msg)"
            }
        }
    }
}
