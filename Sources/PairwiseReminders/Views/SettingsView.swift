import SwiftUI
import SwiftData

/// Settings tab: AI configuration, per-list write-back rules, and ranking preferences.
struct SettingsView: View {

    @EnvironmentObject private var session: PairwiseSession
    @Environment(\.modelContext) private var modelContext

    @Query private var allConfigs: [ListConfig]
    private var importedConfigs: [ListConfig] { allConfigs.filter(\.isImported) }

    @State private var apiKey: String = ""
    @State private var apiKeyMasked = true
    @State private var apiKeySaved = false
    @State private var useOnDeviceModel: Bool = FoundationModelService.isAvailable
    @State private var aiPreference: PairwiseSession.AIPreference = .onDeviceFirst

    var body: some View {
        NavigationStack {
            Form {
                aiSection
                writeBackSection
                rankingSection
            }
            .navigationTitle("Settings")
            .onAppear { loadSettings() }
        }
    }

    // MARK: - AI Section

    private var aiSection: some View {
        Section {
            // API Key
            HStack {
                if apiKeyMasked {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } else {
                    TextField("sk-ant-…", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Button {
                    apiKeyMasked.toggle()
                } label: {
                    Image(systemName: apiKeyMasked ? "eye" : "eye.slash")
                        .foregroundStyle(.secondary)
                }
                Button("Save") {
                    saveAPIKey()
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if apiKeySaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            // On-device model toggle
            if FoundationModelService.isAvailable {
                Toggle("Use on-device model", isOn: $useOnDeviceModel)
                    .onChange(of: useOnDeviceModel) { _, _ in savePreferences() }
            }

            // Preference order
            Picker("Prefer", selection: $aiPreference) {
                ForEach(PairwiseSession.AIPreference.allCases, id: \.self) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
            .onChange(of: aiPreference) { _, newValue in
                session.aiPreference = newValue
            }
        } header: {
            Text("AI")
        } footer: {
            Text("The Anthropic API key is stored securely in the Keychain. On-device AI requires a supported device and uses no network.")
        }
    }

    // MARK: - Write-Back Section

    private var writeBackSection: some View {
        Section {
            if importedConfigs.isEmpty {
                Text("Import lists in the Home tab to configure write-back rules.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(importedConfigs) { config in
                    NavigationLink(config.calendarIdentifier) {
                        WriteBackConfigView(config: config)
                    }
                }
            }
        } header: {
            Text("Write-Back Rules")
        } footer: {
            Text("Configure how each list's ranking maps to Reminders priority, flags, and due dates.")
        }
    }

    // MARK: - Ranking Section

    private var rankingSection: some View {
        Section {
            if let config = importedConfigs.first {
                // Global default staleness — shown as a representative setting.
                Stepper(
                    "Stale after \(config.stalenessThresholdDays) days",
                    value: Binding(
                        get: { config.stalenessThresholdDays },
                        set: {
                            config.stalenessThresholdDays = $0
                            try? modelContext.save()
                        }
                    ),
                    in: 1...90
                )
            }
        } header: {
            Text("Ranking")
        } footer: {
            Text("Lists whose rankings are older than the staleness threshold show a warning badge on the Home tab.")
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        apiKey = KeychainService.load() ?? ""
        aiPreference = session.aiPreference
        useOnDeviceModel = FoundationModelService.isAvailable
            && UserDefaults.standard.bool(forKey: "use_on_device_model")
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        KeychainService.save(apiKey: trimmed)
        apiKeySaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            apiKeySaved = false
        }
    }

    private func savePreferences() {
        UserDefaults.standard.set(useOnDeviceModel, forKey: "use_on_device_model")
    }
}

// MARK: - Per-List Write-Back Config

private struct WriteBackConfigView: View {

    @Bindable var config: ListConfig
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Flags") {
                Stepper(
                    config.flagTopN == 0 ? "Flags: off" : "Flag top \(config.flagTopN)",
                    value: $config.flagTopN,
                    in: 0...50
                )
            }

            Section("Priority") {
                Picker("Mode", selection: $config.priorityMode) {
                    Text("None").tag("none")
                    Text("Tiered (High / Med / Low)").tag("tiered")
                    Text("Top N → High").tag("topN")
                }
                if config.priorityMode == "topN" {
                    Stepper("Top \(config.priorityTopN) → High", value: $config.priorityTopN, in: 1...50)
                }
            }

            Section("Due Dates") {
                Stepper(
                    config.dueDateTopN == 0 ? "Due dates: off" : "Set due date for top \(config.dueDateTopN)",
                    value: $config.dueDateTopN,
                    in: 0...50
                )
                if config.dueDateTopN > 0 {
                    Picker("Target date", selection: $config.dueDateTarget) {
                        Text("Today").tag("today")
                        Text("Tomorrow").tag("tomorrow")
                        Text("Next week").tag("nextWeek")
                    }
                }
            }

            Section("Trigger") {
                Toggle("Auto write-back on ranking change", isOn: $config.autoWriteBack)
            }

            Section("Staleness") {
                Stepper(
                    "Stale after \(config.stalenessThresholdDays) days",
                    value: $config.stalenessThresholdDays,
                    in: 1...90
                )
            }
        }
        .navigationTitle("Write-Back")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: config.flagTopN)              { _, _ in save() }
        .onChange(of: config.priorityMode)          { _, _ in save() }
        .onChange(of: config.priorityTopN)          { _, _ in save() }
        .onChange(of: config.dueDateTopN)           { _, _ in save() }
        .onChange(of: config.dueDateTarget)         { _, _ in save() }
        .onChange(of: config.autoWriteBack)         { _, _ in save() }
        .onChange(of: config.stalenessThresholdDays) { _, _ in save() }
    }

    private func save() {
        try? modelContext.save()
    }
}
