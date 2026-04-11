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
        switch remindersManager.authorizationStatus {
        case .notDetermined:
            _ = await remindersManager.requestAccess()
        case .fullAccess:
            await remindersManager.fetchLists()
        default:
            break
        }
        await remindersManager.syncWithEventKit(context: modelContext)
    }
}
