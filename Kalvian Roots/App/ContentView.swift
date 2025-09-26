// ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(JuuretApp.self) private var app
    @State private var isSidebarExpanded = false  // Start with sidebar closed
    @State private var hasLoadedStartupFamily = false

    var body: some View {
        Group {
            #if os(macOS)
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
            #elseif os(visionOS)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
            } detail: {
                JuuretView()
            }
            .environment(app)
            .navigationTitle("Kalvian Roots")
            #else
            NavigationView {
                JuuretView()
            }
            .environment(app)
            .navigationTitle("Kalvian Roots")
            .navigationBarTitleDisplayMode(.large)
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
        
        // Check if we're already displaying a family
        guard app.currentFamily == nil else {
            logInfo(.app, "📱 Family already loaded, skipping startup load")
            return
        }
        
        let checkTime1 = Date()
        logInfo(.app, "⏱️ T+\(String(format: "%.3f", checkTime1.timeIntervalSince(startTime)))s: Checks complete, retrieving from cache")
        
        // Load from cache directly WITHOUT checking if file is ready
        if let cached = app.familyNetworkCache.getCachedNetwork(familyId: firstFamilyId) {
            let cacheRetrieveTime = Date()
            logInfo(.app, "⏱️ T+\(String(format: "%.3f", cacheRetrieveTime.timeIntervalSince(startTime)))s: Cache retrieved")
            
            await MainActor.run {
                let mainActorStartTime = Date()
                logInfo(.app, "⏱️ T+\(String(format: "%.3f", mainActorStartTime.timeIntervalSince(startTime)))s: MainActor update starting")
                
                // Set the family directly from cache
                app.currentFamily = cached.network.mainFamily
                app.enhancedFamily = cached.network.mainFamily
                
                let familySetTime = Date()
                logInfo(.app, "⏱️ T+\(String(format: "%.3f", familySetTime.timeIntervalSince(startTime)))s: Families set")
                
                // Create workflow with cached network
                app.familyNetworkWorkflow = FamilyNetworkWorkflow(
                    nuclearFamily: cached.network.mainFamily,
                    familyResolver: app.familyResolver,
                    resolveCrossReferences: false  // Already resolved in cache
                )
                
                let workflowTime = Date()
                logInfo(.app, "⏱️ T+\(String(format: "%.3f", workflowTime.timeIntervalSince(startTime)))s: Workflow created")
                
                // Activate the cached network
                app.familyNetworkWorkflow?.activateCachedNetwork(cached.network)
                
                let activateTime = Date()
                logInfo(.app, "⏱️ T+\(String(format: "%.3f", activateTime.timeIntervalSince(startTime)))s: Network activated")
                
                // Clear any error state
                app.errorMessage = nil
                app.isProcessing = false
                app.extractionProgress = .idle
                
                let completeTime = Date()
                logInfo(.app, "⏱️ T+\(String(format: "%.3f", completeTime.timeIntervalSince(startTime)))s: ✅ Cache load complete")
                
                logInfo(.app, """
                    📊 Cache Load Performance Breakdown:
                    - Cache retrieval: \(String(format: "%.3f", cacheRetrieveTime.timeIntervalSince(checkTime1)))s
                    - MainActor wait: \(String(format: "%.3f", mainActorStartTime.timeIntervalSince(cacheRetrieveTime)))s
                    - Family assignment: \(String(format: "%.3f", familySetTime.timeIntervalSince(mainActorStartTime)))s
                    - Workflow creation: \(String(format: "%.3f", workflowTime.timeIntervalSince(familySetTime)))s
                    - Network activation: \(String(format: "%.3f", activateTime.timeIntervalSince(workflowTime)))s
                    - Cleanup: \(String(format: "%.3f", completeTime.timeIntervalSince(activateTime)))s
                    - TOTAL: \(String(format: "%.3f", completeTime.timeIntervalSince(startTime)))s
                    """)
            }
            
            // Start background processing for next family once file loads
            Task {
                // This runs separately and shouldn't block the UI
                let fileReady = await app.waitForFileReady()
                if fileReady {
                    app.familyNetworkCache.startBackgroundProcessing(
                        currentFamilyId: firstFamilyId,
                        fileManager: app.fileManager,
                        aiService: app.aiParsingService,
                        familyResolver: app.familyResolver
                    )
                }
            }
        } else {
            logError(.app, "❌ Failed to retrieve cached family: \(firstFamilyId)")
        }
    }

}

// MARK: - Simplified Sidebar
struct SidebarView: View {
    @Environment(JuuretApp.self) private var app
    @State private var fm = RootsFileManager()
    
    var body: some View {
        List {
            Section("File Status") {
                HStack {
                    Circle()
                        .fill(fm.isFileLoaded ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(fm.isFileLoaded ? "File Loaded" : "No File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !fm.isFileLoaded {
                    Button("Open File") {
                        Task {
                            try? await fm.openFile()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            // NEW SECTION: Cached Families
            Section("Cached Families") {
                let cachedIds = app.familyNetworkCache.getAllCachedFamilyIds()
                
                if cachedIds.isEmpty {
                    Text("No cached families")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(cachedIds.count) families cached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Show first few cached families
                    ForEach(cachedIds.prefix(5), id: \.self) { familyId in
                        Button(familyId) {
                            Task {
                                await app.extractFamily(familyId: familyId)
                            }
                        }
                        .buttonStyle(.borderless)
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
            
            // Only AI Settings navigation remains
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
