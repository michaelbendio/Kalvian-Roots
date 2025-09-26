//
//  RootsFileManager.swift
//  Kalvian Roots
//
//  Canonical location file management - iCloud Drive ONLY, no fallback
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// Custom error types for file operations
enum RootsFileManagerError: LocalizedError {
    case iCloudNotAvailable
    case fileNotFound(String)
    case wrongFile(String)
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Drive is not available. Please enable iCloud Drive in Settings."
        case .fileNotFound(let details):
            return "File not found: \(details)"
        case .wrongFile(let details):
            return "Wrong file location: \(details)"
        case .loadFailed(let details):
            return "Failed to load file: \(details)"
        }
    }
}

/// Avoid name collision with Foundation.FileManager
@Observable
final class RootsFileManager {

    // MARK: - Public state (iOS UI can set these)
    #if os(iOS)
    var currentFileURL: URL?
    var currentFileContent: String?
    var isFileLoaded: Bool = false
    #else
    private(set) var currentFileURL: URL?
    private(set) var currentFileContent: String?
    private(set) var isFileLoaded: Bool = false
    #endif

    private(set) var recentFileURLs: [URL] = []
    var errorMessage: String?

    /// The ONE canonical file name (normalize at comparison time)
    private let defaultFileName = "JuuretKälviällä.roots"

    // MARK: - Init
    
    init() {
        loadRecentFiles()
        logInfo(.file, "📁 RootsFileManager initialized (iCloud default container)")
    }

    // MARK: - Canonical iCloud Locations

    /// The app's iCloud container root. (This *is* the "Kalvian Roots" folder in iCloud Drive.)
    private func containerURL() -> URL? {
        Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    /// The canonical folder where the file lives: <container>/Documents
    private func documentsURL() -> URL? {
        guard let root = containerURL() else { return nil }
        return root.appendingPathComponent("Documents", isDirectory: true)
    }

    /// Canonical file URL (<container>/Documents/JuuretKälviällä.roots)
    func getCanonicalFileURL() -> URL? {
        guard let docsURL = documentsURL() else { return nil }
        return docsURL.appendingPathComponent(defaultFileName)
    }

    // MARK: - Loading methods

    /// Auto-load the canonical file (should always succeed)
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 Auto-loading from canonical location")
        
        guard let canonicalURL = getCanonicalFileURL() else {
            await MainActor.run {
                self.errorMessage = "iCloud Drive not available"
            }
            logError(.file, "❌ iCloud container not available")
            return
        }
        
        logInfo(.file, "📂 Canonical location: \(canonicalURL.path)")
        
        do {
            _ = try await loadFile(from: canonicalURL)
            logInfo(.file, "✅ Auto-loaded successfully from canonical location")
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            logError(.file, "❌ Auto-load failed: \(error)")
        }
    }

    /// Load from a specific URL (validates it's the canonical file)
    func loadFile(from url: URL) async throws -> String {
        logInfo(.file, "📂 Attempting to load file from: \(url.path)")
        
        // Ensure it's the canonical file
        guard let canonicalURL = getCanonicalFileURL() else {
            throw RootsFileManagerError.iCloudNotAvailable
        }
        
        // Normalize paths for comparison
        let selectedPath = url.standardizedFileURL.path
        let canonicalPath = canonicalURL.standardizedFileURL.path
        
        guard selectedPath == canonicalPath else {
            throw RootsFileManagerError.wrongFile("""
                Expected: \(canonicalURL.path)
                Selected: \(url.path)
                
                Please use the file from the Kalvian Roots folder in iCloud Drive.
                """)
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Validate canonical marker
            guard validateCanonicalMarker(in: content) else {
                throw RootsFileManagerError.loadFailed("""
                    FATAL: Missing canonical marker.
                    The first line must be "canonical"
                    """)
            }
            
            await MainActor.run {
                self.currentFileURL = url
                self.currentFileContent = content
                self.isFileLoaded = true
                self.errorMessage = nil
            }
            
            addToRecentFiles(url)
            logInfo(.file, "✅ File loaded successfully")
            return content
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isFileLoaded = false
            }
            throw RootsFileManagerError.loadFailed(error.localizedDescription)
        }
    }

    /// Validate the canonical marker
    private func validateCanonicalMarker(in content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines)
        guard let firstLine = lines.first else { return false }
        let normalized = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "canonical"
    }

    /// Clear the currently loaded file
    func clearFile() {
        currentFileURL = nil
        currentFileContent = nil
        isFileLoaded = false
        errorMessage = nil
        logInfo(.file, "🗑️ Cleared loaded file")
    }

    // MARK: - macOS File Picker
    
    #if os(macOS)
    /// Show file picker on macOS (validates canonical location)
    @MainActor
    func showFilePicker() async throws {
        let panel = NSOpenPanel()
        panel.title = "Select JuuretKälviällä.roots from iCloud Drive"
        panel.message = "Please select the file from the Kalvian Roots folder in iCloud Drive"
        panel.prompt = "Select"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "roots") ?? .plainText]
        
        // Set initial directory to canonical location
        if let canonicalURL = getCanonicalFileURL() {
            panel.directoryURL = canonicalURL.deletingLastPathComponent()
        }
        
        let response = await panel.begin()
        
        if response == .OK, let url = panel.url {
            _ = try await loadFile(from: url)
        }
    }
    #endif

    // MARK: - iOS File Loading
    
    #if os(iOS)
    /// iOS-specific file loading (called from DocumentPicker)
    func loadFileFromPicker(_ url: URL) async throws -> String {
        logInfo(.file, "📱 iOS: Loading file from picker")
        
        guard let canonicalURL = getCanonicalFileURL() else {
            throw RootsFileManagerError.iCloudNotAvailable
        }
        
        // On iOS, the picker might give us a security-scoped URL
        // We need to access it and validate it's the right file
        let selectedPath = url.standardizedFileURL.path
        let canonicalPath = canonicalURL.standardizedFileURL.path
        
        // Check if paths match (they might not due to security scoping)
        if selectedPath != canonicalPath {
            logWarn(.file, """
                ⚠️ Path mismatch (may be OK on iOS):
                Selected: \(selectedPath)
                Canonical: \(canonicalPath)
                """)
        }
        
        // Validate filename at least
        guard url.lastPathComponent == defaultFileName else {
            throw RootsFileManagerError.wrongFile("""
                Expected: \(canonicalURL.path)
                Selected: \(url.path)
                
                Please use the file from the Kalvian Roots folder in iCloud Drive.
                """)
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Validate canonical marker
            guard validateCanonicalMarker(in: content) else {
                throw RootsFileManagerError.loadFailed("""
                    FATAL: Missing canonical marker.
                    The first line must be "canonical"
                    """)
            }
            
            await MainActor.run {
                self.currentFileURL = url
                self.currentFileContent = content
                self.isFileLoaded = true
                self.errorMessage = nil
            }
            addToRecentFiles(url)
            logInfo(.file, "✅ File loaded via iOS picker")
            return content
        } catch {
            throw RootsFileManagerError.loadFailed("Failed to read file: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Family ID Methods

    /**
     * Get all family IDs in file order
     */
    func getAllFamilyIds() -> [String] {
        // FamilyIDs is now ordered exactly as families appear in the file
        // So we just return it directly - no parsing needed!
        logDebug(.file, "✨ Using FamilyIDs as gold standard (\(FamilyIDs.count) families)")
        return FamilyIDs.validFamilyIds
    }

    /**
     * Extract family text for a specific family ID
     */
    func extractFamilyText(familyId: String) -> String? {
        guard FamilyIDs.isValid(familyId: familyId) else {
            logWarn(.file, "⚠️ Invalid family ID: \(familyId)")
            return nil
        }
        
        guard let content = currentFileContent else {
            logError(.file, "❌ No file content loaded")
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
        var out = [String]()
        var found = false
        var previousWasBlank = false
        
        let contentLines = Array(lines.dropFirst(2)) // Skip canonical marker and blank line
        
        for line in contentLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed == "#" {
                continue // Skip bookmarks
            }
            
            let isBlank = trimmed.isEmpty
            
            if !found {
                // Looking for our target family
                if trimmed.hasPrefix(familyId) || trimmed.hasPrefix(familyId.uppercased()) {
                    found = true
                    out.append(line)
                }
            } else {
                // We're inside our target family
                if isBlank && previousWasBlank {
                    // Two consecutive blank lines = end of family
                    break
                } else if isBlank && !previousWasBlank {
                    // First blank line after content - might be end
                    // Check if next non-blank line is a new family ID
                    var nextNonBlankIndex = contentLines.firstIndex(of: line)! + 1
                    while nextNonBlankIndex < contentLines.count {
                        let nextLine = contentLines[nextNonBlankIndex].trimmingCharacters(in: .whitespaces)
                        if !nextLine.isEmpty && nextLine != "#" {
                            // Check if it looks like a family ID
                            if let firstChar = nextLine.first, firstChar.isUppercase {
                                // This is likely a new family, stop here
                                break
                            }
                            break
                        }
                        nextNonBlankIndex += 1
                    }
                }
                out.append(line)
            }
            
            previousWasBlank = isBlank
        }
        
        if !found {
            logWarn(.file, "⚠️ Family \(familyId) not found in file")
            return nil
        }
        
        return out.isEmpty ? nil : out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /**
     * Find the next family ID after the given one
     */
    func findNextFamilyId(after currentFamilyId: String) -> String? {
        // Find current position in FamilyIDs array
        guard let currentIndex = FamilyIDs.indexOf(familyId: currentFamilyId) else {
            logWarn(.file, "Current family \(currentFamilyId) not found in FamilyIDs")
            return nil
        }
        
        // Return next one if it exists
        let nextIndex = currentIndex + 1
        if let nextId = FamilyIDs.familyAt(index: nextIndex) {
            logInfo(.file, "Found next family ID: \(nextId)")
            return nextId
        } else {
            logInfo(.file, "No family after \(currentFamilyId) - reached end of list")
            return nil
        }
    }

    /**
     * Check if a family ID exists
     */
    func familyExistsInFile(_ familyId: String) -> Bool {
        return FamilyIDs.isValid(familyId: familyId)
    }

    /**
     * Get statistics about families
     */
    func getFamilyStatistics() -> (total: Int, found: Int, missing: [String]) {
        // If file is loaded and FamilyIDs is correct, all families should be present
        if isFileLoaded {
            return (
                total: FamilyIDs.count,
                found: FamilyIDs.count,
                missing: []
            )
        } else {
            return (
                total: FamilyIDs.count,
                found: 0,
                missing: FamilyIDs.validFamilyIds
            )
        }
    }

    // MARK: - Recent files

    private func addToRecentFiles(_ url: URL) {
        recentFileURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentFileURLs.insert(url, at: 0)
        if recentFileURLs.count > 10 { recentFileURLs = Array(recentFileURLs.prefix(10)) }
        saveRecentFiles()
    }

    private func loadRecentFiles() {
        if let bookmarks = UserDefaults.standard.array(forKey: "RecentFileBookmarks") as? [Data] {
            recentFileURLs = bookmarks.compactMap { data in
                var stale = false
                return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
            }.filter { $0 != nil }.map { $0! }
        }
    }

    private func saveRecentFiles() {
        let bookmarks = recentFileURLs.compactMap { url in
            try? url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: "RecentFileBookmarks")
    }
}
