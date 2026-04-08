import Foundation
@preconcurrency import EventKit
import SwiftData

// EKReminder and EKCalendar are ObjC classes with no Sendable annotation.
// We always access them on the main actor, so this is safe.
extension EKReminder: @unchecked Sendable {}
extension EKCalendar: @unchecked Sendable {}

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

    /// Fetches all incomplete reminders from the given list identifiers, loading
    /// Elo ratings from SwiftData where available.
    func fetchIncompleteReminders(
        from listIDs: Set<String>,
        context: ModelContext
    ) async throws -> [ReminderItem] {
        let calendars = store.calendars(for: .reminder)
            .filter { listIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: RemindersError.fetchFailed)
                    return
                }
                continuation.resume(returning: reminders)
            }
        }

        let idsSet = Set(reminders.map(\.calendarItemIdentifier))
        let existingRecords = ((try? context.fetch(FetchDescriptor<RankedItemRecord>())) ?? [])
            .filter { idsSet.contains($0.calendarItemIdentifier) }
        let recordsByID = Dictionary(uniqueKeysWithValues: existingRecords.map {
            ($0.calendarItemIdentifier, $0)
        })

        return reminders.map { reminder in
            let record = recordsByID[reminder.calendarItemIdentifier]
            return ReminderItem(
                from: reminder,
                eloRating: record?.eloRating ?? 1000.0,
                kFactor: record?.kFactor ?? 32.0
            )
        }
    }

    // MARK: - Sync

    /// Syncs SwiftData with the current state of EventKit for all imported lists.
    /// - Inserts `RankedItemRecord` for reminders not yet tracked.
    /// - Deletes records for reminders that no longer exist or are completed.
    ///
    /// Call on app launch and when returning to the foreground.
    func syncWithEventKit(context: ModelContext) async {
        await fetchLists()

        // Fetch all list configs to know which lists are imported.
        let importedConfigs = ((try? context.fetch(FetchDescriptor<ListConfig>())) ?? [])
            .filter(\.isImported)
        guard !importedConfigs.isEmpty else { return }

        let importedListIDs = Set(importedConfigs.map(\.calendarIdentifier))
        let importedCalendars = lists.filter { importedListIDs.contains($0.calendarIdentifier) }
        guard !importedCalendars.isEmpty else { return }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: importedCalendars
        )

        guard let reminders = await fetchRemindersAsync(matching: predicate) else { return }

        let liveIDs = Set(reminders.map(\.calendarItemIdentifier))

        // Fetch all tracked records for imported lists.
        let existingRecords = ((try? context.fetch(FetchDescriptor<RankedItemRecord>())) ?? [])
            .filter { importedListIDs.contains($0.listCalendarIdentifier) }
        let trackedIDs = Set(existingRecords.map(\.calendarItemIdentifier))

        // Insert new reminders.
        for reminder in reminders {
            let rid = reminder.calendarItemIdentifier
            guard !trackedIDs.contains(rid) else { continue }
            let calID = reminder.calendar?.calendarIdentifier ?? ""
            let record = RankedItemRecord(
                calendarItemIdentifier: rid,
                listCalendarIdentifier: calID
            )
            context.insert(record)
        }

        // Delete stale records (reminder was completed or deleted).
        for record in existingRecords where !liveIDs.contains(record.calendarItemIdentifier) {
            context.delete(record)
        }

        try? context.save()
    }

    private func fetchRemindersAsync(matching predicate: NSPredicate) async -> [EKReminder]? {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders)
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

    /// Sets a flag on the top `count` items and removes it from the rest, then commits.
    func applyFlags(_ items: [ReminderItem], count: Int) throws {
        guard !items.isEmpty, count > 0 else { return }
        let n = min(count, items.count)
        for (index, item) in items.enumerated() {
            item.ekReminder.isCompleted = false  // ensure not accidentally completing
            // EKReminder doesn't expose a flag property directly; use priority 1 as a proxy.
            // iOS Reminders shows flagged items separately regardless of priority.
            // The Reminders app's "flag" is stored as `isFlagged` on EKReminder in iOS 16+.
            // Accessing it dynamically to avoid compile errors on older SDKs.
            item.ekReminder.setValue(index < n, forKey: "isFlagged")
            try store.save(item.ekReminder, commit: false)
        }
        try store.commit()
    }

    /// Marks the reminder as completed and commits.
    func complete(_ item: ReminderItem) throws {
        item.ekReminder.isCompleted = true
        item.ekReminder.completionDate = Date()
        try store.save(item.ekReminder, commit: true)
    }

    /// Updates a reminder's fields in-place and commits immediately.
    func updateReminder(_ item: ReminderItem, title: String, notes: String?,
                        calendarID: String?, dueDate: Date?) throws {
        let reminder = item.ekReminder
        reminder.title = title
        reminder.notes = notes?.isEmpty == true ? nil : notes
        if let calendarID,
           let calendar = lists.first(where: { $0.calendarIdentifier == calendarID }) {
            reminder.calendar = calendar
        }
        if let dueDate {
            reminder.dueDateComponents = Calendar.current
                .dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
        try store.save(reminder, commit: true)
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
