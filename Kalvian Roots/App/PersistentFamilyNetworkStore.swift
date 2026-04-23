//
//  PersistentFamilyNetworkStore.swift
//  Kalvian Roots
//
//  Handles persistence of cached family networks inside the iCloud container.
//  Includes proper iCloud sync handling to ensure cache is shared across devices.
//
//  IMPORTANT: Both iOS and macOS use the app's ubiquity container for cache storage.
//  This ensures the cache is shared across all devices via iCloud sync.
//

import Foundation

@MainActor
final class PersistentFamilyNetworkStore {

    private struct CachePayload: Codable {
        let schemaVersion: Int
        let families: [String: FamilyNetworkCache.CachedFamily]
    }

    private let fileManager: FileManager
    private let cacheDirectoryURL: URL
    private let cacheFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let schemaVersion: Int
    
    /// Callback when iCloud delivers updated cache file
    var onCacheUpdatedFromCloud: (() -> Void)?
    
    /// Metadata query for monitoring iCloud changes
    private var metadataQuery: NSMetadataQuery?

    init(cacheFileURL: URL, fileManager: FileManager = .default, schemaVersion: Int = 2) {
        self.fileManager = fileManager
        self.cacheFileURL = cacheFileURL
        self.cacheDirectoryURL = cacheFileURL.deletingLastPathComponent()
        self.schemaVersion = schemaVersion

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        
        // Start monitoring for iCloud changes
        startMonitoringICloudChanges()
    }

    convenience init(rootsFileManager: RootsFileManager, fileManager: FileManager = .default, schemaVersion: Int = 2) {
        // UNIFIED: Both iOS and macOS use the app's own ubiquity container for cache.
        // This ensures the cache is shared across all devices via iCloud sync.
        // The app always has access to its own container without security-scoped bookmarks.
        if let appContainer = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let cacheDirectory = appContainer.appendingPathComponent("Documents/Cache", isDirectory: true)
            let cacheFileURL = cacheDirectory.appendingPathComponent("families.json")
            self.init(cacheFileURL: cacheFileURL, fileManager: fileManager, schemaVersion: schemaVersion)
            #if os(iOS)
            logDebug(.cache, "📂 iOS: Persistent cache at \(cacheFileURL.path)")
            #else
            logDebug(.cache, "📂 macOS: Persistent cache at \(cacheFileURL.path)")
            #endif
            return
        }
        
        if let fallbackFileURL = Self.durableFallbackCacheFileURL(fileManager: fileManager) {
            self.init(cacheFileURL: fallbackFileURL, fileManager: fileManager, schemaVersion: schemaVersion)
            logWarn(.cache, "⚠️ iCloud container unavailable; using durable cache at \(fallbackFileURL.path)")
            return
        }

        let fallbackDirectory = Self.applicationSupportCacheDirectory(fileManager: fileManager)
        let fallbackFileURL = fallbackDirectory.appendingPathComponent("families.json")
        self.init(cacheFileURL: fallbackFileURL, fileManager: fileManager, schemaVersion: schemaVersion)
        logWarn(.cache, "⚠️ iCloud container unavailable; using Application Support cache at \(fallbackFileURL.path)")
    }
    
    deinit {
        metadataQuery?.stop()
        metadataQuery = nil
    }
    
    // MARK: - Public Methods

    func loadAll() -> [String: FamilyNetworkCache.CachedFamily] {
        // Ensure file is downloaded from iCloud before reading
        ensureFileDownloaded()
        return loadPayload()?.families ?? [:]
    }

    func loadFamily(withId id: String) -> FamilyNetworkCache.CachedFamily? {
        ensureFileDownloaded()
        return loadPayload()?.families[id]
    }

    func save(_ families: [String: FamilyNetworkCache.CachedFamily]) {
        do {
            if families.isEmpty {
                try removeCacheFile()
                return
            }

            let payload = CachePayload(schemaVersion: schemaVersion, families: families)
            try writePayload(payload)
            logDebug(.cache, "💾 Persisted \(families.count) family networks to disk")
        } catch {
            logError(.cache, "❌ Failed to persist family cache: \(error)")
        }
    }

    func clear() {
        do {
            try removeCacheFile()
        } catch {
            logError(.cache, "❌ Failed to clear persisted cache: \(error)")
        }
    }
    
    /// Force a reload from iCloud (useful after receiving sync notification)
    func reloadFromCloud() -> [String: FamilyNetworkCache.CachedFamily] {
        logInfo(.cache, "☁️ Reloading cache from iCloud")
        ensureFileDownloaded()
        return loadPayload()?.families ?? [:]
    }

    // MARK: - iCloud Sync Handling
    
    /// Ensure the cache file is downloaded from iCloud if it exists remotely
    private func ensureFileDownloaded() {
        // First, ensure the cache directory exists
        try? ensureCacheDirectory()
        
        // Check if this is an iCloud URL (ubiquity container)
        guard cacheFileURL.path.contains("Mobile Documents") ||
              cacheFileURL.path.contains("iCloud") ||
              isUbiquitousItem(at: cacheFileURL) else {
            // Not an iCloud URL, skip download check
            return
        }
        
        do {
            // Check the download status of the file
            let resourceValues = try cacheFileURL.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ])
            
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                if status == .notDownloaded {
                    // File exists in iCloud but not downloaded - trigger download
                    logInfo(.cache, "☁️ Cache file exists in iCloud but not downloaded locally - triggering download")
                    try fileManager.startDownloadingUbiquitousItem(at: cacheFileURL)
                    
                    // Wait briefly for download to start/complete
                    waitForDownload()
                } else if status == .current {
                    // File is downloaded and up to date
                    logDebug(.cache, "✅ Cache file is downloaded and current")
                } else if status == .downloaded {
                    // File is downloaded but might not be the latest
                    logDebug(.cache, "✅ Cache file is downloaded (may need refresh)")
                } else {
                    // Unknown status - log and continue
                    logDebug(.cache, "📂 iCloud download status: \(status)")
                }
            }
        } catch {
            // File might not exist in iCloud yet, which is normal for first device
            logDebug(.cache, "📂 Cache file not in iCloud yet (normal for first device): \(error.localizedDescription)")
        }
    }
    
    /// Check if a URL is in an iCloud ubiquity container
    private func isUbiquitousItem(at url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            return resourceValues.isUbiquitousItem ?? false
        } catch {
            return false
        }
    }
    
    /// Wait briefly for iCloud download to complete
    private func waitForDownload() {
        // Give iCloud a moment to download the file
        // This is a simple approach - for large files you'd want async handling
        let maxWaitTime: TimeInterval = 5.0
        let checkInterval: TimeInterval = 0.1
        var waited: TimeInterval = 0
        
        while waited < maxWaitTime {
            Thread.sleep(forTimeInterval: checkInterval)
            waited += checkInterval
            
            // Check if file is now available
            if fileManager.fileExists(atPath: cacheFileURL.path) {
                do {
                    let resourceValues = try cacheFileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    if let status = resourceValues.ubiquitousItemDownloadingStatus,
                       status == .current || status == .downloaded {
                        logInfo(.cache, "☁️ iCloud download complete after \(String(format: "%.1f", waited))s")
                        return
                    }
                } catch {
                    // Continue waiting
                }
            }
        }
        
        logWarn(.cache, "⚠️ iCloud download did not complete within \(maxWaitTime)s - proceeding anyway")
    }
    
    // MARK: - iCloud Change Monitoring
    
    /// Start monitoring for iCloud file changes
    private func startMonitoringICloudChanges() {
        // Only monitor if we're using iCloud storage
        guard cacheFileURL.path.contains("Mobile Documents") ||
              cacheFileURL.path.contains("iCloud") else {
            logDebug(.cache, "📂 Not using iCloud storage - skipping change monitoring")
            return
        }
        
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "families.json")
        
        // Listen for updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        
        query.start()
        self.metadataQuery = query
        
        logInfo(.cache, "☁️ Started monitoring iCloud for cache updates")
    }
    
    /// Stop monitoring iCloud changes
    private func stopMonitoringICloudChanges() {
        metadataQuery?.stop()
        metadataQuery = nil
        
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: nil)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: nil)
    }
    
    @objc private func metadataQueryDidFinishGathering(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        defer { query.enableUpdates() }
        
        if query.resultCount > 0 {
            logInfo(.cache, "☁️ Found cache file in iCloud during initial scan")
        }
    }
    
    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        
        query.disableUpdates()
        defer { query.enableUpdates() }
        
        // Check if our cache file was updated
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let itemURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                continue
            }
            
            if itemURL.lastPathComponent == "families.json" {
                logInfo(.cache, "☁️ Cache file updated in iCloud - notifying for reload")
                
                // Notify that cache was updated from cloud
                Task { @MainActor in
                    self.onCacheUpdatedFromCloud?()
                }
                break
            }
        }
    }

    // MARK: - Private Helpers

    private static func durableFallbackCacheFileURL(fileManager: FileManager) -> URL? {
        let candidateFiles = [
            manuallyResolvedICloudCacheFileURL(fileManager: fileManager),
            localDocumentsCacheDirectory(fileManager: fileManager)?.appendingPathComponent("families.json"),
            applicationSupportCacheDirectory(fileManager: fileManager).appendingPathComponent("families.json")
        ].compactMap { $0 }

        return candidateFiles.first { fileManager.fileExists(atPath: $0.path) }
    }

    private static func manuallyResolvedICloudCacheFileURL(fileManager: FileManager) -> URL? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }

        let containerName = "iCloud~" + bundleIdentifier.replacingOccurrences(of: ".", with: "~")
        return libraryDirectory
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent(containerName, isDirectory: true)
            .appendingPathComponent("Documents/Cache/families.json")
    }

    private static func localDocumentsCacheDirectory(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Cache", isDirectory: true)
    }

    private static func applicationSupportCacheDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return baseDirectory
            .appendingPathComponent("Kalvian Roots", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
    }

    private func loadPayload() -> CachePayload? {
        guard fileManager.fileExists(atPath: cacheFileURL.path) else {
            logDebug(.cache, "📂 No cache file exists at \(cacheFileURL.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            if data.isEmpty {
                logDebug(.cache, "📂 Cache file is empty")
                return nil
            }

            do {
                let payload = try decoder.decode(CachePayload.self, from: data)
                guard payload.schemaVersion == schemaVersion else {
                    logWarn(.cache, "⚠️ Ignoring cache with mismatched schema version \(payload.schemaVersion)")
                    try? removeCacheFile()
                    return nil
                }
                logDebug(.cache, "✅ Loaded \(payload.families.count) families from cache")
                return payload
            } catch {
                if let legacyFamilies = try? decoder.decode([String: FamilyNetworkCache.CachedFamily].self, from: data) {
                    logWarn(.cache, "♻️ Migrating legacy cache file without schema version")
                    let payload = CachePayload(schemaVersion: schemaVersion, families: legacyFamilies)
                    try? writePayload(payload)
                    return payload
                }

                logError(.cache, "❌ Failed to decode persisted cache: \(error)")
                try? removeCacheFile()
                return nil
            }
        } catch {
            logError(.cache, "❌ Failed to load cache data: \(error)")
            return nil
        }
    }

    private func ensureCacheDirectory() throws {
        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            logDebug(.cache, "📁 Created cache directory at \(cacheDirectoryURL.path)")
        }
    }

    private func writePayload(_ payload: CachePayload) throws {
        try ensureCacheDirectory()
        let data = try encoder.encode(payload)
        try data.write(to: cacheFileURL, options: [.atomic])
    }

    private func removeCacheFile() throws {
        if fileManager.fileExists(atPath: cacheFileURL.path) {
            try fileManager.removeItem(at: cacheFileURL)
            logDebug(.cache, "🧹 Removed persisted family cache at \(cacheFileURL.path)")
        }
    }
}
