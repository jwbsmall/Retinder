import SwiftUI

/// Root view. Requests Reminders access, syncs with EventKit, then shows
/// a tab bar with Home, Prioritise, and Settings.
struct ContentView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var session: PairwiseSession
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            PrioritiseTab()
                .tabItem { Label("Prioritise", systemImage: "arrow.up.arrow.down") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(2)
        }
        // When a list sets pendingListIDs, switch to the Prioritise tab automatically.
        .onChange(of: session.pendingListIDs) { _, ids in
            if !ids.isEmpty { selectedTab = 1 }
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
