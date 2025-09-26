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

    // MARK: - Family text helpers

    func extractFamilyText(familyId: String) -> String? {
        guard let content = currentFileContent else {
            logWarn(.file, "No file content loaded")
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
        var out: [String] = []
        var capturing = false
        let target = familyId.uppercased()
        
        // Skip the first two lines (canonical marker and blank line)
        let contentLines = Array(lines.dropFirst(2))

        for line in contentLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            
            if !capturing {
                // Check if this line starts with our target family ID
                let lineUpper = t.uppercased()
                
                // Handle both formats: "KYKYRI II 9, page 264" and "KYKYRI II 9"
                if lineUpper.hasPrefix(target) {
                    // Verify it's the exact family (not a prefix match)
                    let afterTarget = String(lineUpper.dropFirst(target.count))
                    // Should be either empty, start with comma, or start with whitespace
                    if afterTarget.isEmpty || afterTarget.hasPrefix(",") || afterTarget.first?.isWhitespace == true {
                        capturing = true
                        out.append(line)
                        logDebug(.file, "Started capturing family: \(familyId)")
                    }
                }
            } else {
                // Stop at blank line
                if t.isEmpty {
                    logDebug(.file, "Finished capturing family: \(familyId)")
                    break
                }
                out.append(line)
            }
        }
        
        return out.isEmpty ? nil : out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func findNextFamilyId(after currentFamilyId: String) -> String? {
        guard let content = currentFileContent else { return nil }
        let lines = content.components(separatedBy: .newlines)
        var foundCurrent = false
        var passedBlank = false
        let target = currentFamilyId.uppercased()
        
        // Skip the first two lines (canonical marker and blank line)
        let contentLines = Array(lines.dropFirst(2))

        for line in contentLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            let u = t.uppercased()
            
            if !foundCurrent {
                // Look for the current family
                if u.hasPrefix(target) {
                    foundCurrent = true
                    logDebug(.file, "Found current family: \(t)")
                }
            } else if !passedBlank {
                // Wait for a blank line after current family
                if t.isEmpty {
                    passedBlank = true
                    logDebug(.file, "Passed blank line after \(currentFamilyId)")
                }
            } else if !t.isEmpty {
                // Found the next non-empty line - extract the family ID
                
                // Family ID is everything before the comma (or the whole line if no comma)
                let familyId: String
                if let commaIndex = t.firstIndex(of: ",") {
                    familyId = String(t[..<commaIndex]).trimmingCharacters(in: .whitespaces)
                } else {
                    familyId = t
                }
                
                logInfo(.file, "Found next family ID: \(familyId)")
                return familyId
            }
        }
        
        logInfo(.file, "No next family found after \(currentFamilyId)")
        return nil
    }

    // Helper method to find all family IDs in order
    func getAllFamilyIds() -> [String] {
        guard let content = currentFileContent else { return [] }
        let lines = content.components(separatedBy: .newlines)
        var familyIds: [String] = []
        var previousWasBlank = true  // Treat start of content as "after blank"
        
        // Skip the first two lines (canonical marker and blank line)
        let contentLines = Array(lines.dropFirst(2))
        
        for line in contentLines {
            let t = line.trimmingCharacters(in: .whitespaces)
            
            if t.isEmpty {
                previousWasBlank = true
                continue
            }
            
            // If previous line was blank, this might be a family ID
            if previousWasBlank {
                // Extract everything before the comma (or whole line if no comma)
                let familyId: String
                if let commaIndex = t.firstIndex(of: ",") {
                    familyId = String(t[..<commaIndex]).trimmingCharacters(in: .whitespaces)
                } else {
                    familyId = t
                }
                
                // Simple check: starts with uppercase letter (most family IDs do)
                if let firstChar = familyId.first, firstChar.isUppercase {
                    familyIds.append(familyId)
                }
            }
            
            previousWasBlank = false
        }
        
        return familyIds
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
