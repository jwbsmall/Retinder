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

    /// Sendable snapshot of a reminder — only the fields needed for AI filtering.
    struct ReminderSummary: Sendable {
        let id: String
        let title: String
    }

    /// Sendable result from AI filtering — an ID and optional reasoning string.
    struct FilteredResult: Sendable {
        let id: String
        let reasoning: String?
    }

    /// Sends reminder summaries to Claude and returns the shortlisted IDs with reasoning.
    /// Callers are responsible for mapping results back to their domain objects.
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
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        let responseData = try await performRequest(body: requestBody)
        return try parseFilterResponse(responseData)
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

    private func parseFilterResponse(_ data: Data) throws -> [FilteredResult] {
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
