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

    /// The app's iCloud container root. (This *is* the “Kalvian Roots” folder in iCloud Drive.)
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
            JuuretKälviällä.roots not found at canonical location.
            Expected: ~/Library/Mobile Documents/iCloud~com~michael-bendio~Kalvian-Roots/Documents/
            
            Please move the file to the correct location.
            """)
    }

    // MARK: - Loading

    #if os(macOS)
    func openFile() async throws -> String {
        // Optional: allow a manual pick on macOS, but still warn if it isn't canonical.
        return try await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = "Open Juuret Kälviällä File"
            panel.allowedContentTypes = []
            panel.allowsOtherFileTypes = true
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.message = "Select your Juuret Kälviällä file (.roots) from iCloud Drive"
            panel.prompt = "Open File"
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else {
                throw RootsFileManagerError.userCancelled
            }
            if let canonical = getCanonicalFileURL(), url.standardizedFileURL != canonical.standardizedFileURL {
                logWarn(.file, "⚠️ Selected file is not in canonical iCloud location")
            }
            return try processSelectedFile(url)
        }
    }
    #else
    func openFile() async throws -> String {
        logWarn(.file, "⚠️ Use UIDocumentPicker and call processSelectedFileFromPicker(_:) on iOS")
        throw RootsFileManagerError.loadFailed("Use the document picker UI on iOS/iPadOS")
    }

    func processSelectedFileFromPicker(_ url: URL) async throws -> String {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
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

    // macOS loader with security-scoped access if necessary (usually not needed for our container)
    #if os(macOS)
    private func processSelectedFile(_ url: URL) throws -> String {
        guard Foundation.FileManager.default.fileExists(atPath: url.path) else {
            throw RootsFileManagerError.fileNotFound(url.path)
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let content = try String(contentsOf: url, encoding: .utf8)
        currentFileURL = url
        currentFileContent = content
        isFileLoaded = true
        errorMessage = nil
        addToRecentFiles(url)
        return content
    }
    #endif

    private func loadFileFromURL(_ url: URL) async {
        do {
            // If the file is in iCloud but not downloaded, request it.
            var isDownloaded = true
            do {
                let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if let status = values.ubiquitousItemDownloadingStatus {
                    isDownloaded = (status == URLUbiquitousItemDownloadingStatus.current || status == URLUbiquitousItemDownloadingStatus.downloaded)
                }
            } catch { /* ignore */ }

            if !isDownloaded {
                logInfo(.file, "📥 Requesting iCloud download...")
                try Foundation.FileManager.default.startDownloadingUbiquitousItem(at: url)
            }

            // Read
            let content = try String(contentsOf: url, encoding: .utf8)
            await MainActor.run {
                self.currentFileURL = url
                self.currentFileContent = content
                self.isFileLoaded = true
                self.errorMessage = nil
            }
            addToRecentFiles(url)
            logInfo(.file, "🎉 Loaded canonical file from iCloud: \(url.lastPathComponent)")
        } catch {
            await setError("Failed to load file: \(error.localizedDescription)")
            logError(.file, "❌ \(error)")
        }
    }

    // MARK: - NSMetadataQuery search (handles not-downloaded files + Unicode name issues)

    private func findFileInICloudDocuments(named rawName: String) async -> URL? {
        guard let docsURL = documentsURL() else { return nil }

        let nameCandidates: [String] = [
            rawName,
            rawName.precomposedStringWithCanonicalMapping,
            rawName.decomposedStringWithCanonicalMapping
        ].uniqued()

        return await withCheckedContinuation { continuation in
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            // Limit to our Documents/ path
            query.predicate = NSPredicate(format: "%K BEGINSWITH %@",
                                          NSMetadataItemPathKey, docsURL.path)

            var found: URL?

            // Use a token variable declared before assignment to avoid capture-before-declare
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                query.disableUpdates()
                for item in query.results.compactMap({ $0 as? NSMetadataItem }) {
                    guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
                    let last = url.lastPathComponent
                    let lastNorms = [
                        last,
                        last.precomposedStringWithCanonicalMapping,
                        last.decomposedStringWithCanonicalMapping
                    ]
                    if nameCandidates.contains(where: { candidate in lastNorms.contains(candidate) }) {
                        found = url
                        break
                    }
                }
                query.stop()
                if let t = token { NotificationCenter.default.removeObserver(t) }
                continuation.resume(returning: found)
            }

            query.start()
        }
    }

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

        for line in lines {
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

        for line in lines {
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
        var previousWasBlank = true  // Treat start of file as "after blank"
        
        for line in lines {
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

