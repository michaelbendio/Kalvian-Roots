//
//  KalvianRootsApp.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import SwiftUI

@main
struct KalvianRootsApp: App {
    @State private var juuretApp = JuuretApp()
    @State private var showingFatalError = false
    @State private var fileCheckComplete = false
    
    var body: some Scene {
        WindowGroup {
            if !fileCheckComplete {
                // Show loading while checking for file
                VStack {
                    ProgressView()
                    Text("Checking for canonical file...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    await juuretApp.fileManager.autoLoadDefaultFile()
                    fileCheckComplete = true
                    if !juuretApp.fileManager.isFileLoaded {
                        showingFatalError = true
                    }
                }
            } else if showingFatalError {
                // Show error screen - no other UI
                VStack {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Fatal Error")
                        .font(.largeTitle)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alert("Fatal Error: Canonical File Not Found", isPresented: $showingFatalError) {
                    Button("Quit", role: .destructive) {
                        #if os(macOS)
                        NSApplication.shared.terminate(nil)
                        #else
                        exit(0)  // Force quit on iOS
                        #endif
                    }
                } message: {
                    Text("""
                        JuuretKälviällä.roots must be in:
                        ~/Library/Mobile Documents/iCloud~com~michael-bendio~Kalvian-Roots/Documents/
                        
                        First line must be: canonical
                        Second line must be: blank
                        """)
                }
            } else {
                // Normal app only if file loaded successfully
                ContentView()
                    .environment(juuretApp)
            }
        }
    }
}
