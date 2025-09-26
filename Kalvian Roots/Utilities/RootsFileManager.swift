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
        guard let docs = documentsURL() else { return nil }
        return docs.appendingPathComponent(defaultFileName, isDirectory: false)
    }

    // MARK: - Content Validation

    /// Validate that the file content has the required canonical marker
    private func validateCanonicalMarker(in content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines)
        guard lines.count >= 3 else {
            logError(.file, "❌ File too short - must have at least 3 lines")
            return false
        }
        
        // First line must be exactly "canonical"
        let firstLine = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstLine == "canonical" else {
            logError(.file, "❌ First line must be 'canonical', found: '\(firstLine)'")
            return false
        }
        
        // Second line must be blank
        let secondLine = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard secondLine.isEmpty else {
            logError(.file, "❌ Second line must be blank, found: '\(secondLine)'")
            return false
        }
        
        logInfo(.file, "✅ Canonical marker validated")
        return true
    }

    // MARK: - Auto-load

    /// Attempt to auto-load the canonical file from iCloud. No local fallback.
    func autoLoadDefaultFile() async {
        logInfo(.file, "🔍 Searching for \(defaultFileName) in iCloud (Documents/)")

        guard let docsURL = documentsURL() else {
            setError("Cannot access iCloud Drive.")
            return
        }
        
        let canonicalURL = docsURL.appendingPathComponent(defaultFileName)
        
        // Check if file exists at the canonical location
        if Foundation.FileManager.default.fileExists(atPath: canonicalURL.path) {
            // Load it
            do {
                let content = try String(contentsOf: canonicalURL, encoding: .utf8)
                
                // Validate canonical marker
                guard validateCanonicalMarker(in: content) else {
                    setError("""
                        FATAL: JuuretKälviällä.roots is missing the canonical marker.
                        
                        The first line of the file must be exactly "canonical"
                        The second line must be blank.
                        The third line begins the actual content.
                        
                        Please add these lines to your file.
                        """)
                    return
                }
                
                await MainActor.run {
                    self.currentFileContent = content
                    self.currentFileURL = canonicalURL
                    self.isFileLoaded = true
                }
                logInfo(.file, "✅ Loaded canonical file from iCloud")
                return
            } catch {
                setError("Failed to read canonical file: \(error.localizedDescription)")
                return
            }
        }
        
        // File not at canonical location - this is an error condition
        setError("""
            FATAL: JuuretKälviällä.roots not found at canonical location.
            
            Expected location:
            ~/Library/Mobile Documents/iCloud~com~michael-bendio~Kalvian-Roots/Documents/JuuretKälviällä.roots
            
            Please move the file to the correct location.
            """)
    }

    // MARK: - Loading

    #if os(macOS)
    func openFile() async throws -> String {
        // STRICT: Only allow opening from the canonical location
        guard let canonicalURL = getCanonicalFileURL() else {
            throw RootsFileManagerError.loadFailed("Cannot determine canonical location")
        }
        
        guard Foundation.FileManager.default.fileExists(atPath: canonicalURL.path) else {
            throw RootsFileManagerError.fileNotFound("""
                FATAL: JuuretKälviällä.roots not at canonical location.
                
                Expected: \(canonicalURL.path)
                
                Please move the file to the correct location.
                """)
        }
        
        return try await MainActor.run {
            let content = try String(contentsOf: canonicalURL, encoding: .utf8)
            
            // Validate canonical marker
            guard validateCanonicalMarker(in: content) else {
                throw RootsFileManagerError.loadFailed("""
                    FATAL: Missing canonical marker.
                    
                    First line must be "canonical"
                    Second line must be blank
                    Third line starts content
                    """)
            }
            
            self.currentFileContent = content
            self.currentFileURL = canonicalURL
            self.isFileLoaded = true
            self.errorMessage = nil
            
            addToRecentFiles(canonicalURL)
            logInfo(.file, "✅ Loaded canonical file")
            return content
        }
    }
    #else
    func openFile() async throws -> String {
        // iOS must use the canonical location
        guard let canonicalURL = getCanonicalFileURL() else {
            throw RootsFileManagerError.loadFailed("Cannot determine canonical location")
        }
        
        guard Foundation.FileManager.default.fileExists(atPath: canonicalURL.path) else {
            throw RootsFileManagerError.fileNotFound("""
                FATAL: JuuretKälviällä.roots not at canonical location.
                Please place it in the Kalvian Roots folder in iCloud Drive.
                """)
        }
        
        return try await processSelectedFileFromPicker(canonicalURL)
    }

    func processSelectedFileFromPicker(_ url: URL) async throws -> String {
        // Verify this is the canonical location
        guard let canonicalURL = getCanonicalFileURL() else {
            throw RootsFileManagerError.loadFailed("Cannot determine canonical location")
        }
        
        guard url.standardizedFileURL == canonicalURL.standardizedFileURL else {
            throw RootsFileManagerError.loadFailed("""
                FATAL: Selected file is not at canonical location.
                
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

    // MARK: - Family ID Methods (Using Curated List)

    /**
     * Get all family IDs that exist in the file, in file order
     * Uses the curated FamilyIDs list as the source of truth
     */
    func getAllFamilyIds() -> [String] {
        guard let content = currentFileContent else { return [] }
        
        var foundIds: [String] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Skip the first two lines (canonical marker and blank line)
        let contentLines = Array(lines.dropFirst(2))
        
        for line in contentLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and bookmarks
            if t.isEmpty || t == "#" { continue }
            
            // Try each valid family ID to see if this line starts with it
            for validId in FamilyIDs.validFamilyIds {
                let upperLine = t.uppercased()
                let upperValidId = validId.uppercased()
                
                if upperLine.hasPrefix(upperValidId) {
                    // Check what comes after the ID - should be comma, space, or nothing
                    let afterId = String(upperLine.dropFirst(upperValidId.count))
                    if afterId.isEmpty || afterId.hasPrefix(",") || afterId.hasPrefix(" ") {
                        // This is a valid family ID line
                        if !foundIds.contains(validId) {
                            foundIds.append(validId)
                            logTrace(.file, "Found family in file: \(validId)")
                        }
                        break // Found the ID for this line, move to next line
                    }
                }
            }
        }
        
        logInfo(.file, "Found \(foundIds.count) valid families in file (from \(FamilyIDs.validFamilyIds.count) known families)")
        return foundIds
    }

    /**
     * Extract family text for a specific family ID
     */
    func extractFamilyText(familyId: String) -> String? {
        // First verify this is a valid family ID
        guard FamilyIDs.isValid(familyId: familyId) else {
            logWarn(.file, "Invalid family ID requested: \(familyId)")
            return nil
        }
        
        guard let content = currentFileContent else {
            logWarn(.file, "No file content loaded")
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
        var out: [String] = []
        var capturing = false
        var skipNextBlank = false
        
        // Skip the first two lines (canonical marker and blank line)
        let contentLines = Array(lines.dropFirst(2))
        
        for (index, line) in contentLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            
            if !capturing {
                // Check for bookmark immediately before a family
                if t == "#" {
                    // Check if next non-empty line is our target
                    if index + 1 < contentLines.count {
                        let nextLine = contentLines[index + 1].trimmingCharacters(in: .whitespaces)
                        if nextLine.uppercased().hasPrefix(familyId.uppercased()) {
                            // Include the bookmark
                            out.append("#")
                            skipNextBlank = false
                        }
                    }
                    continue
                }
                
                // Check if this line is our target family
                if t.uppercased().hasPrefix(familyId.uppercased()) {
                    // Verify it's exact match (not a prefix of another family)
                    let afterId = String(t.uppercased().dropFirst(familyId.count))
                    if afterId.isEmpty || afterId.hasPrefix(",") || afterId.first?.isWhitespace == true {
                        capturing = true
                        out.append(line) // Use original line with formatting
                        logDebug(.file, "Started capturing family: \(familyId)")
                    }
                }
            } else {
                // Stop at blank line (unless it's a bookmark)
                if t.isEmpty && !skipNextBlank {
                    logDebug(.file, "Finished capturing family: \(familyId)")
                    break
                }
                skipNextBlank = false
                out.append(line)
            }
        }
        
        return out.isEmpty ? nil : out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /**
     * Find the next family ID after the given one
     */
    func findNextFamilyId(after currentFamilyId: String) -> String? {
        // Get all family IDs in file order
        let allIds = getAllFamilyIds()
        
        // Find current position
        guard let currentIndex = allIds.firstIndex(where: {
            $0.uppercased() == currentFamilyId.uppercased()
        }) else {
            logWarn(.file, "Current family \(currentFamilyId) not found in file")
            return nil
        }
        
        // Return next one if it exists
        let nextIndex = currentIndex + 1
        if nextIndex < allIds.count {
            let nextId = allIds[nextIndex]
            logInfo(.file, "Found next family ID: \(nextId)")
            return nextId
        } else {
            logInfo(.file, "No family after \(currentFamilyId) - reached end of file")
            return nil
        }
    }

    /**
     * Check if a family ID exists in the file
     */
    func familyExistsInFile(_ familyId: String) -> Bool {
        guard FamilyIDs.isValid(familyId: familyId) else { return false }
        
        let allIds = getAllFamilyIds()
        return allIds.contains { $0.uppercased() == familyId.uppercased() }
    }

    /**
     * Get statistics about families in the file
     */
    func getFamilyStatistics() -> (total: Int, found: Int, missing: [String]) {
        let foundIds = getAllFamilyIds()
        let foundSet = Set(foundIds.map { $0.uppercased() })
        
        let missing = FamilyIDs.validFamilyIds.filter { validId in
            !foundSet.contains(validId.uppercased())
        }
        
        return (
            total: FamilyIDs.validFamilyIds.count,
            found: foundIds.count,
            missing: missing.sorted()
        )
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
        let bookmarks = recentFileURLs.compactMap { try? $0.bookmarkData(options: .minimalBookmark) }
        UserDefaults.standard.set(bookmarks, forKey: "RecentFileBookmarks")
    }

    // MARK: - Status

    func getFileStatus() -> FileStatus {
        let canonical = getCanonicalFileURL()
        return FileStatus(
            isLoaded: isFileLoaded,
            fileName: currentFileURL?.lastPathComponent,
            filePath: currentFileURL?.path,
            fileSize: getFileSize(),
            isDefaultFile: (normalize(defaultFileName) == normalize(currentFileURL?.lastPathComponent ?? "")),
            isCanonicalLocation: (canonical != nil) && (currentFileURL?.standardizedFileURL == canonical?.standardizedFileURL)
        )
    }

    private func getFileSize() -> String? {
        guard let url = currentFileURL else { return nil }
        do {
            let attrs = try Foundation.FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber {
                return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
            }
        } catch {
            logWarn(.file, "⚠️ Could not read size: \(error)")
        }
        return nil
    }

    // MARK: - Utilities

    private func normalize(_ s: String) -> String {
        // Compare using both common NFC + case folding for safety
        s.precomposedStringWithCanonicalMapping.folding(options: String.CompareOptions([.caseInsensitive, .diacriticInsensitive]), locale: .current)
    }

    @MainActor
    private func setError(_ message: String) {
        self.errorMessage = message
    }
}

// MARK: - Support types

struct FileStatus {
    let isLoaded: Bool
    let fileName: String?
    let filePath: String?
    let fileSize: String?
    let isDefaultFile: Bool
    let isCanonicalLocation: Bool

    var displayName: String { fileName ?? "No file loaded" }
    var statusDescription: String {
        if isLoaded {
            var d = "Loaded"
            if let size = fileSize { d += " (\(size))" }
            if isDefaultFile && isCanonicalLocation { d += " [Canonical]" }
            else if isDefaultFile { d += " [Default]" }
            return d
        } else { return "No file loaded" }
    }
    var locationDescription: String {
        guard isLoaded else { return "No file loaded" }
        return isCanonicalLocation ? "✅ Canonical location (syncs across devices)"
                                   : "⚠️ Non-canonical location (device-specific)"
    }
}

enum RootsFileManagerError: LocalizedError {
    case userCancelled
    case loadFailed(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled: return "File selection cancelled"
        case .loadFailed(let r): return "Failed to load file: \(r)"
        case .fileNotFound(let p): return "File not found: \(p)"
        }
    }
}

// Small helper to unique arrays
private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
