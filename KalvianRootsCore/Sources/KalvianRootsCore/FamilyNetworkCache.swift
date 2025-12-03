//
//  FamilyNetworkCache.swift
//  Kalvian Roots
//
//  Simple cache for pre-processed family networks
//

import Foundation

/// Simple cache for family networks with optional persistence.
@MainActor
public final class FamilyNetworkCache {

    private let persistenceStore: FamilyNetworkStoring
    private var cachedNetworks: [String: CachedFamily] = [:]

    public private(set) var statusMessage: String?
    public private(set) var nextFamilyReady: Bool = false
    public private(set) var nextFamilyId: String?

    public var cachedFamilyCount: Int {
        cachedNetworks.count
    }

    public init(persistenceStore: FamilyNetworkStoring = InMemoryFamilyNetworkStore()) {
        self.persistenceStore = persistenceStore
        cachedNetworks = persistenceStore.loadAll()
        updateReadyStateFromCache()
    }

    public func isCached(familyId: String) -> Bool {
        cachedNetworks[normalize(familyId)] != nil
    }

    public func getCachedNetwork(familyId: String) -> FamilyNetwork? {
        let normalized = normalize(familyId)
        if let cached = cachedNetworks[normalized] {
            return cached.network
        }

        if let persisted = persistenceStore.loadFamily(withId: normalized) {
            cachedNetworks[normalized] = persisted
            return persisted.network
        }

        return nil
    }

    public func getCachedNuclearFamily(familyId: String) -> Family? {
        getCachedNetwork(familyId: familyId)?.mainFamily
    }

    public func cacheNetwork(_ network: FamilyNetwork, extractionTime: TimeInterval) {
        let normalized = normalize(network.mainFamily.familyId)
        let cached = CachedFamily(network: network, cachedAt: Date(), extractionTime: extractionTime)
        cachedNetworks[normalized] = cached
        persistenceStore.save(cachedNetworks)
        statusMessage = "\(normalized) ready"
        nextFamilyReady = true
        nextFamilyId = normalized
    }

    public func deleteCachedFamily(familyId: String) {
        let normalized = normalize(familyId)
        cachedNetworks.removeValue(forKey: normalized)
        persistenceStore.save(cachedNetworks)
        if nextFamilyId == normalized {
            nextFamilyReady = false
            nextFamilyId = nil
        }
    }

    public func clearCache() {
        cachedNetworks.removeAll()
        nextFamilyReady = false
        nextFamilyId = nil
        statusMessage = nil
        persistenceStore.clear()
    }

    private func updateReadyStateFromCache() {
        guard let latestEntry = cachedNetworks.max(by: { $0.value.cachedAt < $1.value.cachedAt }) else {
            nextFamilyReady = false
            nextFamilyId = nil
            return
        }

        nextFamilyReady = true
        nextFamilyId = latestEntry.key
    }

    private func normalize(_ familyId: String) -> String {
        familyId.uppercased().trimmingCharacters(in: .whitespaces)
    }
}

extension FamilyNetworkCache: FamilyNetworkCaching {}
