//
//  JuuretFileCommands.swift
//  Kalvian Roots
//
//  File menu commands for standard macOS file operations
//

import SwiftUI

/**
 * File menu commands for Juuret Kälviällä text file operations.
 * Provides standard macOS File menu behavior.
 */
struct JuuretFileCommands: Commands {
    var body: some Commands {
        // Replace the default "New" menu item
        CommandGroup(replacing: .newItem) {
            // Remove "New" - we don't create new genealogy files
        }
        
        // Add our file operations after the newItem group
        CommandGroup(after: .newItem) {
            Button("Open...") {
                Task {
                    // We'll need to get the app instance from the environment
                    // For now, let's use a simplified approach
                    do {
                        let content = try await JuuretFileManager.loadJuuretText()
                        print("✅ File loaded via static method: \(content.count) characters")
                    } catch {
                        print("❌ Failed to open file: \(error)")
                    }
                }
            }
            .keyboardShortcut("o", modifiers: .command)
            
            // For now, let's simplify the recent files menu
            Button("Open Recent...") {
                // TODO: Implement recent files when app state is available
                print("Recent files not yet implemented in menu commands")
            }
            .disabled(true)
        }
    }
}
