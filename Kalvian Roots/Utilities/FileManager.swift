//
//  FileManager.swift
//  Kalvian Roots
//
//  Canonical location file management for cross-device sync
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/**
 * FileManager.swift - Canonical location file management
 *
 * Handles file operations with ONE canonical location: iCloud Drive/Documents/JuuretKälviällä.roots
 * This location works across Mac, iPad, iPhone and is easily user-accessible.
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
    
    /// The ONE canonical file name
    private let defaultFileName = "JuuretKälviällä.roots"
    
    // MARK: - Initialization
    
    init() {
        loadRecentFiles()
        logInfo(.file, "📁 FileManager initialized with canonical location strategy")
    }
    
    // MARK: - File Operations
    
    /**
     * Open file with system file picker
     */
    func openFile() async throws -> String {
        logInfo(.file, "🗂️ User requested file picker")
        
        return try await MainActor.run {
            logDebug(.file, "Creating file picker on main thread")
            
            // Create and configure the open panel on main thread
            let panel = NSOpenPanel()
            panel.title = "Open Juuret Kälviällä File"
            panel.allowedContentTypes = []  // Allow all file types for flexibility
            panel.allowsOtherFileTypes = true
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.message = "Select your Juuret Kälviällä file (.roots, .txt, or any text file)"
            panel.prompt = "Open File"
            
            logDebug(.file, "NSOpenPanel configured, presenting modal dialog")
            
            // Run modal synchronously on main thread
            let response = panel.runModal()
            
            logDebug(.file, "NSOpenPanel response: \(response == .OK ? "OK" : "Cancel")")
            
            if response == .OK {
                if let url = panel.url {
                    logInfo(.file, "✅ User selected file: \(url.lastPathComponent)")
                    logDebug(.file, "Full path: \(url.path)")
                    
                    // Process the file selection
                    return try self.processSelectedFile(url)
                } else {
                    logError(.file, "❌ NSOpenPanel returned OK but no URL")
                    throw FileManagerError.loadFailed("No file URL returned from picker")
                }
            } else {
                logInfo(.file, "User cancelled file selection")
                throw FileManagerError.userCancelled
            }
        }
    }
    
    /**
     * Process selected file URL with detailed logging
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
            logTrace(.file, "Content preview: \(String(content.prefix(200)))...")
            
            // Update state on main thread
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
    
    /**
     * Auto-load from CANONICAL location: iCloud Drive/Documents/JuuretKälviällä.roots
     * This is the ONE location that works across Mac, iPad, iPhone and is user-accessible
     */
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 CANONICAL: Searching for JuuretKälviällä.roots in canonical location")
        
        // The ONE canonical location: iCloud Drive/Documents/
        guard let canonicalURL = getCanonicalFileURL() else {
            logWarn(.file, "❌ Cannot access iCloud Drive/Documents")
            logInfo(.file, "💡 Make sure iCloud Drive is enabled in System Settings")
            return
        }
        
        logDebug(.file, "Checking canonical location: \(canonicalURL.path)")
        
        if Foundation.FileManager.default.fileExists(atPath: canonicalURL.path) {
            logInfo(.file, "✅ Found file in canonical location")
            
            do {
                _ = try await openFile(at: canonicalURL)
                logInfo(.file, "✅ Successfully auto-loaded from canonical location")
                return
            } catch {
                logError(.file, "❌ Failed to load from canonical location: \(error.localizedDescription)")
                return
            }
        }
        
        logInfo(.file, "📂 JuuretKälviällä.roots not found in canonical location")
        logInfo(.file, "💡 Place your file at: \(getCanonicalLocationPath())")
        logInfo(.file, "💡 This file will then sync to all your devices automatically")
    }
    
    // MARK: - Canonical Location Methods
    
    /**
     * Get the canonical file location: App's Documents folder (accessible via symlink from iCloud)
     * The app can only see its sandbox, but we create a symlink for user access
     */
    func getCanonicalFileURL() -> URL? {
        // The app can only access its sandboxed Documents folder
        guard let sandboxDocuments = Foundation.FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logError(.file, "❌ Cannot access app's Documents folder")
            return nil
        }
        
        let canonicalFile = sandboxDocuments.appendingPathComponent(defaultFileName)
        logDebug(.file, "Canonical location: \(canonicalFile.path)")
        
        return canonicalFile
    }
    
    /**
     * Get the current canonical location for UI display
     */
    func getCanonicalLocationPath() -> String {
        return "App Documents → JuuretKälviällä.roots (accessible via iCloud Drive symlink)"
    }
    
    /**
     * Get default file URL (canonical location if file exists)
     */
    func getDefaultFileURL() -> URL? {
        let canonicalURL = getCanonicalFileURL()
        
        if let canonicalURL = canonicalURL,
           Foundation.FileManager.default.fileExists(atPath: canonicalURL.path) {
            return canonicalURL
        }
        
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
            logError(.file, "❌ No file content available for family extraction")
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
            logError(.file, "❌ Family \(familyId) not found in file")
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
    
    // MARK: - File Status and Information
    
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
                isDefaultFile: url.lastPathComponent == defaultFileName,
                isCanonicalLocation: isCanonicalLocation(url)
            )
        } else {
            return FileStatus(
                isLoaded: false,
                fileName: nil,
                filePath: nil,
                fileSize: nil,
                isDefaultFile: false,
                isCanonicalLocation: false
            )
        }
    }
    
    /**
     * Check if URL is in canonical location
     */
    func isCanonicalLocation(_ url: URL) -> Bool {
        guard let canonicalURL = getCanonicalFileURL() else { return false }
        return url.path == canonicalURL.path
    }
    
    private func getFileSize(_ url: URL) -> String? {
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
        return [
            "1. Open Finder (Mac) or Files app (iPad/iPhone)",
            "2. Click 'iCloud Drive' in the sidebar",
            "3. Open the 'Documents' folder",
            "4. Place 'JuuretKälviällä.roots' here",
            "5. The file will sync to all your devices automatically"
        ]
    }
    
    /**
     * Check if iCloud Drive is available
     */
    func isiCloudDriveAvailable() -> Bool {
        let homeURL = Foundation.FileManager.default.homeDirectoryForCurrentUser
        let iCloudDriveDocuments = homeURL.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents")
        return Foundation.FileManager.default.fileExists(atPath: iCloudDriveDocuments.path)
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
        case .accessDenied(let path):
            return "Access denied to file: \(path)"
        case .loadFailed(let details):
            return "Failed to load file: \(details)"
        case .invalidFileType:
            return "Invalid file type. Please select a text file."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .iCloudUnavailable:
            return "iCloud Drive is not available. Please enable it in System Settings."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .iCloudUnavailable:
            return "Enable iCloud Drive in System Settings → Apple ID → iCloud → iCloud Drive"
        case .fileNotFound:
            return "Place JuuretKälviällä.roots in iCloud Drive/Documents/"
        default:
            return nil
        }
    }
}
