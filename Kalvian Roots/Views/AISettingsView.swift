import SwiftUI

struct AISettingsView: View {
    @Environment(JuuretApp.self) private var juuretApp

    @State private var showingAPIKeyInput = false
    @State private var tempAPIKey = ""

    var body: some View {
        Form {
            Section("AI Service") {
                HStack {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.green)

                    VStack(alignment: .leading) {
                        Text("DeepSeek")
                            .font(.headline)

                        Text(juuretApp.aiParsingService.isConfigured
                             ? "Configured"
                             : "Not configured")
                            .font(.caption)
                            .foregroundColor(
                                juuretApp.aiParsingService.isConfigured
                                ? .green
                                : .secondary
                            )
                    }

                    Spacer()

                    Button("Configure") {
                        showingAPIKeyInput = true
                    }
                }
            }
        }
        .navigationTitle("AI Settings")
        .sheet(isPresented: $showingAPIKeyInput) {
            apiKeyInputSheet
        }
    }

    private var apiKeyInputSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Configure DeepSeek API Key")
                    .font(.title2)

                SecureField("API Key", text: $tempAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.footnote, design: .monospaced))

                Button("Save") {
                    saveAPIKey()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tempAPIKey.isEmpty)

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAPIKeyInput = false
                        tempAPIKey = ""
                    }
                }
            }
        }
    }

    private func saveAPIKey() {
        Task {
            do {
                try await juuretApp.configureAIService(apiKey: tempAPIKey)
                tempAPIKey = ""
                showingAPIKeyInput = false
            } catch {
                // optional: show alert later
                print("Failed to configure AI: \(error)")
            }
        }
    }
}

#Preview {
    AISettingsView()
        .environment(JuuretApp())
}

