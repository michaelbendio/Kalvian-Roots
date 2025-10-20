//
//  ContentView.swift - Fixed for iOS/iPad full-width layout
//

import SwiftUI

struct ContentView: View {
    @Environment(JuuretApp.self) private var app
    @State private var isSidebarExpanded = false
    @State private var hasLoadedStartupFamily = false
    @State private var showingFatalError = false

    var body: some View {
        Group {
            #if os(macOS)
            // macOS: Use NavigationSplitView with sidebar
            NavigationSplitView(columnVisibility: .constant(isSidebarExpanded ? .all : .detailOnly)) {
                SidebarView()
            } detail: {
                JuuretView()
            }
            .environment(app)
            .navigationTitle("Kalvian Roots")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: { isSidebarExpanded.toggle() }) {
                        Image(systemName: "sidebar.left")
                            .help("Toggle Sidebar")
                    }
                }
            }
            #else
            // iOS/iPadOS: Use NavigationStack for full-width layout
            NavigationStack {
                JuuretView()
                    .navigationTitle("Kalvian Roots")
                    .navigationBarTitleDisplayMode(.inline)
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
        if let cached = app.familyNetworkCache.getCachedNetwork(familyId: firstFamilyId) {
            let loadTime = Date().timeIntervalSince(startTime)
            logInfo(.app, "⏱️ T+\(String(format: "%.3f", loadTime))s: Loaded \(firstFamilyId) from cache instantly")
            
            await MainActor.run {
                app.currentFamily = cached.network.mainFamily
                app.familyNetworkWorkflow?.activateCachedNetwork(cached.network)
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
                        Text(familyId)
                            .font(.caption)
                            .foregroundStyle(app.currentFamily?.familyId == familyId ? .primary : .secondary)
                    }
                    
                    if cachedIds.count > 5 {
                        Text("+ \(cachedIds.count - 5) more...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            Section("AI Service") {
                HStack {
                    Circle()
                        .fill(app.aiParsingService.isConfigured ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(app.currentServiceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !app.aiParsingService.isConfigured {
                    Text("Add API key in settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                NavigationLink("AI Settings") {
                    AISettingsView()
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
