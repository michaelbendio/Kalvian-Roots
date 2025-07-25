//
//  ContentView.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(JuuretApp.self) private var app
    
    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                SidebarView()
            } detail: {
                JuuretView()
            }
            .environment(app)  // Use .environment instead of .environmentObject
            .navigationTitle("Kalvian Roots")
            #elseif os(visionOS)
            NavigationSplitView {
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
    }
}

// MARK: - Sidebar for macOS/visionOS
struct SidebarView: View {
    @Environment(JuuretApp.self) private var app  // Use @Environment
    
    var body: some View {
        List {
            Section("File Status") {
                HStack {
                    Circle()
                        .fill(app.fileManager.isFileLoaded ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(app.fileManager.isFileLoaded ? "File Loaded" : "No File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !app.fileManager.isFileLoaded {
                    Button("Open File") {
                        Task {
                            try? await app.fileManager.openFile()
                        }
                    }
                    .buttonStyle(.borderless)
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
            
            Section("Recent Families") {
                if let currentFamily = app.currentFamily {
                    Label(currentFamily.familyId, systemImage: "person.3.fill")
                        .font(.caption)
                } else {
                    Text("No recent families")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            Section("Tools") {
                NavigationLink("Family Extraction") {
                    JuuretView()
                }
                
                NavigationLink("AI Settings") {
                    AISettingsView()  // This now references the separate file
                }
                
                NavigationLink("Hiski Search") {
                    Text("Hiski Search (Coming Soon)")
                        .foregroundStyle(.secondary)
                }
                
                NavigationLink("FamilySearch") {
                    Text("FamilySearch Integration (Coming Soon)")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Debug") {
                Button("Load Sample Family") {
                    Task {
                        app.loadSampleFamily()
                    }
                }
                .buttonStyle(.borderless)
                
                Button("Test Cross-References") {
                    Task {
                        app.loadComplexSampleFamily()
                        try? await app.resolveCrossReferences()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .navigationTitle("Kalvian Roots")
        .frame(minWidth: 200)
    }
}

// MARK: - AISettingsView has been moved to its own file: Views/AISettingsView.swift

#Preview {
    ContentView()
}
