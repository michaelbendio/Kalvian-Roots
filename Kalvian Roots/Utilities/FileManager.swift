//
//  FileManager.swift
//  Kalvian Roots
//
//  Canonical location file management - iCloud Drive ONLY, no fallback
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
 * NO FALLBACK - if iCloud is not available or file is not there, the app fails with clear error.
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
    
    /// Error message for UI display
    var errorMessage: String?
    
    /// The ONE canonical file name
    private let defaultFileName = "JuuretKälviällä.roots"
    
    var iCloudDocumentsURL: URL? {
        // Try specific container first, then default
        if let iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.michael-bendio.Kalvian-Roots") {
            return iCloudURL.appendingPathComponent("Documents")
        } else if let iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return iCloudURL.appendingPathComponent("Documents")
        }
        return nil
    }
        
    // MARK: - Initialization
    
    init() {
        loadRecentFiles()
        logInfo(.file, "📁 FileManager initialized - iCloud Drive ONLY mode")
    }
    
    // MARK: - File Operations
    
#if os(macOS)
    /**
     * Open file with system file picker (macOS)
     * Even with picker, we validate it's the canonical file
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
            panel.message = "Select your Juuret Kälviällä file (.roots, .txt, or any text file) from iCloud Drive"
            panel.prompt = "Open File"
            logDebug(.file, "NSOpenPanel configured, presenting modal dialog")
            let response = panel.runModal()
            logDebug(.file, "NSOpenPanel response: \(response == .OK ? "OK" : "Cancel")")
            if response == .OK, let url = panel.url {
                logInfo(.file, "✅ User selected file: \(url.lastPathComponent)")
                logDebug(.file, "Full path: \(url.path)")
                
                // Warn if not from canonical location
                if let canonicalURL = self.getCanonicalFileURL() {
                    if url != canonicalURL {
                        logWarn(.file, "⚠️ Selected file is not from canonical iCloud location")
                        logWarn(.file, "⚠️ Changes will not sync across devices")
                    }
                }
                
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
        
        // Warn if not from canonical location
        if let canonicalURL = self.getCanonicalFileURL() {
            if url != canonicalURL {
                logWarn(.file, "⚠️ Selected file is not from canonical iCloud location")
                logWarn(.file, "⚠️ Changes will not sync across devices")
            }
        }
        
        // The security-scoped resource access is handled in the View layer
        // Just read the content here
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Update state
            await MainActor.run {
                self.currentFileURL = url
                self.currentFileContent = content
                self.isFileLoaded = true
                self.errorMessage = nil
            }
            
            // Update recent files
            addToRecentFiles(url)
            
            logInfo(.file, "✅ File loaded successfully via document picker")
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
            logInfo(.file, "Content preview:\n\(String(content.prefix(15)))\n")
            
            // Update state on main thread
            currentFileURL = url
            currentFileContent = content
            isFileLoaded = true
            errorMessage = nil
            
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
     * NO FALLBACK - fails if file is not in iCloud Drive
     */
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 CANONICAL: Searching for \(defaultFileName) in iCloud Drive")
        
        // Debug: Check iCloud availability
        #if os(iOS)
        if let token = Foundation.FileManager.default.ubiquityIdentityToken {
            logInfo(.file, "✅ iCloud account is signed in (token exists)")
        } else {
            logError(.file, "❌ No iCloud account token - user may not be signed in")
        }
        #endif
        
        // Try to get iCloud container with the specific identifier from Xcode
        var iCloudURL: URL? = nil
        
        // Try the specific container first
        let specificIdentifier = "iCloud.com.michael-bendio.Kalvian-Roots"
        logDebug(.file, "Trying container identifier: \(specificIdentifier)")
        iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: specificIdentifier)
        
        if iCloudURL != nil {
            logInfo(.file, "✅ Found iCloud container with identifier: \(specificIdentifier)")
            logInfo(.file, "📁 Container path: \(iCloudURL!.path)")
        } else {
            logWarn(.file, "⚠️ Could not find container: \(specificIdentifier)")
            
            // Try default container as fallback
            logDebug(.file, "Trying default container (nil)")
            iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil)
            if iCloudURL != nil {
                logInfo(.file, "✅ Found iCloud container with default identifier")
                logInfo(.file, "📁 Container path: \(iCloudURL!.path)")
            } else {
                logWarn(.file, "⚠️ Could not find default container either")
            }
        }
        
        // Check if we found an iCloud container
        guard let iCloudURL = iCloudURL else {
            logError(.file, "❌ CRITICAL: iCloud Drive container not accessible")
            logError(.file, "❌ Possible causes:")
            logError(.file, "  1. App not properly signed (check Team ID in Xcode)")
            logError(.file, "  2. iCloud entitlements not configured correctly")
            logError(.file, "  3. iCloud Drive disabled in Settings")
            logError(.file, "  4. First run - container not yet created")
            logError(.file, "💡 Try: Build and run from Xcode to create container")
            
            // Set error state with detailed message
            await MainActor.run {
                self.errorMessage = """
                    Cannot access iCloud Drive container.
                    
                    Please ensure:
                    1. You're signed into iCloud
                    2. iCloud Drive is enabled in Settings
                    3. The app was built with proper signing
                    
                    If this is the first run, try building from Xcode.
                    """
            }
            return
        }
        
        let iCloudFileURL = iCloudURL
            .appendingPathComponent("Documents")
            .appendingPathComponent(defaultFileName)
        
        logDebug(.file, "Canonical iCloud location: \(iCloudFileURL.path)")
        
        // Check if file exists in iCloud
        var fileExistsInCloud = false
        var isDownloaded = false
        
        // Check file status in iCloud
        do {
            let resourceValues = try iCloudFileURL.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .isUbiquitousItemKey
            ])
            
            if let isUbiquitous = resourceValues.isUbiquitousItem {
                fileExistsInCloud = isUbiquitous
                logDebug(.file, "File exists in iCloud: \(isUbiquitous)")
            }
            
            if let downloadingStatus = resourceValues.ubiquitousItemDownloadingStatus {
                isDownloaded = (downloadingStatus == .current || downloadingStatus == .downloaded)
                logDebug(.file, "iCloud download status: \(downloadingStatus.rawValue)")
            }
        } catch {
            // File doesn't exist in iCloud yet
            logDebug(.file, "File not found in iCloud: \(error)")
        }
        
        // Check if file exists locally (may have been downloaded already)
        let fileExistsLocally = Foundation.FileManager.default.fileExists(atPath: iCloudFileURL.path)
        
        if fileExistsLocally || fileExistsInCloud {
            // File exists - download if needed
            if fileExistsInCloud && !isDownloaded {
                logInfo(.file, "📥 Downloading file from iCloud...")
                do {
                    try Foundation.FileManager.default.startDownloadingUbiquitousItem(at: iCloudFileURL)
                    // Wait for download
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                } catch {
                    logError(.file, "❌ Failed to download from iCloud: \(error)")
                    await MainActor.run {
                        self.errorMessage = "Failed to download file from iCloud: \(error.localizedDescription)"
                    }
                    return
                }
            }
            
            // Try to load the file
            await checkAndLoadFile(at: iCloudFileURL)
        } else {
            // File doesn't exist in iCloud - provide clear instructions
            logError(.file, "❌ \(defaultFileName) not found in iCloud Drive")
            logInfo(.file, "📱 On iOS/iPadOS:")
            logInfo(.file, "  1. Open Files app")
            logInfo(.file, "  2. Navigate to: iCloud Drive → Kalvian Roots → Documents")
            logInfo(.file, "  3. Place '\(defaultFileName)' there")
            logInfo(.file, "💻 On macOS:")
            logInfo(.file, "  1. Open Finder")
            logInfo(.file, "  2. Navigate to: iCloud Drive → Kalvian Roots → Documents")
            logInfo(.file, "  3. Place '\(defaultFileName)' there")
            logInfo(.file, "☁️ The file will sync automatically across all your devices")
            
            await MainActor.run {
                self.errorMessage = "File not found in iCloud Drive. Place '\(defaultFileName)' in iCloud Drive → Kalvian Roots → Documents"
            }
        }
    }
    
    /**
     * Check and load file at given URL
     * NO FALLBACK - only loads from the exact URL provided
     */
    private func checkAndLoadFile(at url: URL) async {
        logDebug(.file, "Attempting to load file from: \(url.path)")
        
        if Foundation.FileManager.default.fileExists(atPath: url.path) {
            logInfo(.file, "✅ Found \(defaultFileName) at canonical location!")
            do {
                #if os(macOS)
                _ = try processSelectedFile(url)
                #else
                _ = try await processSelectedFileFromPicker(url)
                #endif
                
                logInfo(.file, "🎉 Successfully loaded canonical file from iCloud Drive")
                
                // Clear any error state
                await MainActor.run {
                    self.errorMessage = nil
                }
            } catch {
                logError(.file, "❌ Failed to load file: \(error)")
                await MainActor.run {
                    self.errorMessage = "Failed to load file: \(error.localizedDescription)"
                }
            }
        } else {
            logError(.file, "❌ File does not exist at: \(url.path)")
            await MainActor.run {
                self.errorMessage = "File not found. Ensure '\(defaultFileName)' is in iCloud Drive → Kalvian Roots → Documents"
            }
        }
    }
    
    // MARK: - Canonical Location Management
    
    /**
     * Get the ONE canonical file location
     * Returns: iCloud Drive/Kalvian Roots/Documents/JuuretKälviällä.roots
     * NO FALLBACK - returns nil if iCloud is not available
     */
    func getCanonicalFileURL() -> URL? {
        // Try the specific container identifier first
        var iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.michael-bendio.Kalvian-Roots")
        
        // If specific container not found, try default
        if iCloudURL == nil {
            iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }
        
        guard let iCloudURL = iCloudURL else {
            logError(.file, "❌ iCloud Drive is not available - cannot access canonical location")
            return nil
        }
        
        let documentsURL = iCloudURL.appendingPathComponent("Documents")
        
        // Create Documents directory if it doesn't exist
        do {
            try Foundation.FileManager.default.createDirectory(
                at: documentsURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            logError(.file, "❌ Failed to create iCloud Documents directory: \(error)")
            return nil
        }
        
        return documentsURL.appendingPathComponent(defaultFileName)
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
                // Stop at blank line (family delimiter)
                if trimmedLine.isEmpty {
                    // Don't include the blank line itself
                    logDebug(.file, "Reached blank line delimiter - stopping extraction")
                    break
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
        let canonicalURL = getCanonicalFileURL()  // Now returns optional
        
        return FileStatus(
            isLoaded: isFileLoaded,
            fileName: currentFileURL?.lastPathComponent,
            filePath: currentFileURL?.path,
            fileSize: getFileSize(),
            isDefaultFile: currentFileURL?.lastPathComponent == defaultFileName,
            isCanonicalLocation: canonicalURL != nil && currentFileURL == canonicalURL
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
     * NO FALLBACK - only provides iCloud instructions
     */
    func getCanonicalLocationInstructions() -> [String] {
        if iCloudDocumentsURL != nil {
            return [
                "1. Open Files app on iPad/iPhone (or Finder on Mac)",
                "2. Navigate to 'iCloud Drive'",
                "3. Open or create 'Kalvian Roots' folder",
                "4. Open or create 'Documents' folder inside",
                "5. Place '\(defaultFileName)' in the Documents folder",
                "6. The file will sync to all your devices automatically"
            ]
        } else {
            return [
                "❌ iCloud Drive is not available",
                "This app requires iCloud Drive to access the canonical file",
                "Please enable iCloud Drive:",
                "  Settings → [Your Name] → iCloud → iCloud Drive",
                "Then restart the app"
            ]
        }
    }
    
    /**
     * Check if iCloud Drive is available
     */
    func isiCloudDriveAvailable() -> Bool {
        return Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
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
            return "File not found: \(path)"
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
        
        logDebug(.file, "🔍 Looking for next family after: \(currentFamilyId)")
        
        let lines = content.components(separatedBy: .newlines)
        var foundCurrent = false
        var passedBlankLine = false
        let targetId = currentFamilyId.uppercased()
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let upperLine = trimmedLine.uppercased()
            
            if !foundCurrent {
                // Look for current family
                if upperLine.hasPrefix(targetId) {
                    foundCurrent = true
                    logDebug(.file, "Found current family at: \(trimmedLine.prefix(50))...")
                }
            } else if !passedBlankLine {
                // Wait for blank line after current family
                if trimmedLine.isEmpty {
                    passedBlankLine = true
                    logDebug(.file, "Passed blank line after current family")
                }
            } else if passedBlankLine && !trimmedLine.isEmpty {
                // This should be the start of the next family
                // Extract the family ID (first word/token)
                let components = trimmedLine.split(separator: " ")
                if let firstComponent = components.first {
                    let nextId = String(firstComponent)
                    logInfo(.file, "✅ Found next family: \(nextId)")
                    return nextId
                }
            }
        }
        
        logInfo(.file, "📋 No next family found - reached end of file")
        return nil
    }
}
