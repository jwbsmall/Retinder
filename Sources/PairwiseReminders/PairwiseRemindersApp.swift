import SwiftUI

@main
struct PairwiseRemindersApp: App {
    @StateObject private var session = PairwiseSession()
    @StateObject private var remindersManager = RemindersManager()
    @StateObject private var engine = PairwiseEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(remindersManager)
                .environmentObject(engine)
        }
    }
}
