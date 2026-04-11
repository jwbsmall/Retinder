import SwiftUI

/// Root view. Requests Reminders access, syncs with EventKit, then shows HomeView.
struct ContentView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HomeView()
            .task { await bootstrap() }
    }

    private func bootstrap() async {
        if remindersManager.authorizationStatus == .notDetermined {
            _ = await remindersManager.requestAccess()
        }
        // syncWithEventKit calls fetchLists() internally and updates SwiftData.
        // Lists may already be populated from init() if access was pre-granted.
        await remindersManager.syncWithEventKit(context: modelContext)
    }
}
