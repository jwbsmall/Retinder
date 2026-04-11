import Foundation
import SwiftData

/// Owns the SwiftData ModelContainer for the app. Access via `PersistenceController.shared`.
///
/// The container holds three models:
/// - `RankedItemRecord`: Elo rating metadata per reminder.
/// - `ListConfig`: Per-list import and write-back configuration.
/// - `ComparisonRecord`: Individual pairwise comparison decisions for the history log.
@MainActor
final class PersistenceController {

    static let shared = PersistenceController()

    let container: ModelContainer

    private init() {
        let schema = Schema([RankedItemRecord.self, ListConfig.self, ComparisonRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    /// A ModelContext bound to the main actor, suitable for view-layer use.
    var mainContext: ModelContext {
        container.mainContext
    }
}
