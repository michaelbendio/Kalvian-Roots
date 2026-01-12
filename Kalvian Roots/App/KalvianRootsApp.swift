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
                }
            } else if !juuretApp.fileManager.isFileLoaded {
                #if os(iOS)
                // iOS: Show document picker if file not loaded
                DocumentPickerView(fileManager: juuretApp.fileManager)
                #else
                // macOS: Show fatal error (shouldn't happen with direct access)
                VStack {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Fatal Error")
                        .font(.largeTitle)
                        .padding()
                    Text(juuretApp.fileManager.errorMessage ?? "Cannot load file")
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            } else {
                // Normal app - file loaded successfully
                ContentView()
                    .environment(juuretApp)
            }
        }
    }
}
