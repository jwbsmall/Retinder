import Testing
import Foundation
@testable import PairwiseReminders

@Suite("AnthropicService")
struct AnthropicServiceTests {

    // MARK: - ReminderSummary

    @Test("ReminderSummary stores id and title")
    func reminderSummaryFields() {
        let summary = AnthropicService.ReminderSummary(id: "abc-123", title: "Buy milk")
        #expect(summary.id == "abc-123")
        #expect(summary.title == "Buy milk")
    }

    // MARK: - FilteredResult

    @Test("FilteredResult stores id and optional reasoning")
    func filteredResultFields() {
        let withReasoning = AnthropicService.FilteredResult(id: "x", reasoning: "Urgent")
        #expect(withReasoning.id == "x")
        #expect(withReasoning.reasoning == "Urgent")

        let withoutReasoning = AnthropicService.FilteredResult(id: "y", reasoning: nil)
        #expect(withoutReasoning.id == "y")
        #expect(withoutReasoning.reasoning == nil)
    }

    // MARK: - filterReminders edge cases

    @Test("filterReminders with empty input returns empty without network call")
    func emptyInputReturnsEmpty() async throws {
        // No API key needed — the guard fires before any network access.
        let service = AnthropicService(apiKey: "sk-ant-test-key")
        let result = try await service.filterReminders([])
        #expect(result.isEmpty)
    }
}
