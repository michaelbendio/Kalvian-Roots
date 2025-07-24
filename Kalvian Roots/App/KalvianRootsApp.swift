//
//  KalvianRootsApp.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import SwiftUI

@main
struct KalvianRootsApp: App {
    // Create the main app coordinator
    @State private var juuretApp = JuuretApp()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(juuretApp) // Provide app to all views
        }
    }
}
