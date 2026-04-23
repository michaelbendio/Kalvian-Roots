//
//  PersistentFamilyNetworkStore.swift
//  Kalvian Roots
//
//  Handles local durable persistence of cached family networks.
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

        do {
            try ensureCacheDirectory()
        } catch {
            fatalError("Persistent family cache directory is not accessible: \(error)")
        }
    }

    convenience init(rootsFileManager: RootsFileManager, fileManager: FileManager = .default, schemaVersion: Int = 2) {
        let cacheDirectory = Self.applicationSupportCacheDirectory(fileManager: fileManager)
        let cacheFileURL = cacheDirectory.appendingPathComponent("families.json")
        self.init(cacheFileURL: cacheFileURL, fileManager: fileManager, schemaVersion: schemaVersion)
        logDebug(.cache, "📂 Persistent cache at \(cacheFileURL.path)")
    }
    
    // MARK: - Public Methods

    func loadAll() -> [String: FamilyNetworkCache.CachedFamily] {
        return loadPayload()?.families ?? [:]
    }

    func loadFamily(withId id: String) -> FamilyNetworkCache.CachedFamily? {
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
            fatalError("Failed to persist family cache: \(error)")
        }
    }

    func clear() {
        do {
            try removeCacheFile()
        } catch {
            fatalError("Failed to clear persisted family cache: \(error)")
        }
    }

    // MARK: - Private Helpers

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
            fatalError("Failed to load persisted family cache: \(error)")
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
