//
//  FileManager.swift
//  Kalvian Roots
//
//  Canonical location file management for cross-device sync
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/**
 * FileManager.swift - Canonical location file management
 *
 * Handles file operations with ONE canonical location: iCloud Drive/Kalvian Roots/Documents/JuuretKälviällä.roots
 * This location works across Mac, iPad, iPhone and is easily user-accessible.
 */

@Observable
class FileManager {
    
    // MARK: - Properties
    
    /// Current file state - Made publicly settable for iOS document picker
    #if os(iOS)
    var currentFileURL: URL?
    var currentFileContent: String?
    var isFileLoaded: Bool = false
    #else
    private(set) var currentFileURL: URL?
    private(set) var currentFileContent: String?
    private(set) var isFileLoaded: Bool = false
    #endif
    
    /// Recent files management
    private(set) var recentFileURLs: [URL] = []
    
    /// The ONE canonical file name
    private let defaultFileName = "JuuretKälviällä.roots"
    
    var iCloudDocumentsURL: URL? {
        Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }
        
    // MARK: - Initialization
    
    init() {
        loadRecentFiles()
        logInfo(.file, "📁 FileManager initialized with canonical location strategy")
    }
    
    // MARK: - File Operations
    
#if os(macOS)
    /**
     * Open file with system file picker (macOS)
     */
    func openFile() async throws -> String {
        logInfo(.file, "🗂️ User requested file picker (macOS)")
        return try await MainActor.run {
            logDebug(.file, "Creating file picker on main thread (macOS)")
            let panel = NSOpenPanel()
            panel.title = "Open Juuret Kälviällä File"
            panel.allowedContentTypes = []
            panel.allowsOtherFileTypes = true
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.message = "Select your Juuret Kälviällä file (.roots, .txt, or any text file)"
            panel.prompt = "Open File"
            logDebug(.file, "NSOpenPanel configured, presenting modal dialog")
            let response = panel.runModal()
            logDebug(.file, "NSOpenPanel response: \(response == .OK ? "OK" : "Cancel")")
            if response == .OK, let url = panel.url {
                logInfo(.file, "✅ User selected file: \(url.lastPathComponent)")
                logDebug(.file, "Full path: \(url.path)")
                return try self.processSelectedFile(url)
            } else if response == .OK {
                logError(.file, "❌ NSOpenPanel returned OK but no URL")
                throw FileManagerError.loadFailed("No file URL returned from picker")
            } else {
                logInfo(.file, "User cancelled file selection")
                throw FileManagerError.userCancelled
            }
        }
    }
#elseif os(iOS)
    /**
     * On iPadOS/iOS, file picking must be handled via UIDocumentPickerViewController in the View layer.
     * This method is kept for API compatibility but shouldn't be called directly on iOS.
     */
    func openFile() async throws -> String {
        logWarn(.file, "⚠️ Use processSelectedFileFromPicker(url:) for iOS/iPadOS file handling")
        throw FileManagerError.loadFailed("Use the document picker UI on iOS/iPadOS")
    }
    
    /**
     * Process a file selected from UIDocumentPickerViewController (iOS/iPadOS)
     * This is called from the View layer after user selects a file
     */
    func processSelectedFileFromPicker(_ url: URL) async throws -> String {
        logInfo(.file, "📂 Processing file from iOS document picker: \(url.lastPathComponent)")
        
        // The security-scoped resource access is handled in the View layer
        // Just read the content here
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Update state
            await MainActor.run {
                self.currentFileURL = url
                self.currentFileContent = content
                self.isFileLoaded = true
            }
            
            // Update recent files
            addToRecentFiles(url)
            
            logInfo(.file, "✅ File loaded successfully from iOS document picker")
            logDebug(.file, "Content length: \(content.count) characters")
            
            return content
        } catch {
            logError(.file, "❌ Failed to read file from iOS picker: \(error)")
            throw FileManagerError.loadFailed("Failed to read file: \(error.localizedDescription)")
        }
    }
#endif
    
    /**
     * Process selected file URL with detailed logging (macOS version)
     */
    #if os(macOS)
    private func processSelectedFile(_ url: URL) throws -> String {
        logInfo(.file, "📂 Processing selected file: \(url.lastPathComponent)")
        logDebug(.file, "File path: \(url.path)")
        logDebug(.file, "File extension: \(url.pathExtension)")
        
        do {
            // Check if file exists
            guard Foundation.FileManager.default.fileExists(atPath: url.path) else {
                logError(.file, "❌ File does not exist at path: \(url.path)")
                throw FileManagerError.fileNotFound(url.path)
            }
            
            // Check file size
            let attributes = try Foundation.FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? NSNumber {
                logDebug(.file, "File size: \(ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file))")
            }
            
            // Start accessing security-scoped resource
            logDebug(.file, "Starting security-scoped resource access")
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    logDebug(.file, "Stopping security-scoped resource access")
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if !accessing {
                logWarn(.file, "⚠️ Failed to start accessing security-scoped resource")
            }
            
            // Read file content
            logDebug(.file, "Reading file content")
            let content = try String(contentsOf: url, encoding: .utf8)
            
            logInfo(.file, "✅ File content read successfully")
            logDebug(.file, "Content length: \(content.count) characters")
            logInfo(.file, "Content preview:\n\(String(content.prefix(200)))...")
            
            // Update state on main thread
            currentFileURL = url
            currentFileContent = content
            isFileLoaded = true
            
            // Update recent files
            addToRecentFiles(url)
            
            return content
        } catch {
            logError(.file, "❌ Failed to process file: \(error)")
            throw FileManagerError.loadFailed("Failed to process file: \(error.localizedDescription)")
        }
    }
    #endif
    
    // MARK: - Auto-Load Default File
    
    /**
     * Attempt to auto-load the default file from canonical location
     */
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 CANONICAL: Searching for \(defaultFileName) in canonical location")
        
        let canonicalURL = getCanonicalFileURL()
        logDebug(.file, "Canonical location: \(canonicalURL.path)")
        
        // For iCloud files, we might need to download them first
        if let _ = iCloudDocumentsURL,
           canonicalURL.path.contains("Mobile Documents") {
            
            var isDownloaded = false
            do {
                let resourceValues = try canonicalURL.resourceValues(forKeys: [
                    .ubiquitousItemDownloadingStatusKey
                ])
                
                if let status = resourceValues.ubiquitousItemDownloadingStatus {
                    isDownloaded = (status == .current)
                }
            } catch {
                logDebug(.file, "Could not check iCloud download status: \(error)")
            }
            
            if !isDownloaded {
                logInfo(.file, "📥 Downloading file from iCloud...")
                do {
                    try Foundation.FileManager.default.startDownloadingUbiquitousItem(at: canonicalURL)
                    // Wait a moment for download to start
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                } catch {
                    logWarn(.file, "Failed to start iCloud download: \(error)")
                }
            }
        }
        
        await checkAndLoadFile(at: canonicalURL)
    }
    
    /**
     * Check and load file at given URL
     */
    private func checkAndLoadFile(at url: URL) async {
        logDebug(.file, "Checking canonical location: \(url.path)")
        
        if Foundation.FileManager.default.fileExists(atPath: url.path) {
            logInfo(.file, "✅ Found \(defaultFileName) in canonical location!")
            do {
                #if os(macOS)
                _ = try processSelectedFile(url)
                #else
                _ = try await processSelectedFileFromPicker(url)
                #endif
                
                logInfo(.file, "🎉 Successfully auto-loaded canonical file")
                
            } catch {
                logError(.file, "❌ Failed to auto-load file: \(error)")
            }
        } else {
            logInfo(.file, "📂 \(defaultFileName) not found in canonical location")
            logInfo(.file, "💡 Place your file at: iCloud Drive → Kalvian Roots → Documents → \(defaultFileName)")
            logInfo(.file, "💡 This file will then sync to all your devices automatically")
        }
    }
    
    // MARK: - Canonical Location Management
    
    /**
     * Get the ONE canonical file location
     * Returns: iCloud Drive/Kalvian Roots/Documents/JuuretKälviällä.roots
     */
    private func getCanonicalFileURL() -> URL {
        // Use iCloud Documents if available, otherwise fall back to local
        if let iCloudURL = iCloudDocumentsURL {
            // Create Documents directory in iCloud if it doesn't exist
            try? Foundation.FileManager.default.createDirectory(
                at: iCloudURL,
                withIntermediateDirectories: true
            )
            return iCloudURL.appendingPathComponent(defaultFileName)
        } else {
            // Fall back to local documents only if iCloud is unavailable
            let documentsURL = Foundation.FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!
            return documentsURL.appendingPathComponent(defaultFileName)
        }
    }
    
    // MARK: - Recent Files Management
    
    /**
     * Add file to recent files list
     */
    private func addToRecentFiles(_ url: URL) {
        // Remove if already exists to move to front
        recentFileURLs.removeAll { $0 == url }
        
        // Add to front
        recentFileURLs.insert(url, at: 0)
        
        // Keep only last 10
        if recentFileURLs.count > 10 {
            recentFileURLs = Array(recentFileURLs.prefix(10))
        }
        
        saveRecentFiles()
        logDebug(.file, "Added to recent files: \(url.lastPathComponent)")
    }
    
    /**
     * Load recent files from UserDefaults
     */
    private func loadRecentFiles() {
        if let bookmarks = UserDefaults.standard.array(forKey: "RecentFileBookmarks") as? [Data] {
            recentFileURLs = bookmarks.compactMap { data in
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: data,
                                     bookmarkDataIsStale: &isStale) {
                    return isStale ? nil : url
                }
                return nil
            }
            logDebug(.file, "Loaded \(recentFileURLs.count) recent files")
        }
    }
    
    /**
     * Save recent files to UserDefaults
     */
    private func saveRecentFiles() {
        let bookmarks = recentFileURLs.compactMap { url in
            try? url.bookmarkData(options: .minimalBookmark)
        }
        UserDefaults.standard.set(bookmarks, forKey: "RecentFileBookmarks")
        logTrace(.file, "Saved \(bookmarks.count) recent file bookmarks")
    }
    
    // MARK: - Text Extraction
    
    /**
     * Extract family text from the loaded file
     */
    func extractFamilyText(familyId: String) -> String? {
        guard let content = currentFileContent else {
            logWarn(.file, "No file content loaded")
            return nil
        }
        
        logInfo(.file, "🔍 Extracting text for family: \(familyId)")
        
        let lines = content.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var capturing = false
        let targetId = familyId.uppercased()
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if !capturing {
                // Look for family ID at start of line
                if trimmedLine.uppercased().hasPrefix(targetId) {
                    capturing = true
                    familyLines.append(line)
                    logDebug(.file, "Found family \(targetId) at line: \(trimmedLine.prefix(50))...")
                }
            } else {
                // Check if we've hit the next family
                if !trimmedLine.isEmpty &&
                   trimmedLine.first?.isUppercase == true &&
                   trimmedLine.contains(where: { $0.isNumber }) {
                    // This looks like a new family ID
                    let components = trimmedLine.components(separatedBy: .whitespaces)
                    if components.count >= 2 &&
                       components[1].contains(where: { $0.isNumber }) {
                        // Definitely a new family, stop capturing
                        break
                    }
                }
                familyLines.append(line)
            }
        }
        
        if familyLines.isEmpty {
            logWarn(.file, "Family \(familyId) not found in file")
            return nil
        }
        
        let familyText = familyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        logInfo(.file, "✅ Extracted family text: \(familyText.count) characters")
        logTrace(.file, "Preview: \(familyText.prefix(200))...")
        
        return familyText
    }
    
    // MARK: - File Status
    
    /**
     * Get current file status for UI display
     */
    func getFileStatus() -> FileStatus {
        return FileStatus(
            isLoaded: isFileLoaded,
            fileName: currentFileURL?.lastPathComponent,
            filePath: currentFileURL?.path,
            fileSize: getFileSize(),
            isDefaultFile: currentFileURL?.lastPathComponent == defaultFileName,
            isCanonicalLocation: currentFileURL == getCanonicalFileURL()
        )
    }
    
    /**
     * Get formatted file size
     */
    private func getFileSize() -> String? {
        guard let url = currentFileURL else { return nil }
        
        do {
            let attributes = try Foundation.FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
            }
        } catch {
            logWarn(.file, "⚠️ Failed to get file size: \(error)")
        }
        return nil
    }
    
    // MARK: - Helper Methods for UI
    
    /**
     * Get user-friendly instructions for finding canonical location
     */
    func getCanonicalLocationInstructions() -> [String] {
        if iCloudDocumentsURL != nil {
            return [
                "1. Open Files app on iPad/iPhone (or Finder on Mac)",
                "2. Tap/Click 'iCloud Drive'",
                "3. Look for 'Kalvian Roots' folder (will appear after first save)",
                "4. Place '\(defaultFileName)' in the Documents folder inside",
                "5. The file will sync to all your devices automatically"
            ]
        } else {
            return [
                "1. iCloud Drive is not available",
                "2. Using local storage instead",
                "3. Files won't sync between devices",
                "4. Consider enabling iCloud Drive for this app"
            ]
        }
    }
    
    /**
     * Check if iCloud Drive is available
     */
    func isiCloudDriveAvailable() -> Bool {
        #if os(macOS)
        let homeURL = Foundation.FileManager.default.homeDirectoryForCurrentUser
        let iCloudDriveDocuments = homeURL.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents")
        return Foundation.FileManager.default.fileExists(atPath: iCloudDriveDocuments.path)
        #else
        // iCloud Drive availability can't be checked via file path on iOS
        return Foundation.FileManager.default.ubiquityIdentityToken != nil
        #endif
    }
}

// MARK: - Supporting Data Structures

/**
 * File status information for UI
 */
struct FileStatus {
    let isLoaded: Bool
    let fileName: String?
    let filePath: String?
    let fileSize: String?
    let isDefaultFile: Bool
    let isCanonicalLocation: Bool
    
    var displayName: String {
        return fileName ?? "No file loaded"
    }
    
    var statusDescription: String {
        if isLoaded {
            var desc = "Loaded"
            if let size = fileSize {
                desc += " (\(size))"
            }
            if isDefaultFile && isCanonicalLocation {
                desc += " [Canonical]"
            } else if isDefaultFile {
                desc += " [Default]"
            }
            return desc
        } else {
            return "No file loaded"
        }
    }
    
    var locationDescription: String {
        guard isLoaded else { return "No file loaded" }
        
        if isCanonicalLocation {
            return "✅ Canonical location (syncs across devices)"
        } else {
            return "⚠️ Non-canonical location (device-specific)"
        }
    }
}

/**
 * File manager errors
 */
enum FileManagerError: LocalizedError {
    case userCancelled
    case accessDenied(String)
    case loadFailed(String)
    case invalidFileType
    case fileNotFound(String)
    case iCloudUnavailable
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "File selection cancelled"
        case .accessDenied(let reason):
            return "Access denied: \(reason)"
        case .loadFailed(let reason):
            return "Failed to load file: \(reason)"
        case .invalidFileType:
            return "Invalid file type"
        case .fileNotFound(let path):
            return "Fie not found: \(path)"
        case .iCloudUnavailable:
            return "iCloud Drive is not available"
        }
    }
}

// MARK: - Next Family Detection Extension

extension FileManager {
    
    /**
     * Find the next family ID after the given family in the file
     * Families are delimited by blank lines
     */
    func findNextFamilyId(after currentFamilyId: String) -> String? {
        guard let content = currentFileContent else {
            logWarn(.file, "No file content loaded")
            return nil
        }
        
        logInfo(.file, "🔎 Looking for next family after: \(currentFamilyId)")
        
        let lines = content.components(separatedBy: .newlines)
        var foundCurrent = false
        var passedBlankLine = false
        let targetId = currentFamilyId.uppercased()
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if !foundCurrent {
                // Look for current family ID at start of line
                if trimmedLine.uppercased().hasPrefix(targetId) {
                    foundCurrent = true
                    logDebug(.file, "Found current family at line \(index + 1): \(trimmedLine.prefix(50))...")
                }
            } else if foundCurrent && !passedBlankLine {
                // Wait for blank line (family delimiter)
                if trimmedLine.isEmpty {
                    passedBlankLine = true
                    logDebug(.file, "Passed blank line delimiter at line \(index + 1)")
                }
            } else if foundCurrent && passedBlankLine && !trimmedLine.isEmpty {
                // Look for next family ID pattern
                if let nextId = extractFamilyIdFromLine(trimmedLine) {
                    // Verify it's in our valid family IDs
                    if FamilyIDs.validFamilyIds.contains(nextId) {
                        logInfo(.file, "✅ Found next family: \(nextId)")
                        return nextId
                    } else {
                        logDebug(.file, "Found potential family ID '\(nextId)' but not in valid set")
                        // Continue looking - might be a note or something else
                    }
                }
            }
        }
        
        logInfo(.file, "📋 No next family found (end of file or no valid family after current)")
        return nil
    }
    
    /**
     * Extract family ID from a line like "KORPI 6, pages 105-106"
     * Returns just the family ID part: "KORPI 6"
     */
    private func extractFamilyIdFromLine(_ line: String) -> String? {
        // Pattern matches family IDs like: HYYPPÄ 6, ISO-KORPI 3, MAUNUMÄKI IV 5
        // Family ID = uppercase letters (possibly with hyphen) + space + number(s) or roman numerals + number(s)
        let pattern = #"^([A-ZÄÖÅ][A-ZÄÖÅ-]*(?:\s+(?:II|III|IV|V|VI))?\s+\d+[A-Z]?)"#
        
        if let range = line.range(of: pattern, options: .regularExpression) {
            let familyId = String(line[range])
            logTrace(.file, "Extracted potential family ID: '\(familyId)'")
            return familyId
        }
        
        return nil
    }
}
