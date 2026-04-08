import SwiftUI
import SwiftData

@main
struct PairwiseRemindersApp: App {
    @StateObject private var session = PairwiseSession()
    @StateObject private var remindersManager = RemindersManager()
    @StateObject private var eloEngine = EloEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(remindersManager)
                .environmentObject(eloEngine)
                .modelContainer(PersistenceController.shared.container)
        }
    }
}
