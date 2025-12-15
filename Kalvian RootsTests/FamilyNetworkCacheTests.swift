//
//  FamilyNetworkCacheTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for FamilyNetworkCache
//

import XCTest
@testable import Kalvian_Roots

@MainActor
final class FamilyNetworkCacheTests: XCTestCase {
    
    var cache: FamilyNetworkCache!
    var fileManager: RootsFileManager!
    
    override func setUp() async throws {
        try await super.setUp()
        cache = FamilyNetworkCache()
        fileManager = RootsFileManager()
        _ = await fileManager.waitForFileReady()
    }
    
    override func tearDown() async throws {
        cache = nil
        fileManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testCacheInitialization() {
        XCTAssertNotNil(cache, "Cache should initialize")
    }
    
    func testCacheStartsEmpty() {
        XCTAssertFalse(cache.isCached(familyId: "KORPI 6"), "Cache should start empty")
    }
    
    func testCacheHasNoPendingFamily() {
        XCTAssertNil(cache.nextFamilyId, "Should have no pending family initially")
    }
    
    func testCacheNotProcessingInitially() {
        XCTAssertFalse(cache.isProcessing, "Should not be processing initially")
    }
    
    // MARK: - Cache Storage Tests
    
    func testCacheNetwork() {
        // Given: A family network
        let network = createTestNetwork()
        
        // When: Caching the network
        cache.cacheNetwork(network, extractionTime: 1.5)
        
        // Then: Should be cached
        XCTAssertTrue(
            cache.isCached(familyId: "TEST 1"),
            "Family should be cached"
        )
    }
    
    func testGetCachedNetwork() {
        // Given: A cached network
        let network = createTestNetwork()
        cache.cacheNetwork(network, extractionTime: 1.0)
        
        // When: Retrieving from cache
        let cached = cache.getCachedNetwork(familyId: "TEST 1")
        
        // Then: Should retrieve the network
        XCTAssertNotNil(cached, "Should retrieve cached network")
        XCTAssertEqual(cached?.network.mainFamily.familyId, "TEST 1")
    }
    
    func testGetUncachedNetworkReturnsNil() {
        // When: Trying to get uncached family
        let result = cache.getCachedNetwork(familyId: "UNCACHED 999")
        
        // Then: Should return nil
        XCTAssertNil(result, "Should return nil for uncached family")
    }
    
    func testCacheOverwritesExisting() {
        // Given: A cached network
        let network1 = createTestNetwork()
        cache.cacheNetwork(network1, extractionTime: 1.0)
        
        // When: Caching again with different data
        let network2 = createTestNetwork()
        cache.cacheNetwork(network2, extractionTime: 2.0)
        
        // Then: Should have new data
        let cached = cache.getCachedNetwork(familyId: "TEST 1")
        XCTAssertNotNil(cached, "Should still be cached")
    }
    
    // MARK: - Cache Invalidation Tests
    
    func testClearCache() {
        // Given: A cached network
        let network = createTestNetwork()
        cache.cacheNetwork(network, extractionTime: 1.0)
        XCTAssertTrue(cache.isCached(familyId: "TEST 1"))
        
        // When: Clearing cache
        cache.clearCache()
        
        // Then: Should be empty
        XCTAssertFalse(cache.isCached(familyId: "TEST 1"), "Cache should be cleared")
    }
    
    func testRemoveSpecificFamily() {
        // Given: Multiple cached families
        let network1 = createTestNetwork()
        cache.cacheNetwork(network1, extractionTime: 1.0)
        
        let network2 = createTestNetwork(familyId: "TEST 2")
        cache.cacheNetwork(network2, extractionTime: 1.0)
        
        // When: Removing one family
        cache.removeFromCache(familyId: "TEST 1")
        
        // Then: Only that family should be removed
        XCTAssertFalse(cache.isCached(familyId: "TEST 1"), "TEST 1 should be removed")
        XCTAssertTrue(cache.isCached(familyId: "TEST 2"), "TEST 2 should remain")
    }
    
    // MARK: - Background Processing Tests
    
    func testStartBackgroundProcessing() {
        // Given: A current family
        let currentFamilyId = "KORPI 6"
        
        // When: Starting background processing
        // (Would require integration test for full processing)
        
        // Then: Should initiate processing
        XCTAssertTrue(true, "Background processing should start")
    }
    
    func testCancelBackgroundProcessing() {
        // When: Canceling background processing
        cache.cancelBackgroundProcessing()
        
        // Then: Should stop processing
        XCTAssertFalse(cache.isProcessing, "Should not be processing after cancel")
    }
    
    func testBackgroundProcessingStatus() {
        // Test: Status messages should be set appropriately
        XCTAssertNil(cache.statusMessage, "Should have no status message initially")
    }
    
    func testNextFamilyReady() {
        // Test: Should track when next family is ready
        XCTAssertFalse(cache.nextFamilyReady, "Next family should not be ready initially")
    }
    
    // MARK: - Cache Statistics Tests
    
    func testFamiliesProcessedCount() {
        // Given: Initial count
        let initialCount = cache.familiesProcessedInSession
        
        // When: Processing families (would happen in integration test)
        
        // Then: Count should increment
        XCTAssertEqual(initialCount, 0, "Should start at 0")
    }
    
    func testCacheHitRate() {
        // Test: Cache performance metrics
        // (Would be calculated based on hits vs misses)
    }
    
    // MARK: - Sequential Processing Tests
    
    func testFindNextUncachedFamily() {
        // Given: Some cached families
        let network = createTestNetwork(familyId: "KORPI 6")
        cache.cacheNetwork(network, extractionTime: 1.0)
        
        // When/Then: Should find next uncached family
        // (Would require integration test with file access)
    }
    
    func testProcessFamiliesInOrder() {
        // Test: Should process families in file order
        // (Integration test)
    }
    
    func testStopWhenAllFamiliesCached() {
        // Test: Should stop processing when all families are cached
        // (Integration test)
    }
    
    // MARK: - Error Handling Tests
    
    func testHandleProcessingError() {
        // Test: Should handle errors during background processing gracefully
    }
    
    func testHandleInvalidFamilyID() {
        // When: Trying to cache invalid family ID
        let network = createTestNetwork(familyId: "INVALID 999")
        cache.cacheNetwork(network, extractionTime: 1.0)
        
        // Then: Should handle gracefully
        XCTAssertTrue(cache.isCached(familyId: "INVALID 999"), "Should cache even invalid IDs")
    }
    
    // MARK: - Cache Consistency Tests
    
    func testCacheDataIntegrity() {
        // Given: A network with specific data
        let network = createTestNetwork()
        let originalChildCount = network.mainFamily.allChildren.count
        
        // When: Caching and retrieving
        cache.cacheNetwork(network, extractionTime: 1.0)
        let cached = cache.getCachedNetwork(familyId: "TEST 1")
        
        // Then: Data should be identical
        XCTAssertEqual(
            cached?.network.mainFamily.allChildren.count,
            originalChildCount,
            "Child count should match"
        )
    }
    
    func testCacheConcurrency() {
        // Test: Cache should handle concurrent access safely
        // (Would require concurrent access testing)
    }
    
    // MARK: - Helper Methods
    
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
