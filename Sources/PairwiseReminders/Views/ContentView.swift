import SwiftUI

/// Root view. Routes to the active session phase.
struct ContentView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager
    @EnvironmentObject private var engine: PairwiseEngine

    var body: some View {
        sessionView
            .task { await bootstrapRemindersAccess() }
    }

    @ViewBuilder
    private var sessionView: some View {
        switch session.phase {
        case .listPicking: ListPickerView()
        case .filtering:   FilteringView()
        case .comparing:   PairwiseView()
        case .results:     ResultsView()
        }
    }

    private func bootstrapRemindersAccess() async {
        switch remindersManager.authorizationStatus {
        case .notDetermined:
            _ = await remindersManager.requestAccess()
        case .fullAccess:
            await remindersManager.fetchLists()
        default:
            break
        }
    }
}
