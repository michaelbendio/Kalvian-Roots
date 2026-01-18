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

    var errorMessage: String?

    /// The ONE canonical file name (normalize at comparison time)
    private let defaultFileName = "JuuretKälviällä.roots"

    // MARK: - Init
    
    init() {
        logInfo(.file, "📁 RootsFileManager initialized (main iCloud Drive Documents)")    }

    // MARK: - Canonical iCloud Locations
    
    // Point to main iCloud Drive
    private func containerURL() -> URL? {
        // Start with any ubiquity container to get the Mobile Documents path
        guard let anyContainer = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        // Get the Mobile Documents directory
        let mobileDocsURL = anyContainer.deletingLastPathComponent()
        // Return the main iCloud Drive container
        return mobileDocsURL.appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
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
    
    
    /// Get the effective file URL for cache path derivation
    /// On iOS, prefers the bookmark URL (actual file location) over programmatic canonical URL
    /// On macOS, returns the canonical URL
    func getEffectiveFileURL() -> URL? {
#if os(iOS)
        // First check if we have a loaded file URL (most accurate)
        if let loadedURL = currentFileURL {
            return loadedURL
        }
        
        // Try to resolve bookmark URL without loading the file
        // This allows cache to find the right location even before file is loaded
        if let bookmarkData = UserDefaults.standard.data(forKey: "FileBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                  bookmarkDataIsStale: &isStale)
                if !isStale {
                    return url
                }
            } catch {
                logWarn(.file, "⚠️ Failed to resolve bookmark for cache path: \(error)")
            }
        }
        
        // Fallback to programmatic canonical URL
        return getCanonicalFileURL()
#else
        // macOS: Always use canonical URL
        return getCanonicalFileURL()
#endif
    }
    
    // MARK: - Loading methods
    
    /// Auto-load the canonical file (should always succeed)
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 Auto-loading from canonical location")
        
#if os(macOS)
// macOS: Direct access to com~apple~CloudDocs
guard let canonicalURL = getCanonicalFileURL() else {
    await MainActor.run {
        self.errorMessage = "iCloud Drive not available"
    }
    logError(.file, "❌ iCloud Drive not available")
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

#elseif os(iOS)
// iOS: Try to load from saved security-scoped bookmark
if let bookmarkData = UserDefaults.standard.data(forKey: "FileBookmark") {
    do {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmarkData,
                          bookmarkDataIsStale: &isStale)
        
        if isStale {
            logWarn(.file, "⚠️ Bookmark is stale, user needs to reselect file")
            await MainActor.run {
                self.errorMessage = "Please select the file from iCloud Drive/Documents"
            }
            return
        }
        
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw RootsFileManagerError.loadFailed("Cannot access bookmarked file")
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        _ = try await loadFile(from: url)
        logInfo(.file, "✅ Auto-loaded from security-scoped bookmark")
        
    } catch {
        logError(.file, "❌ Failed to load from bookmark: \(error)")
        await MainActor.run {
            self.errorMessage = "Please select the file from iCloud Drive/Documents"
        }
    }
} else {
    // No bookmark saved - user needs to select file
    logInfo(.file, "📱 No saved bookmark - user needs to select file")
    await MainActor.run {
        self.errorMessage = "Please select JuuretKälviällä.roots from iCloud Drive/Documents"
    }
}
#endif
}
    
    /// Load from a specific URL (validates it's the canonical file)
    func loadFile(from url: URL) async throws -> String {
        logInfo(.file, "📂 Attempting to load file from: \(url.path)")
        
        // Just validate the filename, not the full path
        guard url.lastPathComponent == defaultFileName else {
            throw RootsFileManagerError.wrongFile("""
                Expected file: \(defaultFileName)
                Selected: \(url.lastPathComponent)
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
    func loadFileFromPicker(_ url: URL) async throws -> String {
        logInfo(.file, "📱 iOS: Loading file from picker")
        
        // Validate filename
        guard url.lastPathComponent == defaultFileName else {
            throw RootsFileManagerError.wrongFile("""
                Please select JuuretKälviällä.roots
                Selected: \(url.lastPathComponent)
                """)
        }
        
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw RootsFileManagerError.loadFailed("Cannot access selected file")
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Validate canonical marker
            guard validateCanonicalMarker(in: content) else {
                throw RootsFileManagerError.loadFailed("""
                    FATAL: Missing canonical marker.
                    The first line must be "canonical"
                    """)
            }
            
            // Save security-scoped bookmark for future launches
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: "FileBookmark")
                logInfo(.file, "💾 Saved security-scoped bookmark")
            } catch {
                logWarn(.file, "⚠️ Failed to save bookmark: \(error)")
            }
            
            await MainActor.run {
                self.currentFileURL = url
                self.currentFileContent = content
                self.isFileLoaded = true
                self.errorMessage = nil
            }
            
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
    /**
     * Extract family text for a specific family ID
     * FIXED: Properly stops at blank line followed by new family ID
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
        var shouldStop = false
        
        let contentLines = Array(lines.dropFirst(2)) // Skip canonical marker and blank line
        
        for (index, line) in contentLines.enumerated() {
            if shouldStop {
                break
            }
            
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
                    logDebug(.file, "✅ Found end of family (double blank) at line \(index)")
                    break
                } else if isBlank && !previousWasBlank {
                    // First blank line after content - check if next family starts
                    // Look ahead to see if next non-blank line is a new family ID
                    var lookAheadIndex = index + 1
                    var foundNextFamily = false
                    
                    while lookAheadIndex < contentLines.count {
                        let nextLine = contentLines[lookAheadIndex].trimmingCharacters(in: .whitespaces)
                        
                        if nextLine == "#" {
                            // Skip bookmarks
                            lookAheadIndex += 1
                            continue
                        }
                        
                        if nextLine.isEmpty {
                            // Another blank line - definitely end of family
                            logDebug(.file, "✅ Found end of family (double blank detected during lookahead) at line \(index)")
                            shouldStop = true
                            foundNextFamily = true
                            break
                        }
                        
                        // Found non-blank content - check if it's a family ID
                        if let firstChar = nextLine.first, firstChar.isUppercase {
                            // Looks like a family ID - check if it's in our valid set
                            let potentialFamilyId = nextLine.components(separatedBy: .whitespaces)
                                .prefix(while: { !$0.isEmpty })
                                .joined(separator: " ")
                            
                            // Try matching with 1-3 words + number
                            let words = nextLine.components(separatedBy: .whitespaces)
                            for wordCount in 1...min(3, words.count) {
                                let candidate = words.prefix(wordCount).joined(separator: " ")
                                if FamilyIDs.validFamilyIds.contains(where: { $0.hasPrefix(candidate) }) {
                                    logDebug(.file, "✅ Found end of family (next family '\(candidate)' detected) at line \(index)")
                                    shouldStop = true
                                    foundNextFamily = true
                                    break
                                }
                            }
                            if foundNextFamily {
                                break
                            }
                        }
                        
                        // If we hit non-family content, this blank is part of current family
                        break
                    }
                    
                    if !foundNextFamily {
                        // The blank line is part of the current family
                        out.append(line)
                    }
                } else {
                    // Normal content line
                    out.append(line)
                }
            }
            
            previousWasBlank = isBlank
        }
        
        if !found {
            logWarn(.file, "⚠️ Family \(familyId) not found in file")
            return nil
        }
        
        let result = out.isEmpty ? nil : out.joined(separator: "\n")
        
        if let result = result {
            let lineCount = out.count
            let charCount = result.count
            logInfo(.file, "✅ Extracted \(familyId): \(lineCount) lines, \(charCount) characters")
            
            // Log a warning if the extraction seems unusually large
            if charCount > 10000 {
                logWarn(.file, "⚠️ Large extraction detected (\(charCount) chars) - may exceed token limits")
            }
        }
        
        return result
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
}

extension RootsFileManager {
    
    /**
     * Search for families containing a specific 6-digit marriage date
     * Returns array of (familyId, familyText) tuples for matches
     *
     * Used as fallback when a married child has no valid asParent family ID
     * but has a 6-digit marriage date that can be searched.
     */
    func searchFamiliesByMarriageDate(_ marriageDate: String) -> [(familyId: String, familyText: String)] {
        guard let content = currentFileContent else {
            logWarn(.file, "⚠️ No file content loaded for marriage date search")
            return []
        }
        
        // Ensure we have a 6-digit date (DD.MM.YY format)
        guard marriageDate.contains(".") else {
            logDebug(.file, "Marriage date '\(marriageDate)' is not 6-digit format, skipping search")
            return []
        }
        
        logInfo(.file, "🔍 Searching for families with marriage date: \(marriageDate)")
        
        let lines = content.components(separatedBy: .newlines)
        var results: [(familyId: String, familyText: String)] = []
        var currentFamilyId: String? = nil
        var currentFamilyLines: [String] = []
        var inFamily = false
        
        let contentLines = Array(lines.dropFirst(2)) // Skip canonical marker and blank line
        
        for line in contentLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip bookmarks
            if trimmed == "#" {
                continue
            }
            
            // Check if this line starts a new family
            if let firstChar = trimmed.first, firstChar.isUppercase {
                // Check if it's a valid family ID
                let potentialId = extractPotentialFamilyId(from: trimmed)
                if let familyId = potentialId, FamilyIDs.isValid(familyId: familyId) {
                    // Save previous family if it contained the marriage date
                    if let prevId = currentFamilyId, !currentFamilyLines.isEmpty {
                        let familyText = currentFamilyLines.joined(separator: "\n")
                        if familyText.contains("∞ \(marriageDate)") || familyText.contains("∞\(marriageDate)") {
                            results.append((familyId: prevId, familyText: familyText))
                            logDebug(.file, "  Found match in: \(prevId)")
                        }
                    }
                    
                    // Start new family
                    currentFamilyId = familyId
                    currentFamilyLines = [line]
                    inFamily = true
                    continue
                }
            }
            
            // Add line to current family
            if inFamily {
                currentFamilyLines.append(line)
            }
        }
        
        // Check last family
        if let lastId = currentFamilyId, !currentFamilyLines.isEmpty {
            let familyText = currentFamilyLines.joined(separator: "\n")
            if familyText.contains("∞ \(marriageDate)") || familyText.contains("∞\(marriageDate)") {
                results.append((familyId: lastId, familyText: familyText))
                logDebug(.file, "  Found match in: \(lastId)")
            }
        }
        
        logInfo(.file, "🔍 Found \(results.count) families with marriage date \(marriageDate)")
        return results
    }
    
    /**
     * Extract potential family ID from a line
     * Returns nil if not a valid family ID pattern
     */
    private func extractPotentialFamilyId(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Family IDs typically end with a number or roman numeral + number
        // Examples: "KORPI 6", "KYKYRI II 9", "HYYPPÄ 6"
        
        // Try to match against known family IDs
        for familyId in FamilyIDs.validFamilyIds {
            if trimmed.hasPrefix(familyId) {
                // Make sure it's actually starting the line (not in middle of text)
                let afterId = trimmed.dropFirst(familyId.count)
                if afterId.isEmpty || afterId.first == "," || afterId.first == " " {
                    return familyId
                }
            }
        }
        
        return nil
    }
}
