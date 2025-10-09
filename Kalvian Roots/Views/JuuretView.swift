//
//  JuuretView.swift
//  Kalvian Roots
//
//  Main family display view with new UI redesign
//  Phases 1-4 complete: Navigation + Enhanced Display
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
    
    var body: some View {
        VStack(spacing: 0) {
            if juuretApp.fileManager.isFileLoaded {
                // Navigation bar at top
                NavigationBarView()
                
                // Main content area
                if let family = juuretApp.currentFamily {
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
                } else {
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
                CachedFamiliesMenu()
            }
        }
        #elseif os(iOS) || os(visionOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                CachedFamiliesMenu()
            }
        }
        .setupHiskiSafariHost()
        #endif
        
        // Citation alert
        .alert("Citation", isPresented: $showingCitation) {
            Button("Copy to Clipboard") {
                copyToClipboard(citationText)
            }
            Button("OK") { }
        } message: {
            Text(citationText)
                .font(.system(size: 13, design: .monospaced))
        }
        
        // Hiski result alert
        .alert("Hiski Query Result", isPresented: $showingHiskiResult) {
            Button("Copy URL") {
                copyToClipboard(hiskiResult)
                juuretApp.closeHiskiWebViews()
            }
            Button("OK") {
                juuretApp.closeHiskiWebViews()
            }
        } message: {
            Text(hiskiResult)
                .font(.system(size: 13, design: .monospaced))
        }
        
        // Fatal error alert
        .alert("Fatal Error", isPresented: $showingFatalError) {
            Button("Quit", role: .destructive) {
                #if os(macOS)
                NSApplication.shared.terminate(nil)
                #endif
            }
        } message: {
            Text(juuretApp.errorMessage ?? "Unknown error")
                .font(.system(size: 13, design: .monospaced))
        }
        
        .onAppear {
            logInfo(.ui, "JuuretView appeared")
            Task {
                await juuretApp.fileManager.autoLoadDefaultFile()
                if !juuretApp.fileManager.isFileLoaded {
                    showingFatalError = true
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Family Loaded")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter a family ID in the navigation bar above")
                .font(.callout)
                .foregroundColor(.secondary)
            
            if juuretApp.familyNetworkCache.cachedFamilyCount > 0 {
                VStack(spacing: 12) {
                    Text("Or select from \(juuretApp.familyNetworkCache.cachedFamilyCount) cached families")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        juuretApp.familyNetworkCache.clearCache()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Clear Cache")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "fefdf8"))
    }
    
    // MARK: - Helpers
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        
        logInfo(.ui, "📋 Copied to clipboard: \(text.prefix(100))...")
    }
}

// MARK: - Preview

#Preview {
    JuuretView()
        .environment(JuuretApp())
}
