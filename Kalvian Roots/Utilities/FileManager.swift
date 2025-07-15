//
//  FileManager.swift
//  Kalvian Roots
//
//  Clean rebuild - no lingering syntax issues
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@Observable
class JuuretFileManager {
    
    // MARK: - Properties
    
    private(set) var currentFileURL: URL?
    private(set) var currentFileContent: String?
    private(set) var isFileLoaded: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?
    private(set) var recentFileURLs: [URL] = []
    private var savedBookmarkData: Data?
    
    #if os(iOS)
    private var documentPickerDelegate: DocumentPickerDelegate?
    #endif
    
    // MARK: - Static Methods
    
    static func loadJuuretText() async throws -> String {
        let fileManager = Foundation.FileManager.default
        
        // Try multiple locations
        let possiblePaths = [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Documents/JuuretKälviällä.roots"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents/JuuretKälviällä.roots")
        ]
        
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path.path) {
                return try String(contentsOf: path, encoding: .utf8)
            }
        }
        
        throw JuuretError.fileNotFound
    }
    
    // MARK: - Public Methods
    
    func autoLoadDefaultFile() async {
        print("🔍 Auto-loading with permission-aware approach...")
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Try to load from saved bookmark first
        if let bookmarkData = loadSavedBookmark() {
            print("📖 Trying saved bookmark...")
            
            do {
                var isStale = false
                
                #if os(macOS)
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale)
                #else
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale)
                #endif
                
                if !isStale {
                    print("✅ Bookmark is valid, attempting to load...")
                    
                    #if os(macOS)
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        try await loadFile(at: url)
                        return
                    }
                    #else
                    try await loadFile(at: url)
                    return
                    #endif
                }
            } catch {
                print("❌ Bookmark failed: \(error)")
            }
        }
        
        // Check if file exists and suggest file picker
        let fileExists = checkIfFileExistsAnywhere()
        
        await MainActor.run {
            if fileExists {
                self.errorMessage = """
                JuuretKälviällä.roots found but needs permission to access.
                Please use the 'Open File' button to grant access.
                """
            } else {
                self.errorMessage = """
                JuuretKälviällä.roots not found. Please:
                1. Place the file in Documents or iCloud Drive/Documents
                2. Use the 'Open File' button to select it
                """
            }
        }
    }
    
    func openFileDialog() async throws {
        print("🔄 openFileDialog() called - current loading state: \(isLoading)")
        
        guard !isLoading else {
            print("🔄 Already loading, skipping duplicate call")
            return
        }
        
        #if os(macOS)
        try await openMacFileDialog()
        #elseif os(iOS)
        await openIOSFilePicker()
        #else
        throw JuuretError.fileNotFound
        #endif
    }
    
    func loadFile(at url: URL) async throws {
        print("📖 Loading file from: \(url.path)")
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        let fileExists = Foundation.FileManager.default.fileExists(atPath: url.path)
        print("📖 File exists: \(fileExists)")
        
        if !fileExists {
            print("❌ File not found at path: \(url.path)")
            
            if url.path.contains("Mobile Documents") {
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                    print("☁️ iCloud file info:")
                    print("☁️ File size: \(resourceValues.fileSize ?? 0) bytes")
                    print("☁️ This is an iCloud file - may need manual download")
                } catch {
                    print("☁️ Could not get iCloud file info: \(error)")
                }
            }
            
            throw JuuretError.fileNotFound
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            print("✅ File loaded successfully")
            print("📊 Content length: \(content.count) characters")
            print("📊 Lines: \(content.components(separatedBy: .newlines).count)")
            
            await MainActor.run {
                self.currentFileURL = url
                self.currentFileContent = content
                self.isFileLoaded = true
                self.errorMessage = nil
            }
            
        } catch {
            print("❌ Failed to read file content: \(error)")
            throw error
        }
    }
    
    func extractFamilyText(familyId: String) -> String? {
        guard let content = currentFileContent else {
            return nil
        }
        
        let normalizedId = familyId.uppercased()
        let lines = content.components(separatedBy: .newlines)
        
        guard let startIndex = lines.firstIndex(where: { line in
            line.uppercased().hasPrefix(normalizedId)
        }) else {
            return nil
        }
        
        var familyLines: [String] = []
        
        for i in startIndex..<lines.count {
            let line = lines[i]
            
            if i > startIndex && isFamilyHeaderLine(line) {
                break
            }
            
            familyLines.append(line)
        }
        
        return familyLines.joined(separator: "\n")
    }
    
    func closeFile() {
        currentFileURL = nil
        currentFileContent = nil
        isFileLoaded = false
        errorMessage = nil
    }
    
    func addToRecentFiles(_ url: URL) {
        recentFileURLs.removeAll { $0 == url }
        recentFileURLs.insert(url, at: 0)
        
        if recentFileURLs.count > 10 {
            recentFileURLs = Array(recentFileURLs.prefix(10))
        }
    }
    
    func clearRecentFiles() {
        recentFileURLs.removeAll()
    }
    
    // MARK: - Platform-Specific File Dialogs
    
    #if os(macOS)
    private func openMacFileDialog() async throws {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "roots")!]
        } else {
            panel.allowedFileTypes = ["roots", "text"]
        }
        #else
        panel.allowedFileTypes = ["roots", "text"]
        #endif
        
        panel.title = "Select JuuretKälviällä.roots file"
        panel.message = "Choose the Juuret Kälviällä genealogy text file"
        
        let homeDir = getActualHomeDirectory()
        let iCloudDocs = URL(fileURLWithPath: "\(homeDir)/Library/Mobile Documents/com~apple~CloudDocs/Documents")
        if Foundation.FileManager.default.fileExists(atPath: iCloudDocs.path) {
            panel.directoryURL = iCloudDocs
        } else {
            panel.directoryURL = URL(fileURLWithPath: "\(homeDir)/Documents")
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        let result = await MainActor.run { panel.runModal() }
        
        if result == .OK, let url = panel.url {
            print("📁 User selected file: \(url.path)")
            
            do {
                #if os(macOS)
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil)
                #else
                let bookmarkData = try url.bookmarkData(options: [],
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil)
                #endif
                saveBookmark(bookmarkData)
                print("💾 Saved security bookmark for future access")
            } catch {
                print("⚠️ Could not create bookmark: \(error)")
            }
            
            #if os(macOS)
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                try await loadFile(at: url)
            } else {
                throw JuuretError.fileNotFound
            }
            #else
            try await loadFile(at: url)
            #endif
            
            addToRecentFiles(url)
        } else {
            print("🚫 User cancelled file selection")
        }
    }
    #endif
    
    #if os(iOS)
    @MainActor
    private func openIOSFilePicker() async {
        print("📱 === Starting iOS file picker process ===")
        
        guard !isLoading else {
            print("📱 Already loading, skipping duplicate call")
            return
        }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            print("❌ Could not get window scene or window")
            errorMessage = "Could not access app window"
            return
        }
        
        var rootViewController = window.rootViewController
        print("📱 Initial root controller: \(String(describing: rootViewController))")
        
        if let hostingController = rootViewController as? UIHostingController<AnyView> {
            rootViewController = hostingController
            print("📱 Using hosting controller")
        }
        
        guard let rootVC = rootViewController else {
            print("❌ Could not get root view controller")
            errorMessage = "Could not access view controller"
            return
        }
        
        var topController = rootVC
        while let presented = topController.presentedViewController {
            print("📱 Found presented controller: \(String(describing: presented))")
            topController = presented
        }
        
        print("📱 Will present on: \(String(describing: topController))")
        
        let documentPicker: UIDocumentPickerViewController
        
        #if canImport(UniformTypeIdentifiers)
        if #available(iOS 14.0, *) {
            print("📱 Using modern document picker (iOS 14+)")
            documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText, .text])
        } else {
            print("📱 Using legacy document picker (iOS 13)")
            documentPicker = UIDocumentPickerViewController(documentTypes: ["public.plain-text", "public.text"], in: .open)
        }
        #else
        print("📱 Using fallback document picker")
        documentPicker = UIDocumentPickerViewController(documentTypes: ["public.plain-text", "public.text"], in: .open)
        #endif
        
        documentPicker.allowsMultipleSelection = false
        documentPicker.modalPresentationStyle = .formSheet
        documentPicker.shouldShowFileExtensions = true
        
        print("📱 Document picker configured")
        
        let delegate = DocumentPickerDelegate { [weak self] url in
            print("📱 === Delegate callback triggered ===")
            print("📱 Selected URL: \(url)")
            
            Task {
                await self?.handlePickedFile(url)
            }
        }
        
        self.documentPickerDelegate = delegate
        documentPicker.delegate = delegate
        
        print("📱 Delegate assigned, about to present...")
        
        isLoading = true
        errorMessage = nil
        
        topController.present(documentPicker, animated: true) {
            print("📱 Document picker presentation animation completed")
        }
        
        print("📱 === File picker setup complete ===")
    }
    
    @MainActor
    private func handlePickedFile(_ url: URL) async {
        print("📱 === Handling picked file ===")
        print("📱 File: \(url.lastPathComponent)")
        print("📱 Path: \(url.path)")
        
        // CRITICAL: Start accessing security scoped resource FIRST
        let hasAccess = url.startAccessingSecurityScopedResource()
        print("📱 Security scoped access granted: \(hasAccess)")
        
        // Use defer to ensure we stop accessing when done
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
                print("📱 Released security scoped access")
            }
        }
        
        do {
            if url.path.contains("Mobile Documents") {
                print("☁️ Detected iCloud file, checking download status...")
                
                do {
                    try Foundation.FileManager.default.startDownloadingUbiquitousItem(at: url)
                    print("☁️ Started iCloud download...")
                    
                    var attempts = 0
                    let maxAttempts = 20
                    
                    while attempts < maxAttempts {
                        if Foundation.FileManager.default.fileExists(atPath: url.path) {
                            do {
                                let testData = try Data(contentsOf: url, options: [.mappedIfSafe])
                                if testData.count > 0 {
                                    print("✅ iCloud file is now accessible!")
                                    break
                                }
                            } catch {
                                print("⚠️ File exists but not yet readable: \(error)")
                            }
                        }
                        
                        print("☁️ Attempt \(attempts + 1): waiting for iCloud sync...")
                        
                        try await Task.sleep(nanoseconds: 500_000_000)
                        attempts += 1
                    }
                    
                    if attempts >= maxAttempts {
                        print("⚠️ iCloud download timed out, trying to load anyway...")
                    }
                    
                } catch {
                    print("⚠️ Could not start iCloud download: \(error)")
                    print("⚠️ Will try to load file directly...")
                }
            }
            
            let fileExists = Foundation.FileManager.default.fileExists(atPath: url.path)
            print("📱 File exists check: \(fileExists)")
            
            if fileExists {
                // Save bookmark AFTER we confirm access works
                do {
                    let bookmarkData = try url.bookmarkData(options: [],
                                                           includingResourceValuesForKeys: nil,
                                                           relativeTo: nil)
                    saveBookmark(bookmarkData)
                    print("💾 Saved iOS bookmark for future access")
                } catch {
                    print("⚠️ Could not create iOS bookmark: \(error)")
                }
                
                print("📱 Starting file load...")
                try await loadFile(at: url)
                addToRecentFiles(url)
                print("📱 File load completed successfully")
            } else {
                print("❌ File still doesn't exist after iCloud download attempt")
                
                // Give more specific error for iCloud files
                if url.path.contains("Mobile Documents") {
                    errorMessage = "iCloud file not accessible. Please ensure the file is downloaded to your device in the Files app."
                } else {
                    errorMessage = "Selected file could not be accessed."
                }
                
                throw JuuretError.fileNotFound
            }
            
        } catch {
            print("❌ iOS file loading failed: \(error)")
            if errorMessage == nil {
                errorMessage = "Failed to load selected file. If this is an iCloud file, make sure it's downloaded to your device."
            }
        }
        
        documentPickerDelegate = nil
        print("📱 === File handling complete ===")
    }
    #endif
    
    // MARK: - Helper Methods
    
    private func checkIfFileExistsAnywhere() -> Bool {
        let fileManager = Foundation.FileManager.default
        let fileName = "JuuretKälviällä.roots"
        let homeDir = getActualHomeDirectory()
        
        let locations = [
            "\(homeDir)/Library/Mobile Documents/com~apple~CloudDocs/Documents/\(fileName)",
            "\(homeDir)/Documents/\(fileName)",
            "\(homeDir)/Desktop/\(fileName)",
            "\(homeDir)/Downloads/\(fileName)"
        ]
        
        for location in locations {
            if fileManager.fileExists(atPath: location) {
                print("📍 File exists at: \(location)")
                return true
            }
        }
        
        return false
    }
    
    private func getActualHomeDirectory() -> String {
        let homeDir = NSHomeDirectory()
        if homeDir.contains("/Library/Containers/") {
            return homeDir.replacingOccurrences(
                of: "/Library/Containers/com.michael-bendio.Kalvian-Roots/Data",
                with: ""
            )
        }
        return homeDir
    }
    
    private func saveBookmark(_ bookmarkData: Data) {
        UserDefaults.standard.set(bookmarkData, forKey: "JuuretFileBookmark")
        self.savedBookmarkData = bookmarkData
    }
    
    private func loadSavedBookmark() -> Data? {
        if let saved = savedBookmarkData {
            return saved
        }
        
        let bookmark = UserDefaults.standard.data(forKey: "JuuretFileBookmark")
        savedBookmarkData = bookmark
        return bookmark
    }
    
    private func isFamilyHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.contains(" ") && trimmed.contains(",") && trimmed.contains("PAGE")
    }
}

#if os(iOS)
class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL) -> Void
    
    init(completion: @escaping (URL) -> Void) {
        self.completion = completion
        super.init()
        print("📱 DocumentPickerDelegate created")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("📱 === DocumentPicker delegate called ===")
        print("📱 Number of files selected: \(urls.count)")
        
        for (index, url) in urls.enumerated() {
            print("📱 File \(index): \(url.lastPathComponent)")
            print("📱 Full path: \(url.path)")
        }
        
        if let url = urls.first {
            print("📱 Calling completion with first file: \(url.lastPathComponent)")
            completion(url)
        } else {
            print("❌ No files in selection")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            controller.dismiss(animated: true) {
                print("📱 DocumentPicker dismissed after selection")
            }
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("🚫 DocumentPicker cancelled by user")
        controller.dismiss(animated: true) {
            print("📱 Cancelled picker dismissed")
        }
    }
    
    deinit {
        print("📱 DocumentPickerDelegate deallocated")
    }
}
#endif
