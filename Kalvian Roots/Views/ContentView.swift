//
//  ContentView.swift - Fixed for iOS/iPad full-width layout
//

import SwiftUI

struct ContentView: View {
    @Environment(JuuretApp.self) private var app
    @State private var hasLoadedStartupFamily = false

    var body: some View {
        Group {
#if os(macOS)
            NavigationSplitView {
                SidebarView()
            } detail: {
                JuuretView()
            }
            .environment(app)
            .navigationTitle("Kalvian Roots")
#else
            NavigationStack {
                JuuretView()
            }
            .environment(app)
#endif
        }
        .task {
            await loadStartupFamily()
        }
    }

    /// Load the first cached family on startup
    private func loadStartupFamily() async {
        let startTime = Date()
        
        // Only run once
        guard !hasLoadedStartupFamily else { return }
        hasLoadedStartupFamily = true
        
        // Check if we have any cached families
        guard app.familyNetworkCache.hasCachedFamilies,
              let firstFamilyId = app.familyNetworkCache.getFirstCachedFamilyId() else {
            logInfo(.app, "📱 No cached families found at startup")
            return
        }
        
        logInfo(.app, "⏱️ T+0.000s: Starting cache load for \(firstFamilyId)")
        
        // Check if we're already displaying this family
        if app.currentFamily?.familyId == firstFamilyId {
            logInfo(.app, "✅ Already displaying \(firstFamilyId)")
            return
        }
        
        // Load from cache
        if let cachedNetwork = app.familyNetworkCache.getCachedNetwork(familyId: firstFamilyId) {
            let loadTime = Date().timeIntervalSince(startTime)
            logInfo(.app, "⏱️ T+\(String(format: "%.3f", loadTime))s: Loaded \(firstFamilyId) from cache instantly")
            
            await MainActor.run {
                app.showFamilyFromCache(cachedNetwork)
            }
            
            logInfo(.app, "✅ Startup family loaded: \(firstFamilyId)")
        } else {
            logWarn(.app, "⚠️ Cache entry exists but couldn't load network for \(firstFamilyId)")
        }
    }
}

// MARK: - Sidebar View (macOS only)

struct SidebarView: View {
    @Environment(JuuretApp.self) private var app
    @State private var showingAIConfiguration = false

    var body: some View {
        List {
            Section("App Status") {
                HStack {
                    Circle()
                        .fill(app.fileManager.isFileLoaded ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(app.fileManager.isFileLoaded ? "File Loaded" : "No File Loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Cache") {
                let cachedIds = app.familyNetworkCache.getAllCachedFamilyIds()
                if cachedIds.isEmpty {
                    Text("No cached families")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cachedIds.prefix(5), id: \.self) { familyId in
                        Button {
                            if let cached = app.familyNetworkCache.getCachedNetwork(familyId: familyId) {
                                let before = app.currentFamily?.familyId ?? "nil"
                                let network = cached
                                app.showFamilyFromCache(network)
                                let after = app.currentFamily?.familyId ?? "nil"
                                logInfo(.ui, "🔄 currentFamily changed: \(before) -> \(after)")
                                logInfo(.ui, "📦 Loaded cached family \(familyId) from Sidebar Cache (workflow activated)")
                            } else {
                                Task {
                                    logInfo(.ui, "⚠️ Cache miss for \(familyId) from Sidebar, extracting…")
                                    await app.extractFamily(familyId: familyId)
                                }
                            }
                        } label: {
                            Text(familyId)
                                .font(.caption)
                                .foregroundStyle(app.currentFamily?.familyId == familyId ? .primary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    if cachedIds.count > 5 {
                        Text("+ \(cachedIds.count - 5) more...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    Button(role: .destructive) {
                        app.familyNetworkCache.clearAllCache()
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            Section("AI Parsing") {
                HStack {
                    Circle()
                        .fill(app.aiParsingService.isConfigured ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(app.aiParsingService.isConfigured ? "Configured" : "Not Configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(app.aiParsingService.currentServiceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showingAIConfiguration = true
                } label: {
                    Label("Configure AI", systemImage: "gearshape")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Kalvian Roots")
        .frame(minWidth: 200)
        .sheet(isPresented: $showingAIConfiguration) {
            AIParsingConfigurationView()
                .environment(app)
        }
    }
}

private struct AIParsingConfigurationView: View {
    @Environment(JuuretApp.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Parsing")
                .font(.title3.weight(.semibold))

            HStack {
                Circle()
                    .fill(app.aiParsingService.isConfigured ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(app.aiParsingService.isConfigured ? "Configured" : "Not Configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Provider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(app.aiParsingService.currentServiceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("Enter \(app.aiParsingService.currentServiceName) API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(isSaving ? "Saving..." : "Save") {
                    saveConfiguration()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    private func saveConfiguration() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await app.configureAIService(apiKey: trimmedKey)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
