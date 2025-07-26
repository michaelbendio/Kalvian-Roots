//
//  FileManager.swift
//  Kalvian Roots
//
//  Complete enhanced file management with iCloud-first multi-device strategy
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/**
 * FileManager.swift - Enhanced macOS/iOS file management
 *
 * Multi-device file management with iCloud-first strategy for seamless
 * access across Mac, iPad, and iPhone with comprehensive debug logging.
 */

@Observable
class FileManager {
    
    // MARK: - Properties
    
    /// Current file state
    private(set) var currentFileURL: URL?
    private(set) var currentFileContent: String?
    private(set) var isFileLoaded: Bool = false
    
    /// Recent files management
    private(set) var recentFileURLs: [URL] = []
    
    /// Expected default file name
    private let defaultFileName = "JuuretKälviällä.roots"
    
    // MARK: - Initialization
    
    init() {
        loadRecentFiles()
        logInfo(.file, "📁 FileManager initialized with multi-device strategy")
    }
    
    // MARK: - File Operations (Enhanced with Multi-Device Support)
    
    /**
     * Open file with system file picker - Enhanced for all platforms
     */
    func openFile() async throws -> String {
        logInfo(.file, "🗂️ User requested file picker")
        
        return try await MainActor.run {
            logDebug(.file, "Creating file picker on main thread")
            
            #if os(macOS)
            // macOS: Use NSOpenPanel
            let panel = NSOpenPanel()
            panel.title = "Open Juuret Kälviällä File"
            panel.allowedContentTypes = []  // Allow all file types
            panel.allowsOtherFileTypes = true
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.message = "Select your Juuret Kälviällä file (.roots, .txt, or any text file)"
            panel.prompt = "Open File"
            
            logDebug(.file, "NSOpenPanel configured, presenting modal dialog")
            
            let response = panel.runModal()
            logDebug(.file, "NSOpenPanel response: \(response == .OK ? "OK" : "Cancel")")
            
            if response == .OK {
                if let url = panel.url {
                    logInfo(.file, "✅ User selected file: \(url.lastPathComponent)")
                    return try self.processSelectedFile(url)
                } else {
                    logError(.file, "❌ NSOpenPanel returned OK but no URL")
                    throw FileManagerError.loadFailed("No file URL returned from picker")
                }
            } else {
                logInfo(.file, "User cancelled file selection")
                throw FileManagerError.userCancelled
            }
            
            #else
            // iOS/iPadOS: Would use UIDocumentPickerViewController
            // For now, throw an error indicating manual picker not implemented
            logError(.file, "❌ Manual file picker not yet implemented on iOS/iPadOS")
            throw FileManagerError.loadFailed("Manual file picker not available on this platform. Use auto-loading or place file in iCloud Documents.")
            #endif
        }
    }
    
    /**
     * Process selected file URL with comprehensive error handling
     */
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
                
                // Warn about very small files
                if fileSize.int64Value < 1000 {
                    logWarn(.file, "⚠️ File is very small (\(fileSize.int64Value) bytes) - may not be the correct file")
                }
            }
            
            // Start accessing security-scoped resource (macOS sandbox)
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
            logTrace(.file, "Content preview: \(String(content.prefix(200)))...")
            
            // Update state
            currentFileURL = url
            currentFileContent = content
            isFileLoaded = true
            
            // Update recent files
            addToRecentFiles(url)
            
            logInfo(.file, "✅ File loaded successfully (\(content.count) characters)")
            return content
            
        } catch let error as FileManagerError {
            logError(.file, "❌ FileManager error: \(error.localizedDescription)")
            throw error
        } catch {
            logError(.file, "❌ Failed to load file: \(error.localizedDescription)")
            logDebug(.file, "Error type: \(type(of: error))")
            throw FileManagerError.loadFailed(error.localizedDescription)
        }
    }
    
    /**
     * Open specific file at URL
     */
    func openFile(at url: URL) async throws -> String {
        return try await MainActor.run {
            return try self.processSelectedFile(url)
        }
    }
    
    /**
     * Close current file
     */
    func closeFile() {
        currentFileURL = nil
        currentFileContent = nil
        isFileLoaded = false
        logInfo(.file, "📂 File closed")
    }
    
    // MARK: - Multi-Device Auto-Loading (iCloud First)
    
    /**
     * Auto-load default file from CANONICAL LOCATION ONLY
     * No fallbacks - enforces single source of truth
     */
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 CANONICAL: Searching for JuuretKälviällä.roots in single location")
        
        // Only check the canonical location
        guard let iCloudDocsURL = getiCloudDocumentsURL() else {
            logWarn(.file, "❌ Canonical location (iCloud Documents) not available")
            logInfo(.file, "💡 Enable iCloud Drive to access your canonical file")
            return
        }
        
        let targetFile = iCloudDocsURL.appendingPathComponent(defaultFileName)
        logDebug(.file, "Checking canonical location: \(targetFile.path)")
        
        // Check if file exists in canonical location
        let fileExists = Foundation.FileManager.default.fileExists(atPath: targetFile.path)
        logTrace(.file, "Canonical file exists: \(fileExists)")
        
        if fileExists {
            logInfo(.file, "✅ FOUND canonical file: \(targetFile.path)")
            
            // Prepare iCloud file if needed
            logDebug(.file, "Preparing canonical iCloud file for reading")
            await prepareFileForReading(at: targetFile)
            
            // Check if file is accessible
            if !isFileAccessible(at: targetFile) {
                logWarn(.file, "⚠️ Canonical file exists but not accessible")
                return
            }
            
            // Try to read the canonical file
            do {
                // Check file size first
                let attributes = try Foundation.FileManager.default.attributesOfItem(atPath: targetFile.path)
                if let fileSize = attributes[.size] as? NSNumber {
                    logDebug(.file, "Canonical file size: \(ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file))")
                    
                    // Validate file size
                    if fileSize.int64Value < 1000 {
                        logWarn(.file, "⚠️ Canonical file too small (\(fileSize.int64Value) bytes) - may be corrupted")
                        return
                    }
                }
                
                // Load the canonical file
                _ = try await openFile(at: targetFile)
                logInfo(.file, "🎉 SUCCESS: Loaded canonical file from iCloud Documents")
                logInfo(.file, "✅ Multi-device access enabled via canonical iCloud location")
                
            } catch {
                logWarn(.file, "⚠️ Found canonical file but couldn't read it: \(error.localizedDescription)")
            }
        } else {
            // File not found in canonical location
            logInfo(.file, "📂 JuuretKälviällä.roots not found in canonical location")
            logInfo(.file, "💡 Place your file in: iCloud Drive/Documents/JuuretKälviällä.roots")
            logInfo(.file, "💡 This is the ONLY location the app will check")
        }
    }
    
    /**
     * Get all possible search locations - SINGLE CANONICAL FILE VERSION
     * Only searches for the canonical file in iCloud Documents - no fallbacks
     */
    private func getAllPossibleSearchLocations() -> [(String, URL)] {
        var locations: [(String, URL)] = []
        
        // ONLY LOCATION: iCloud Documents (canonical file location)
        if let iCloudURL = getiCloudDocumentsURL() {
            locations.append(("iCloud Documents", iCloudURL))
            logTrace(.file, "Canonical location: \(iCloudURL.path)")
        } else {
            logWarn(.file, "⚠️ iCloud Documents not available - enable iCloud Drive for file access")
        }
        
        logDebug(.file, "Single canonical location configured")
        return locations
    }
    
    /**
     * Enhanced iCloud Documents URL detection - YOUR APP'S CONTAINER ONLY
     * Returns the canonical file location in your app's iCloud container
     */
    private func getiCloudDocumentsURL() -> URL? {
        logTrace(.file, "Checking for app's iCloud Documents container")
        
        // Access your app's iCloud container (not Apple's system container)
        guard let iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            logDebug(.file, "❌ App's iCloud container not available - iCloud Drive may be disabled")
            return nil
        }
        
        let documentsURL = iCloudURL.appendingPathComponent("Documents")
        logTrace(.file, "App's iCloud Documents URL: \(documentsURL.path)")
        
        // Verify/create the Documents folder in your app's container
        var isDirectory: ObjCBool = false
        let exists = Foundation.FileManager.default.fileExists(atPath: documentsURL.path, isDirectory: &isDirectory)
        
        if exists && isDirectory.boolValue {
            logDebug(.file, "✅ App's iCloud Documents folder verified")
            return documentsURL
        } else {
            logDebug(.file, "⚠️ App's iCloud Documents folder not found - creating it")
            
            // Create the Documents folder in your app's container
            do {
                try Foundation.FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
                logInfo(.file, "✅ Created Documents folder in app's iCloud container")
                return documentsURL
            } catch {
                logWarn(.file, "❌ Failed to create Documents folder in app's container: \(error)")
                return nil
            }
        }
    }
    
    /**
     * Get main user-friendly iCloud Documents URL - REMOVED
     * We can only access our app's container, not Apple's system container
     */
    private func getMainiCloudDocumentsURL() -> URL? {
        // This method is no longer used since we can't access Apple's system container
        return nil
    }
    
    /**
     * Check if file is accessible and readable
     */
    private func isFileAccessible(at url: URL) -> Bool {
        do {
            let attributes = try Foundation.FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? NSNumber {
                let accessible = fileSize.int64Value > 0
                logTrace(.file, "File accessibility check: \(accessible) (size: \(fileSize.int64Value) bytes)")
                return accessible
            }
            return true
        } catch {
            logTrace(.file, "File not accessible: \(error)")
            return false
        }
    }
    
    /**
     * Prepare file for reading (simplified for iCloud compatibility)
     */
    private func prepareFileForReading(at url: URL) async {
        // For iCloud files, try to ensure they're available
        if url.path.contains("Library/Mobile Documents") || url.path.contains("iCloud") {
            logDebug(.file, "Detected iCloud file path - attempting to ensure availability")
            
            do {
                // Try to start downloading if it's an iCloud file
                try Foundation.FileManager.default.startDownloadingUbiquitousItem(at: url)
                
                // Give it a moment to start downloading
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                logDebug(.file, "iCloud file preparation completed")
            } catch {
                logTrace(.file, "Could not prepare iCloud file (may already be available): \(error)")
            }
        }
    }
    
    // MARK: - Default File Detection
    
    /**
     * Get URL for default file with iCloud priority
     */
    func getDefaultFileURL() -> URL? {
        let searchLocations = getAllPossibleSearchLocations()
        
        for (locationName, url) in searchLocations {
            let defaultFile = url.appendingPathComponent(defaultFileName)
            if Foundation.FileManager.default.fileExists(atPath: defaultFile.path) {
                logDebug(.file, "Found default file in \(locationName): \(defaultFile.path)")
                return defaultFile
            }
        }
        
        logDebug(.file, "Default file not found in any location")
        return nil
    }
    
    // MARK: - Recent Files Management
    
    /**
     * Add file to recent files list
     */
    func addToRecentFiles(_ url: URL) {
        // Remove if already exists
        recentFileURLs.removeAll { $0.path == url.path }
        
        // Add to beginning
        recentFileURLs.insert(url, at: 0)
        
        // Limit to 10 recent files
        if recentFileURLs.count > 10 {
            recentFileURLs = Array(recentFileURLs.prefix(10))
        }
        
        saveRecentFiles()
        logDebug(.file, "📋 Added to recent files: \(url.lastPathComponent)")
    }
    
    /**
     * Clear recent files list
     */
    func clearRecentFiles() {
        recentFileURLs.removeAll()
        saveRecentFiles()
        logInfo(.file, "🗑️ Cleared recent files")
    }
    
    /**
     * Get valid recent files (filter out non-existent files)
     */
    func getValidRecentFiles() -> [URL] {
        return recentFileURLs.filter { url in
            Foundation.FileManager.default.fileExists(atPath: url.path)
        }
    }
    
    // MARK: - Family Text Extraction
    
    /**
     * Extract specific family text from current file content
     */
    func extractFamilyText(familyId: String) -> String? {
        guard let content = currentFileContent else {
            logWarn(.file, "❌ No file content available for family text extraction")
            return nil
        }
        
        return extractFamilyText(familyId: familyId, from: content)
    }
    
    /**
     * Extract family text from given content
     */
    func extractFamilyText(familyId: String, from content: String) -> String? {
        logDebug(.file, "📄 Extracting family text for: \(familyId)")
        
        let lines = content.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inTargetFamily = false
        var foundFamily = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for family header (case-insensitive)
            if let currentFamilyId = extractFamilyIdFromHeader(trimmedLine) {
                if currentFamilyId.uppercased() == familyId.uppercased() {
                    inTargetFamily = true
                    foundFamily = true
                    familyLines.append(line)
                } else if inTargetFamily {
                    // Started a new family, stop collecting
                    break
                } else {
                    inTargetFamily = false
                }
            } else if inTargetFamily {
                familyLines.append(line)
                
                // Stop at empty line after sufficient content
                if trimmedLine.isEmpty && familyLines.count > 3 {
                    let content = familyLines.joined(separator: "\n")
                    if content.contains("Lapset") || content.contains("★") {
                        break
                    }
                }
            }
        }
        
        guard foundFamily else {
            logWarn(.file, "❌ Family \(familyId) not found in file")
            return nil
        }
        
        let familyText = familyLines.joined(separator: "\n")
        logInfo(.file, "✅ Extracted family text for \(familyId) (\(familyText.count) characters)")
        return familyText
    }
    
    /**
     * Extract family ID from header line
     */
    private func extractFamilyIdFromHeader(_ line: String) -> String? {
        // Pattern for "FAMILY_NAME NUMBER" optionally followed by page info
        let pattern = #"^([A-ZÄÖÅ-]+(?:\s+[IVX]+)?\s+\d+[A-Z]?)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        
        let matchRange = Range(match.range(at: 1), in: line)!
        return String(line[matchRange])
    }
    
    // MARK: - Debug and Testing Methods
    
    /**
     * Manual file search for debugging
     */
    func searchForFileManually() -> [(String, Bool, String?)] {
        logInfo(.file, "🔍 Manual file search initiated")
        
        let searchLocations = getAllPossibleSearchLocations()
        var results: [(String, Bool, String?)] = []
        
        for (locationName, url) in searchLocations {
            let targetFile = url.appendingPathComponent(defaultFileName)
            let exists = Foundation.FileManager.default.fileExists(atPath: targetFile.path)
            
            var fileInfo: String? = nil
            if exists {
                do {
                    let attributes = try Foundation.FileManager.default.attributesOfItem(atPath: targetFile.path)
                    if let fileSize = attributes[.size] as? NSNumber {
                        fileInfo = ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file)
                    }
                } catch {
                    fileInfo = "Error reading file info"
                }
            }
            
            results.append((locationName, exists, fileInfo))
            logDebug(.file, "\(locationName): \(exists ? "FOUND" : "not found") \(fileInfo ?? "")")
        }
        
        logInfo(.file, "Manual search complete - found \(results.filter { $0.1 }.count) files")
        return results
    }
    
    /**
     * Force reload attempt - for UI debugging
     */
    func forceReloadFile() async -> Bool {
        logInfo(.file, "🔄 Force reload initiated")
        
        // Clear current state
        closeFile()
        
        // Try auto-load again
        await autoLoadDefaultFile()
        
        let success = isFileLoaded
        logInfo(.file, "Force reload \(success ? "SUCCESS" : "FAILED")")
        return success
    }
    
    // MARK: - File Status
    
    /**
     * Get current file status for UI display
     */
    func getFileStatus() -> FileStatus {
        if let url = currentFileURL {
            return FileStatus(
                isLoaded: true,
                fileName: url.lastPathComponent,
                filePath: url.path,
                fileSize: getFileSize(url),
                isDefaultFile: url.lastPathComponent == defaultFileName
            )
        } else {
            return FileStatus(
                isLoaded: false,
                fileName: nil,
                filePath: nil,
                fileSize: nil,
                isDefaultFile: false
            )
        }
    }
    
    private func getFileSize(_ url: URL) -> String? {
        do {
            let attributes = try Foundation.FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
            }
        } catch {
            logTrace(.file, "⚠️ Failed to get file size: \(error)")
        }
        return nil
    }
    
    // MARK: - Persistence
    
    private func saveRecentFiles() {
        let paths = recentFileURLs.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "RecentFiles")
    }
    
    private func loadRecentFiles() {
        guard let paths = UserDefaults.standard.array(forKey: "RecentFiles") as? [String] else {
            return
        }
        
        recentFileURLs = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return Foundation.FileManager.default.fileExists(atPath: path) ? url : nil
        }
        
        logDebug(.file, "📋 Loaded \(recentFileURLs.count) recent files")
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
    
    var displayName: String {
        return fileName ?? "No file loaded"
    }
    
    var statusDescription: String {
        if isLoaded {
            var desc = "Loaded"
            if let size = fileSize {
                desc += " (\(size))"
            }
            if isDefaultFile {
                desc += " [Default]"
            }
            return desc
        } else {
            return "No file loaded"
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
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "File selection cancelled"
        case .accessDenied(let path):
            return "Access denied to file: \(path)"
        case .loadFailed(let details):
            return "Failed to load file: \(details)"
        case .invalidFileType:
            return "Invalid file type. Please select a text file."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
