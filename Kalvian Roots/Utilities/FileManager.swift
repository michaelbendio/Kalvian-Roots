//
//  FileManager.swift
//  Kalvian Roots
//
//  Fixed file management with proper NSOpenPanel implementation
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/**
 * FileManager.swift - Fixed macOS file management
 *
 * Handles file operations following Apple's Human Interface Guidelines.
 * Fixed NSOpenPanel implementation for sandbox compatibility.
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
        print("📁 FileManager initialized")
    }
    
    // MARK: - File Operations (ENHANCED with Debug Logging)
    
    /**
     * Open file with system file picker - ENHANCED VERSION with detailed logging
     */
    func openFile() async throws -> String {
        logInfo(.file, "🗂️ ENHANCED: User requested file picker")
        
        return try await MainActor.run {
            logDebug(.file, "Creating NSOpenPanel on main thread")
            
            // Create and configure the open panel on main thread
            let panel = NSOpenPanel()
            panel.title = "Open Juuret Kälviällä File"
            // FIXED: Allow .roots files specifically
            panel.allowedContentTypes = []  // Allow all file types
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
     * Process selected file URL - ENHANCED with detailed logging
     */
    private func processSelectedFile(_ url: URL) throws -> String {
        logInfo(.file, "📂 ENHANCED: Processing selected file: \(url.lastPathComponent)")
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
        print("📂 File closed")
    }
    
    /**
     * Auto-load default file from iCloud Documents - SIMPLIFIED for silent loading
     */
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 Silently searching for JuuretKälviällä.roots")
        
        // Check Local Documents FIRST (where the file actually is)
        if let documentsURL = Foundation.FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let targetFile = documentsURL.appendingPathComponent(defaultFileName)
            logDebug(.file, "Checking Local Documents: \(targetFile.path)")
            
            if Foundation.FileManager.default.fileExists(atPath: targetFile.path) {
                logInfo(.file, "✅ Found file in Local Documents: \(targetFile.path)")
                
                do {
                    _ = try await openFile(at: targetFile)
                    logInfo(.file, "✅ Successfully auto-loaded file from Local Documents")
                    return
                } catch {
                    logWarn(.file, "⚠️ Found file but couldn't read it: \(error.localizedDescription)")
                    return
                }
            } else {
                logDebug(.file, "File not found in Local Documents")
            }
        }
        
        // Then check iCloud Documents
        if let iCloudURL = getiCloudDocumentsURL() {
            let targetFile = iCloudURL.appendingPathComponent(defaultFileName)
            logDebug(.file, "Checking iCloud Documents: \(targetFile.path)")
            
            if Foundation.FileManager.default.fileExists(atPath: targetFile.path) {
                logInfo(.file, "✅ Found file in iCloud Documents: \(targetFile.path)")
                
                do {
                    _ = try await openFile(at: targetFile)
                    logInfo(.file, "✅ Successfully auto-loaded file from iCloud Documents")
                    return
                } catch {
                    logWarn(.file, "⚠️ Found file but couldn't read it: \(error.localizedDescription)")
                    return
                }
            } else {
                logDebug(.file, "File not found in iCloud Documents")
            }
        } else {
            logDebug(.file, "iCloud Documents not available")
        }
        
        // Fallback: Check other common locations
        let fallbackPaths = [
            ("Desktop", Foundation.FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first),
            ("Downloads", Foundation.FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        ]
        
        for (location, baseURL) in fallbackPaths {
            guard let baseURL = baseURL else { continue }
            let targetFile = baseURL.appendingPathComponent(defaultFileName)
            
            if Foundation.FileManager.default.fileExists(atPath: targetFile.path) {
                logInfo(.file, "✅ Found file in \(location): \(targetFile.path)")
                
                do {
                    _ = try await openFile(at: targetFile)
                    logInfo(.file, "✅ Successfully auto-loaded file from \(location)")
                    return
                } catch {
                    logWarn(.file, "⚠️ Found file in \(location) but couldn't read it: \(error.localizedDescription)")
                    return
                }
            }
        }
        
        logInfo(.file, "📂 JuuretKälviällä.roots not found in any location")
    }
    
    /**
     * Get all possible file paths for comprehensive search
     */
    private func getAllPossibleFilePaths() -> [(String, URL)] {
        var paths: [(String, URL)] = []
        
        // 1. iCloud Documents
        if let iCloudURL = getiCloudDocumentsURL() {
            let iCloudFile = iCloudURL.appendingPathComponent(defaultFileName)
            paths.append(("iCloud Documents", iCloudFile))
        }
        
        // 2. Local Documents
        if let documentsURL = Foundation.FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localFile = documentsURL.appendingPathComponent(defaultFileName)
            paths.append(("Local Documents", localFile))
        }
        
        // 3. Desktop
        if let desktopURL = Foundation.FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            let desktopFile = desktopURL.appendingPathComponent(defaultFileName)
            paths.append(("Desktop", desktopFile))
        }
        
        // 4. Downloads
        if let downloadsURL = Foundation.FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let downloadsFile = downloadsURL.appendingPathComponent(defaultFileName)
            paths.append(("Downloads", downloadsFile))
        }
        
        // 5. Home directory
        let homeURL = Foundation.FileManager.default.homeDirectoryForCurrentUser
        let homeFile = homeURL.appendingPathComponent(defaultFileName)
        paths.append(("Home Directory", homeFile))
        
        return paths
    }

    // MARK: - Default File Detection
    
    /**
     * Get URL for default file in iCloud Documents
     */
    func getDefaultFileURL() -> URL? {
        // Try iCloud Documents first
        if let iCloudURL = getiCloudDocumentsURL() {
            let defaultFile = iCloudURL.appendingPathComponent(defaultFileName)
            if Foundation.FileManager.default.fileExists(atPath: defaultFile.path) {
                return defaultFile
            }
        }
        
        // Fallback to local Documents
        let documentsURL = Foundation.FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsURL = documentsURL {
            let defaultFile = documentsURL.appendingPathComponent(defaultFileName)
            if Foundation.FileManager.default.fileExists(atPath: defaultFile.path) {
                return defaultFile
            }
        }
        
        return nil
    }
    
    /**
     * Get iCloud Documents URL if available
     */
    private func getiCloudDocumentsURL() -> URL? {
        guard let iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return iCloudURL.appendingPathComponent("Documents")
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
        print("📋 Added to recent files: \(url.lastPathComponent)")
    }
    
    /**
     * Clear recent files list
     */
    func clearRecentFiles() {
        recentFileURLs.removeAll()
        saveRecentFiles()
        print("🗑️ Cleared recent files")
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
            print("❌ No file content available")
            return nil
        }
        
        return extractFamilyText(familyId: familyId, from: content)
    }
    
    /**
     * Extract family text from given content
     */
    func extractFamilyText(familyId: String, from content: String) -> String? {
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
            print("❌ Family \(familyId) not found in file")
            return nil
        }
        
        let familyText = familyLines.joined(separator: "\n")
        print("📄 Extracted family text for \(familyId) (\(familyText.count) characters)")
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
        
        print("📋 Loaded \(recentFileURLs.count) recent files")
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
            print("⚠️ Failed to get file size: \(error)")
        }
        return nil
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
