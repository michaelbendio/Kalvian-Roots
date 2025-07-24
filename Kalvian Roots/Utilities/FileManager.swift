//
//  FileManager.swift
//  Kalvian Roots
//
//  Standard macOS file management with iCloud integration
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/**
 * FileManager.swift - Standard macOS file management
 *
 * Handles file operations following Apple's Human Interface Guidelines.
 * Supports automatic loading from iCloud Documents and standard File menu integration.
 */

@Observable
class JuuretFileManager {
    
    // MARK: - Properties
    
    /// Current file state
    private(set) var currentFileURL: URL?
    private(set) var currentFileContent: String?
    private(set) var isFileLoaded: Bool = false
    
    /// Recent files management
    private(set) var recentFileURLs: [URL] = []
    
    /// Expected default file name
    private let defaultFileName = "JuuretKälviällä.txt"
    
    // MARK: - Initialization
    
    init() {
        loadRecentFiles()
        print("📁 JuuretFileManager initialized")
    }
    
    // MARK: - File Operations
    
    /**
     * Open file with system file picker
     */
    func openFile() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.title = "Open Juuret Kälviällä File"
                panel.allowedContentTypes = [.plainText]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        Task {
                            do {
                                let content = try await self.openFile(at: url)
                                continuation.resume(returning: content)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        continuation.resume(throwing: FileManagerError.userCancelled)
                    }
                }
            }
        }
    }
    
    /**
     * Open specific file at URL
     */
    func openFile(at url: URL) async throws -> String {
        print("📂 Opening file: \(url.lastPathComponent)")
        
        do {
            // Check file accessibility
            guard url.startAccessingSecurityScopedResource() else {
                throw FileManagerError.accessDenied(url.path)
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Read file content
            let content = try String(contentsOf: url, encoding: .utf8)
            
            await MainActor.run {
                currentFileURL = url
                currentFileContent = content
                isFileLoaded = true
            }
            
            // Update recent files
            addToRecentFiles(url)
            
            print("✅ File loaded successfully (\(content.count) characters)")
            return content
            
        } catch {
            print("❌ Failed to load file: \(error)")
            throw FileManagerError.loadFailed(error.localizedDescription)
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
     * Auto-load default file from iCloud Documents
     */
    func autoLoadDefaultFile() async {
        logDebug(.file, "🔍 Searching for default file...")
        
        guard let defaultURL = getDefaultFileURL() else {
            logInfo(.file, "📂 Default file not found - user will need to select manually")
            return
        }
        
        // Check if we can access the file (sandbox permissions)
        if Foundation.FileManager.default.fileExists(atPath: defaultURL.path) {
            logDebug(.file, "📂 Default file found at: \(defaultURL.path)")
            
            // Try to access the file
            do {
                _ = try await openFile(at: defaultURL)
                logInfo(.file, "✅ Auto-loaded default file successfully")
            } catch {
                logWarn(.file, "⚠️ Default file found but access failed: \(error.localizedDescription)")
                logInfo(.file, "💡 User will need to manually grant access via 'Open File' button")
                
                // Set a helpful error message for the UI
                await MainActor.run {
                    // We could set an error state here if needed
                }
            }
        } else {
            logDebug(.file, "📂 Default file not found at expected location")
        }
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
