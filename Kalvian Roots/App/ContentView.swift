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
        // Only run once
        guard !hasLoadedStartupFamily else { return }
        hasLoadedStartupFamily = true
        
        // Check if we have any cached families
        guard app.familyNetworkCache.hasCachedFamilies,
              let firstFamilyId = app.familyNetworkCache.getFirstCachedFamilyId() else {
            logInfo(.app, "📱 No cached families found at startup")
            return
        }
        
        // Check if we're already displaying a family
        guard app.currentFamily == nil else {
            logInfo(.app, "📱 Family already loaded, skipping startup load")
            return
        }
        
        logInfo(.app, "🚀 Loading cached family immediately: \(firstFamilyId)")
        
        // Load from cache directly WITHOUT checking if file is ready
        // The cache is self-contained and doesn't need the file
        if let cached = app.familyNetworkCache.getCachedNetwork(familyId: firstFamilyId) {
            await MainActor.run {
                // Set the family directly from cache
                app.currentFamily = cached.network.mainFamily
                app.enhancedFamily = cached.network.mainFamily
                
                // Create workflow with cached network
                app.familyNetworkWorkflow = FamilyNetworkWorkflow(
                    nuclearFamily: cached.network.mainFamily,
                    familyResolver: app.familyResolver,
                    resolveCrossReferences: false  // Already resolved in cache
                )
                
                // Activate the cached network
                app.familyNetworkWorkflow?.activateCachedNetwork(cached.network)
                
                // Clear any error state
                app.errorMessage = nil
                app.isProcessing = false
                app.extractionProgress = .idle
                
                logInfo(.app, "✅ Loaded cached family on startup: \(firstFamilyId)")
            }
            
            // Start background processing for next family once file loads
            Task {
                // Wait for file to be ready before starting background processing
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
