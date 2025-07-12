//
//  FileManager.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation
#if os(macOS)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

class JuuretFileManager {
    static func loadJuuretText() async throws -> String {
        let fileManager = Foundation.FileManager.default
        
        // Try to find the file in iCloud Documents
        guard let documentsURL = fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") else {
            throw JuuretError.fileNotFound
        }
        
        let fileURL = documentsURL.appendingPathComponent("JuuretKälviällä.txt")
        
        // Check if file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw JuuretError.fileNotFound
        }
        
        // Request download from iCloud if needed
        do {
            try fileManager.startDownloadingUbiquitousItem(at: fileURL)
        } catch {
            // Continue anyway - file might already be downloaded
            print("Could not start downloading item: \(error)")
        }
        
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

