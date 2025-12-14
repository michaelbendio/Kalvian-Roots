//
//  JuuretView.swift - UPDATED with AI Ready Indicator
//  Kalvian Roots
//
//  Main family display view with green dot showing when AI is ready
//

import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct JuuretView: View {
    @Environment(JuuretApp.self) private var juuretApp
    @State private var showingCitation = false
    @State private var citationText = ""
    @State private var showingHiskiResult = false
    @State private var hiskiResult = ""
    @State private var showingFatalError = false
    @State private var shouldCloseHiskiWindows = false
    
    var body: some View {
        VStack(spacing: 0) {
            if juuretApp.fileManager.isFileLoaded {
                // Navigation bar at top
                NavigationBarView()
                
                // Main content area - CHECK FOR PENDING ID FIRST
                if let pendingId = juuretApp.pendingFamilyId {
                    // LOADING STATE - Show while extracting
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading \(pendingId)...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: "fefdf8"))
                    
                } else if let family = juuretApp.currentFamily {
                    // FAMILY LOADED - Show content
                    FamilyContentView(
                        family: family,
                        onShowCitation: { citation in
                            citationText = citation
                            showingCitation = true
                        },
                        onShowHiski: { result in
                            hiskiResult = result
                            showingHiskiResult = true
                        }
                    )
                    .id(family.familyId)
                } else {
                    // NO FAMILY - Show empty state
                    emptyStateView
                }
            } else {
                Color.clear
            }
        }
        .navigationTitle("Kalvian Roots")
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // AI READY INDICATOR - Green dot when AI is ready
                Circle()
                    .fill(isAIReady ? Color.green : Color.clear)
                    .frame(width: 6, height: 6)
                    .opacity(isAIReady ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.3), value: isAIReady)
                
                CachedFamiliesMenu()
            }
        }
        #elseif os(iOS) || os(visionOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    // AI READY INDICATOR - Green dot when AI is ready
                    Circle()
                        .fill(isAIReady ? Color.green : Color.clear)
                        .frame(width: 6, height: 6)
                        .opacity(isAIReady ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.3), value: isAIReady)
                    
                    CachedFamiliesMenu()
                }
            }
        }
        .setupHiskiSafariHost()
        #endif
        
        // Citation alert
        .alert("Citation", isPresented: $showingCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(citationText)
                shouldCloseHiskiWindows = true
            }
            Button("OK", role: .cancel) {
                // Don't close windows for regular citations
            }
        } message: {
            Text(citationText)
        }
        .onChange(of: showingCitation) { _, newValue in
            if !newValue && shouldCloseHiskiWindows {
                #if os(macOS)
                closeAllHiskiWindows()
                #endif
                shouldCloseHiskiWindows = false
            }
        }
        
        // Hiski result alert
        .alert("Hiski Query", isPresented: $showingHiskiResult) {
            Button("Copy to Clipboard") {
                copyToClipboard(hiskiResult)
            }
            #if os(macOS)
            Button("Open in Browser") {
                openHiskiInBrowser(hiskiResult)
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text(hiskiResult)
        }
    }
    
    // MARK: - AI Ready Indicator Logic
    
    private var isAIReady: Bool {
        juuretApp.aiParsingService.isConfigured
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72))
                .foregroundColor(.gray)
            
            Text("No Family Selected")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("Enter a family ID in the navigation bar or select from cached families")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "fefdf8"))
    }
    
    // MARK: - Helper Methods
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
    
    #if os(macOS)
    private func openHiskiInBrowser(_ url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func closeAllHiskiWindows() {
        // Close all Safari windows with hiski.genealogia.fi
        let script = """
        tell application "Safari"
            set windowList to every window
            repeat with aWindow in windowList
                try
                    set tabList to every tab of aWindow
                    repeat with aTab in tabList
                        if URL of aTab contains "hiski.genealogia.fi" then
                            close aTab
                        end if
                    end repeat
                end try
            end repeat
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logWarn(.app, "Failed to close Hiski windows: \(error)")
            }
        }
    }
    #endif
}

// MARK: - Preview

#Preview {
    JuuretView()
        .environment(JuuretApp())
}
