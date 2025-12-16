//
//  FamilyNetworkCacheTests.swift
//  Kalvian Roots Tests
//

import XCTest
@testable import Kalvian_Roots

@MainActor
final class FamilyNetworkCacheTests: XCTestCase {

    private var cache: FamilyNetworkCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = FamilyNetworkCache()
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    // MARK: - Initialization

    func testCacheInitialization() {
        XCTAssertNotNil(cache)
    }

    func testCacheStartsEmpty() {
        XCTAssertFalse(cache.isCached(familyId: "KORPI 6"))
    }

    // MARK: - Cache Storage

    func testCacheNetworkStoresFamily() {
        let network = createTestNetwork()

        cache.cacheNetwork(network, extractionTime: 1.5)

        XCTAssertTrue(cache.isCached(familyId: "TEST 1"))
    }

    func testGetCachedNetworkReturnsStoredFamily() {
        let network = createTestNetwork()
        cache.cacheNetwork(network, extractionTime: 1.0)

        let cached = cache.getCachedNetwork(familyId: "TEST 1")

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.mainFamily.familyId, "TEST 1")
    }

    func testGetUncachedNetworkReturnsNil() {
        let result = cache.getCachedNetwork(familyId: "UNCACHED 999")

        XCTAssertNil(result)
    }

    func testCacheOverwritesExistingEntry() {
        let firstNetwork = createTestNetwork()
        cache.cacheNetwork(firstNetwork, extractionTime: 1.0)

        let updatedNetwork = createTestNetwork(familyId: "TEST 1")
        cache.cacheNetwork(updatedNetwork, extractionTime: 2.0)

        XCTAssertNotNil(cache.getCachedNetwork(familyId: "TEST 1"))
    }

    // MARK: - Cache Clearing

    func testClearCacheRemovesStoredFamilies() {
        let network = createTestNetwork()
        cache.cacheNetwork(network, extractionTime: 1.0)

        cache.clearCache()

        XCTAssertFalse(cache.isCached(familyId: "TEST 1"))
    }

    // MARK: - Edge Cases

    func testCachingInvalidFamilyIdStillStoresData() {
        let network = createTestNetwork(familyId: "INVALID 999")

        cache.cacheNetwork(network, extractionTime: 1.0)

        XCTAssertTrue(cache.isCached(familyId: "INVALID 999"))
    }

    // MARK: - Helpers

    private func createTestNetwork(familyId: String = "TEST 1") -> FamilyNetwork {
        let husband = Person(name: "Matti", birthDate: "01.01.1750", noteMarkers: [])
        let wife = Person(name: "Maria", birthDate: "01.01.1755", noteMarkers: [])
        let child = Person(name: "Liisa", birthDate: "01.01.1780", noteMarkers: [])

        let couple = Couple(husband: husband, wife: wife, children: [child])
        let family = Family(
            familyId: familyId,
            pageReferences: ["100"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )

        return FamilyNetwork(mainFamily: family)
    }
}
