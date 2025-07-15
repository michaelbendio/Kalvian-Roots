//
//  FileManager.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
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
    
    // MARK: - Public Methods
    
    static func loadJuuretText() async throws -> String {
        let systemFileManager = Foundation.FileManager.default
        
        guard let documentsURL = systemFileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") else {
            throw JuuretError.fileNotFound
        }
        
        let fileURL = documentsURL.appendingPathComponent("JuuretKälviällä.txt")
        
        guard systemFileManager.fileExists(atPath: fileURL.path) else {
            throw JuuretError.fileNotFound
        }
        
        do {
            try systemFileManager.startDownloadingUbiquitousItem(at: fileURL)
        } catch {
            print("Could not start downloading item: \(error)")
        }
        
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
    
    func autoLoadDefaultFile() async {
        print("🔍 Attempting to auto-load JuuretKälviällä.txt from default locations...")
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            // Try iCloud Documents first
            if let iCloudURL = getDefaultiCloudFileURL() {
                print("📱 Found iCloud Documents, attempting to load: \(iCloudURL.path)")
                try await loadFile(at: iCloudURL)
                return
            } else {
                print("📱 iCloud Documents not available or file not found there")
            }
            
            // Try local Documents folder
            if let localURL = getDefaultLocalFileURL() {
                print("💻 Found local Documents, attempting to load: \(localURL.path)")
                try await loadFile(at: localURL)
                return
            } else {
                print("💻 Local Documents check failed")
            }
            
            print("⚠️ JuuretKälviällä.txt not found in default locations")
            await MainActor.run {
                self.errorMessage = "JuuretKälviällä.txt not found. Use File → Open to select the file."
            }
            
        } catch {
            print("❌ Auto-load failed: \(error)")
            await MainActor.run {
                self.errorMessage = "Could not auto-load file: \(error.localizedDescription)"
            }
        }
    }
    
    func openFileDialog() async throws {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText, .text]
        panel.title = "Select JuuretKälviällä.txt file"
        panel.message = "Choose the Juuret Kälviällä genealogy text file"
        
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
            try await loadFile(at: url)
            addToRecentFiles(url)
        } else {
            print("🚫 User cancelled file selection")
        }
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
        
        guard Foundation.FileManager.default.fileExists(atPath: url.path) else {
            throw JuuretError.fileNotFound
        }
        
        if url.path.contains("iCloud") {
            do {
                try Foundation.FileManager.default.startDownloadingUbiquitousItem(at: url)
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                print("⚠️ Could not start iCloud download: \(error)")
            }
        }
        
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
    }
    
    func extractFamilyText(familyId: String) -> String? {
        guard let content = currentFileContent else {
            print("❌ No file content available for extraction")
            return nil
        }
        
        let normalizedId = familyId.uppercased()
        print("🔍 Searching for family: \(normalizedId)")
        print("📊 File content length: \(content.count) characters")
        
        let lines = content.components(separatedBy: .newlines)
        print("📊 Total lines in file: \(lines.count)")
        
        // Enhanced search - look for lines that contain the family ID
        var foundLines: [Int] = []
        for (index, line) in lines.enumerated() {
            if line.uppercased().contains(normalizedId) {
                foundLines.append(index)
                print("🔍 Found '\(normalizedId)' on line \(index + 1): \(line.prefix(50))...")
            }
        }
        
        if foundLines.isEmpty {
            print("❌ Family \(normalizedId) not found anywhere in text")
            return nil
        }
        
        // Look for the exact family header (starts with the family ID)
        guard let startIndex = lines.firstIndex(where: { line in
            line.uppercased().hasPrefix(normalizedId)
        }) else {
            print("❌ No line starts with \(normalizedId), but found these matches:")
            for lineIndex in foundLines.prefix(3) {
                print("   Line \(lineIndex + 1): \(lines[lineIndex])")
            }
            return nil
        }
        
        print("✅ Found family \(normalizedId) starting at line \(startIndex + 1)")
        print("📄 Header line: \(lines[startIndex])")
        
        var familyLines: [String] = []
        
        for i in startIndex..<lines.count {
            let line = lines[i]
            
            if i > startIndex && isFamilyHeaderLine(line) {
                print("🛑 Stopped at next family header (line \(i + 1)): \(line.prefix(30))...")
                break
            }
            
            familyLines.append(line)
        }
        
        let familyText = familyLines.joined(separator: "\n")
        print("📄 Extracted \(familyLines.count) lines for family \(normalizedId)")
        print("📄 First few lines of extracted text:")
        for (index, line) in familyLines.prefix(5).enumerated() {
            print("   \(index + 1): \(line)")
        }
        
        return familyText
    }
    
    func closeFile() {
        currentFileURL = nil
        currentFileContent = nil
        isFileLoaded = false
        errorMessage = nil
        print("📁 File closed")
    }
    
    func addToRecentFiles(_ url: URL) {
        recentFileURLs.removeAll { $0 == url }
        recentFileURLs.insert(url, at: 0)
        
        if recentFileURLs.count > 10 {
            recentFileURLs = Array(recentFileURLs.prefix(10))
        }
        
        print("📋 Added to recent files: \(url.lastPathComponent)")
    }
    
    func clearRecentFiles() {
        recentFileURLs.removeAll()
        print("🗑️ Recent files cleared")
    }
    
    // MARK: - Private Helper Methods
    
    private func getDefaultiCloudFileURL() -> URL? {
        guard let iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("JuuretKälviällä.txt") else {
            return nil
        }
        
        return Foundation.FileManager.default.fileExists(atPath: iCloudURL.path) ? iCloudURL : nil
    }
    
    private func getDefaultLocalFileURL() -> URL? {
        guard let documentsURL = Foundation.FileManager.default.urls(for: .documentDirectory,
                                                          in: .userDomainMask).first else {
            print("💻 Could not get local Documents directory")
            return nil
        }
        
        let localURL = documentsURL.appendingPathComponent("JuuretKälviällä.txt")
        print("💻 Checking local path: \(localURL.path)")
        
        let exists = Foundation.FileManager.default.fileExists(atPath: localURL.path)
        print("💻 File exists at local path: \(exists)")
        
        return exists ? localURL : nil
    }
    
    private func isFamilyHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        let familyPattern = "^[A-ZÄÖÅ-]+ [IVX0-9]+[ABC]?( II| III| IV)?, PAGE"
        
        do {
            let regex = try NSRegularExpression(pattern: familyPattern)
            let range = NSRange(location: 0, length: trimmed.count)
            return regex.firstMatch(in: trimmed, range: range) != nil
        } catch {
            return trimmed.contains(" ") &&
                   trimmed.contains(",") &&
                   trimmed.contains("PAGE")
        }
    }
}
