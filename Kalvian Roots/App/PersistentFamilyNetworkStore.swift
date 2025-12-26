//
//  PersistentFamilyNetworkStore.swift
//  Kalvian Roots
//
//  Handles persistence of cached family networks inside the iCloud container.
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
    }

    convenience init(rootsFileManager: RootsFileManager, fileManager: FileManager = .default, schemaVersion: Int = 2) {
        if let canonicalURL = rootsFileManager.getCanonicalFileURL() {
            let documentsURL = canonicalURL.deletingLastPathComponent()
            let cacheDirectory = documentsURL.appendingPathComponent("Cache", isDirectory: true)
            let cacheFileURL = cacheDirectory.appendingPathComponent("families.json")
            self.init(cacheFileURL: cacheFileURL, fileManager: fileManager, schemaVersion: schemaVersion)
            logDebug(.cache, "📂 Persistent cache will be stored at \(cacheFileURL.path)")
        } else {
            let fallbackDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("KalvianRootsCache", isDirectory: true)
            let fallbackFileURL = fallbackDirectory.appendingPathComponent("families.json")
            self.init(cacheFileURL: fallbackFileURL, fileManager: fileManager, schemaVersion: schemaVersion)
            logWarn(.cache, "⚠️ Using temporary directory for cache persistence; iCloud container unavailable")
        }
    }

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

    // MARK: - Private Helpers

    private func loadPayload() -> CachePayload? {
        guard fileManager.fileExists(atPath: cacheFileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            if data.isEmpty {
                return nil
            }

            do {
                let payload = try decoder.decode(CachePayload.self, from: data)
                guard payload.schemaVersion == schemaVersion else {
                    logWarn(.cache, "⚠️ Ignoring cache with mismatched schema version \(payload.schemaVersion)")
                    try? removeCacheFile()
                    return nil
                }
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
