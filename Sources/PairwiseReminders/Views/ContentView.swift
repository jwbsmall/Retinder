import SwiftUI

/// Root view. Requests Reminders access, syncs with EventKit, then shows
/// a tab bar with Home, Prioritise, and Settings.
struct ContentView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            PrioritiseTab()
                .tabItem { Label("Prioritise", systemImage: "arrow.up.arrow.down") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
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

// MARK: - Prioritise Tab

/// Houses the full seeding → comparison → summary session flow.
private struct PrioritiseTab: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var eloEngine: EloEngine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            switch session.phase {
            case .idle:      ListPickerView()
            case .seeding:   FilteringView()
            case .comparing: PairwiseView()
            case .done:      ResultsView()
            }
        }
    }
}
