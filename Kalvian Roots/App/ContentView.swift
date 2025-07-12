//
//  ContentView.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import SwiftUI

struct ContentView: View {
    @State private var app = JuuretApp()  // Use @State with @Observable
    
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
            Section("Recent Families") {
                // Future: Show recently extracted families
                Text("No recent families")
                    .foregroundColor(.secondary)
            }
            
            Section("Tools") {
                NavigationLink("Family Extraction") {
                    JuuretView()
                }
                
                NavigationLink("Hiski Search") {
                    Text("Hiski Search (Coming Soon)")
                }
                
                NavigationLink("FamilySearch") {
                    Text("FamilySearch Integration (Coming Soon)")
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
