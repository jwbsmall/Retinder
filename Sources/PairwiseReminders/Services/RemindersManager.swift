import Foundation
import EventKit

/// Handles all EventKit interactions: requesting access, fetching reminders, writing priorities.
@MainActor
final class RemindersManager: ObservableObject {

    private let store = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var lists: [EKCalendar] = []

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    // MARK: - Access

    /// Requests full Reminders access. Returns true when granted.
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            if granted { await fetchLists() }
            return granted
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            return false
        }
    }

    func fetchLists() async {
        lists = store.calendars(for: .reminder)
    }

    // MARK: - Fetching

    /// Fetches all incomplete reminders from the given list identifiers.
    func fetchIncompleteReminders(from listIDs: Set<String>) async throws -> [ReminderItem] {
        let calendars = store.calendars(for: .reminder)
            .filter { listIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: RemindersError.fetchFailed)
                    return
                }
                let items = reminders.map { ReminderItem(from: $0) }
                continuation.resume(returning: items)
            }
        }
    }

    // MARK: - Writing

    /// Writes EKReminder priorities for the ranked items and commits to the store.
    /// `items` should be ordered from most to least important (index 0 = highest).
    func applyPriorities(_ items: [ReminderItem]) throws {
        let total = items.count
        guard total > 0 else { return }
        for item in items {
            item.ekReminder.priority = item.ekPriority(totalCount: total)
            try store.save(item.ekReminder, commit: false)
        }
        try store.commit()
    }

    /// Sets the due date (date-only, no time) for the top `count` ranked items, then commits.
    func applyDueDates(_ items: [ReminderItem], count: Int, dueDate: Date) throws {
        guard !items.isEmpty else { return }
        let n = min(count, items.count)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        for (index, item) in items.enumerated() {
            if index < n {
                item.ekReminder.dueDateComponents = components
            }
            try store.save(item.ekReminder, commit: false)
        }
        try store.commit()
    }

    /// Marks the top `count` items as High priority and the rest as None, then commits.
    func applyTopNUrgent(_ items: [ReminderItem], count: Int) throws {
        guard !items.isEmpty else { return }
        let n = min(count, items.count)
        for (index, item) in items.enumerated() {
            item.ekReminder.priority = index < n ? 1 : 0
            try store.save(item.ekReminder, commit: false)
        }
        try store.commit()
    }

    // MARK: - Errors

    enum RemindersError: LocalizedError {
        case fetchFailed
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .fetchFailed:  return "Failed to fetch reminders from the store."
            case .unauthorized: return "Reminders access was denied. Check Settings > Privacy."
            }
        }
    }
}
