import Foundation

public protocol FamilyParsingService {
    func parseFamily(familyId: String, familyText: String) async throws -> Family
}

public protocol FamilyFileManaging {
    func extractFamilyText(familyId: String) -> String?
    func findNextFamilyId(after familyId: String) -> String?
    func getAllFamilyIds() -> [String]
}

@MainActor
public protocol FamilyNetworkCaching {
    func getCachedNuclearFamily(familyId: String) -> Family?
}

public struct CachedFamily: Codable, Sendable {
    public let network: FamilyNetwork
    public let cachedAt: Date
    public let extractionTime: TimeInterval

    public init(network: FamilyNetwork, cachedAt: Date, extractionTime: TimeInterval) {
        self.network = network
        self.cachedAt = cachedAt
        self.extractionTime = extractionTime
    }
}

public protocol FamilyNetworkStoring {
    func loadFamily(withId id: String) -> CachedFamily?
    func loadAll() -> [String: CachedFamily]
    func save(_ cached: [String: CachedFamily])
    func clear()
}

public final class InMemoryFamilyNetworkStore: FamilyNetworkStoring {
    private var store: [String: CachedFamily] = [:]

    public init() {}

    public func loadFamily(withId id: String) -> CachedFamily? {
        store[id]
    }

    public func loadAll() -> [String: CachedFamily] {
        store
    }

    public func save(_ cached: [String: CachedFamily]) {
        store = cached
    }

    public func clear() {
        store.removeAll()
    }
}
