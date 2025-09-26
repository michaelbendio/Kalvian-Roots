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
    }
}
