//
//  ContentView.swift - Fixed for iOS/iPad full-width layout
//

import SwiftUI

struct ContentView: View {
    @Environment(JuuretApp.self) private var app
    @State private var showingAISettings = false
    @State private var hasLoadedStartupFamily = false
    @State private var showingFatalError = false

    var body: some View {
        Group {
            #if os(macOS)
            // macOS: Use NavigationSplitView with sidebar (NO custom toolbar button)
            NavigationSplitView {
                SidebarView()
            } detail: {
                switch app.detailRoute {
                case .family(let id):
                    JuuretView()
                        .id(id)
                        .overlay(
                            Text(app.currentFamily?.familyId ?? "nil")
                                .font(.caption)
                                .padding(4)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(4),
                            alignment: .topTrailing
                        )
                case .aiSettings:
                    AISettingsView()
                case .empty:
                    Text("Select a family or open AI Settings")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environment(app)
            .navigationTitle("Kalvian Roots")
            // REMOVED: The toolbar with duplicate sidebar button
            #else
            // iOS/iPadOS: Use NavigationStack with AI Settings sheet
            NavigationStack {
                JuuretView()
                    .navigationTitle("Kalvian Roots")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                showingAISettings = true
                            }) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(app.aiParsingService.isConfigured ? Color.green : Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text("AI")
                                        .font(.caption)
                                }
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingAISettings = true
                            }) {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .environment(app)
            .sheet(isPresented: $showingAISettings) {
                NavigationView {
                    AISettingsView()
                        .navigationTitle("AI Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingAISettings = false
                                }
                            }
                        }
                }
            }
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
                app.currentFamily = cachedNetwork.mainFamily
                app.familyNetworkWorkflow?.activateCachedNetwork(cachedNetwork)
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
                            // Try to load directly from cache for immediate UI switch
                            if let cached = app.familyNetworkCache.getCachedNetwork(familyId: familyId) {
                                // Updated: Use new helper and set route
                                let before = app.currentFamily?.familyId ?? "nil"
                                let network = cached
                                app.showFamilyFromCache(network)
                                let after = app.currentFamily?.familyId ?? "nil"
                                logInfo(.ui, "🔄 currentFamily changed: \(before) -> \(after)")
                                logInfo(.ui, "📦 Loaded cached family \(familyId) from Sidebar Cache (workflow activated)")
                            } else {
                                // Fallback: if not in cache (stale list), trigger extraction
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
                }
            }
            
            Section {
                Button("AI Settings") {
                    app.detailRoute = .aiSettings
                }
            }
        }
        .navigationTitle("Kalvian Roots")
        .frame(minWidth: 200)
    }
}

#Preview {
    ContentView()
}

