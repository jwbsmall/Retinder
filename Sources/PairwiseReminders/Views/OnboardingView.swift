import SwiftUI
import UIKit

/// First-launch screen for entering the Anthropic API key.
struct OnboardingView: View {

    let onComplete: () -> Void

    @State private var apiKey = ""
    @State private var showError = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // App icon + headline
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.blue.gradient)
                            .frame(width: 96, height: 96)
                        Image(systemName: "arrow.up.arrow.down.square")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Text("PairwiseReminders")
                        .font(.largeTitle.bold())

                    Text("AI-powered pairwise prioritisation\nfor your Apple Reminders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // API key section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Anthropic API Key")
                        .font(.headline)

                    TextField("sk-ant-api03-...", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFieldFocused)
                        .onSubmit(saveAndContinue)
                        .textFieldStyle(.roundedBorder)

                    if showError {
                        Label("Enter a valid Anthropic key (starts with sk-ant-).", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Stored securely in your device Keychain. Never sent anywhere except Anthropic.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer()

                Button(action: saveAndContinue) {
                    Text("Save & Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(apiKey.isEmpty ? Color(.systemGray4) : Color.blue)
                        .foregroundStyle(apiKey.isEmpty ? Color.secondary : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .disabled(apiKey.isEmpty)
            }
            .padding()
            .onAppear {
                isFieldFocused = true
                // Auto-fill if the iOS pasteboard already holds an Anthropic key.
                // This sidesteps the Mac↔simulator clipboard isolation issue where
                // Cmd+V doesn't bridge the two clipboards.
                if apiKey.isEmpty,
                   let clip = UIPasteboard.general.string,
                   clip.hasPrefix("sk-ant-") {
                    apiKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    private func saveAndContinue() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-ant-") else { showError = true; return }
        if KeychainService.save(apiKey: trimmed) {
            onComplete()
        } else {
            showError = true
        }
    }
}
