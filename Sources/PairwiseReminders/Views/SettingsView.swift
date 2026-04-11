import SwiftUI

/// Settings tab: AI configuration.
struct SettingsView: View {

    @EnvironmentObject private var session: PairwiseSession
    @EnvironmentObject private var remindersManager: RemindersManager

    @State private var apiKey: String = ""
    @State private var apiKeyMasked = true
    @State private var apiKeySaved = false
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var useOnDeviceModel: Bool = FoundationModelService.isAvailable
    @State private var aiPreference: PairwiseSession.AIPreference = .onDeviceFirst

    private enum ConnectionTestState: Equatable {
        case idle, testing, ok, failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                aiSection
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

            // Connection test
            HStack {
                Button("Test connection") {
                    testConnection()
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                          || connectionTest == .testing)
                Spacer()
                connectionTestLabel
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

    @ViewBuilder
    private var connectionTestLabel: some View {
        switch connectionTest {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        apiKey = KeychainService.load() ?? ""
        aiPreference = session.aiPreference
        useOnDeviceModel = FoundationModelService.isAvailable
            && UserDefaults.standard.bool(forKey: "use_on_device_model")
    }

    private func testConnection() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        connectionTest = .testing
        Task {
            do {
                try await AnthropicService(apiKey: key).testConnection()
                connectionTest = .ok
            } catch AnthropicService.AnthropicError.apiError(let code, let message) {
                connectionTest = .failed("Error \(code): \(message)")
            } catch {
                connectionTest = .failed(error.localizedDescription)
            }
        }
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
