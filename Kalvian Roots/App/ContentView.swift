// ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(JuuretApp.self) private var app
    @State private var isSidebarExpanded = false  // Start with sidebar closed
    
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
