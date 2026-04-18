import SwiftUI

/// Root view. Shows a splash screen while bootstrapping, then fades into HomeView.
struct ContentView: View {

    @EnvironmentObject private var remindersManager: RemindersManager
    @Environment(\.modelContext) private var modelContext

    @State private var isReady = false

    var body: some View {
        ZStack {
            // HomeView starts loading behind the splash so it's ready the moment we fade in.
            HomeView()
                .opacity(isReady ? 1 : 0)

            if !isReady {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: isReady)
        .task { await bootstrap() }
    }

    private func bootstrap() async {
        if remindersManager.authorizationStatus == .notDetermined {
            _ = await remindersManager.requestAccess()
        }
        // syncWithEventKit calls fetchLists() internally and updates SwiftData.
        // Lists may already be populated from init() if access was pre-granted.
        await remindersManager.syncWithEventKit(context: modelContext)
        isReady = true
    }
}

// MARK: - Splash Screen

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: 6) {
                Text("Retinder")
                    .font(.largeTitle.bold())
                Text("Syncing your reminders…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView()
                .scaleEffect(1.2)
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
