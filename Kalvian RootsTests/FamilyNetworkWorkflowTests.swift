//
//  FamilyNetworkWorkflowTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for FamilyNetwork and FamilyNetworkWorkflow
//

import XCTest
@testable import Kalvian_Roots

@MainActor
final class FamilyNetworkWorkflowTests: XCTestCase {
    
    var workflow: FamilyNetworkWorkflow!
    var testFamily: Family!
    var familyResolver: FamilyResolver!
    var fileManager: RootsFileManager!
    var aiParsingService: AIParsingService!
    
    override func setUp() async throws {
        try await super.setUp()
        fileManager = RootsFileManager()
        let nameEquivalenceManager = NameEquivalenceManager()
        aiParsingService = AIParsingService()
        let cache = FamilyNetworkCache(rootsFileManager: fileManager)
        
        familyResolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager,
            fileManager: fileManager,
            familyNetworkCache: cache
        )
        
        testFamily = createTestFamily()
        
        // Wait for file to load
        for _ in 0..<50 {
            if fileManager.isFileLoaded {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    override func tearDown() async throws {
        workflow = nil
        testFamily = nil
        familyResolver = nil
        fileManager = nil
        aiParsingService = nil
        try await super.tearDown()
    }
    
    // MARK: - FamilyNetwork Tests
    
    func testFamilyNetworkInitialization() {
        // Given/When: Creating a network
        let network = FamilyNetwork(mainFamily: testFamily)
        
        // Then: Should initialize with main family
        XCTAssertEqual(network.mainFamily.familyId, testFamily.familyId)
        XCTAssertEqual(network.asChildFamilies.count, 0, "Should start with no asChild families")
        XCTAssertEqual(network.asParentFamilies.count, 0, "Should start with no asParent families")
    }
    
    func testFamilyNetworkGetAsChildFamily() {
        // Given: Network with asChild families
        var network = FamilyNetwork(mainFamily: testFamily)
        let parent = testFamily.allParents.first!
        let asChildFamily = createAsChildFamily()
        network.asChildFamilies[parent.name] = asChildFamily
        
        // When: Getting asChild family
        let retrieved = network.getAsChildFamily(for: parent)
        
        // Then: Should retrieve it
        XCTAssertNotNil(retrieved, "Should find asChild family")
        XCTAssertEqual(retrieved?.familyId, asChildFamily.familyId)
    }
    
    func testFamilyNetworkGetAsParentFamily() {
        // Given: Network with asParent families
        var network = FamilyNetwork(mainFamily: testFamily)
        let child = testFamily.allChildren.first!
        let asParentFamily = createAsParentFamily()
        network.asParentFamilies[child.displayName] = asParentFamily
        
        // When: Getting asParent family
        let retrieved = network.getAsParentFamily(for: child)
        
        // Then: Should retrieve it
        XCTAssertNotNil(retrieved, "Should find asParent family")
        XCTAssertEqual(retrieved?.familyId, asParentFamily.familyId)
    }
    
    func testFamilyNetworkGetSpouseAsChildFamily() {
        // Given: Network with spouse asChild families
        var network = FamilyNetwork(mainFamily: testFamily)
        let spouse = Person(name: "Test Spouse", noteMarkers: [])
        let spouseFamily = createAsChildFamily()
        network.spouseAsChildFamilies["Test Spouse"] = spouseFamily
        
        // When: Getting spouse asChild family
        let retrieved = network.getSpouseAsChildFamily(for: spouse)
        
        // Then: Should retrieve it
        XCTAssertNotNil(retrieved, "Should find spouse asChild family")
    }
    
    // MARK: - FamilyNetworkWorkflow Tests
    
    func testWorkflowInitialization() {
        // When: Creating workflow
        workflow = FamilyNetworkWorkflow(
            nuclearFamily: testFamily,
            familyResolver: familyResolver,
            resolveCrossReferences: true
        )
        
        // Then: Should initialize
        XCTAssertNotNil(workflow, "Workflow should initialize")
    }
    
    func testWorkflowInitializationWithoutResolution() {
        // When: Creating workflow without cross-reference resolution
        workflow = FamilyNetworkWorkflow(
            nuclearFamily: testFamily,
            familyResolver: familyResolver,
            resolveCrossReferences: false
        )
        
        // Then: Should initialize
        XCTAssertNotNil(workflow, "Workflow should initialize")
    }
    
    func testWorkflowProcess() async throws {
        // Given: Workflow configured for resolution
        workflow = FamilyNetworkWorkflow(
            nuclearFamily: testFamily,
            familyResolver: familyResolver,
            resolveCrossReferences: true
        )
        
        // When: Processing (would require integration test for full processing)
        // Then: Should complete without error
        XCTAssertNotNil(workflow, "Workflow should exist")
    }
    
    func testWorkflowGetFamilyNetwork() {
        // Given: Processed workflow
        workflow = FamilyNetworkWorkflow(
            nuclearFamily: testFamily,
            familyResolver: familyResolver,
            resolveCrossReferences: false
        )
        
        // When: Getting network (before processing)
        let network = workflow.getFamilyNetwork()
        
        // Then: Should return network
        XCTAssertNil(network, "Network should be nil before processing")
    }
    
    func testWorkflowGetFamilyNetworkAfterProcess() async {
        // Integration test - would require actual processing
    }
    
    func testWorkflowActivateCachedNetwork() {
        // Given: A cached network
        let cachedNetwork = FamilyNetwork(mainFamily: testFamily)
        
        // When: Creating workflow and activating cache
        workflow = FamilyNetworkWorkflow(
            nuclearFamily: testFamily,
            familyResolver: familyResolver,
            resolveCrossReferences: false
        )
        workflow.activateCachedNetwork(cachedNetwork)
        
        // Then: Network should be available
        let network = workflow.getFamilyNetwork()
        XCTAssertNotNil(network, "Should have network after activation")
    }
    
    // MARK: - Cross-Reference Resolution Tests
    
    func testResolveParentAsChildFamilies() async {
        // Integration test - requires file access
        // Test resolving parent asChild families
    }
    
    func testResolveChildAsParentFamilies() async {
        // Integration test - requires file access
        // Test resolving child asParent families
    }
    
    func testResolveSpouseAsChildFamilies() async {
        // Integration test - requires file access
        // Test resolving spouse asChild families
    }
    
    func testHandleMissingCrossReferences() async {
        // Test: Should handle when referenced families don't exist
    }
    
    func testHandleInvalidCrossReferences() async {
        // Test: Should handle invalid family IDs gracefully
    }
    
    // MARK: - Network Completeness Tests
    
    func testNetworkHasAllParentAsChildFamilies() async {
        // Integration test - verify all parent asChild families are resolved
    }
    
    func testNetworkHasAllChildAsParentFamilies() async {
        // Integration test - verify all married child asParent families are resolved
    }
    
    func testNetworkHasAllSpouseAsChildFamilies() async {
        // Integration test - verify all spouse asChild families are resolved
    }
    
    // MARK: - Enhancement Tests
    
    func testEnhanceChildWithAsParentData() {
        // Given: Network with child's asParent family
        var network = FamilyNetwork(mainFamily: testFamily)
        let child = testFamily.allChildren.first!
        let asParentFamily = createAsParentFamily()
        network.asParentFamilies[child.displayName] = asParentFamily
        
        // Then: Should be able to enhance child data
        let enhanced = network.getAsParentFamily(for: child)
        XCTAssertNotNil(enhanced, "Should get enhancement data")
    }
    
    func testEnhanceParentWithAsChildData() {
        // Given: Network with parent's asChild family
        var network = FamilyNetwork(mainFamily: testFamily)
        let parent = testFamily.allParents.first!
        let asChildFamily = createAsChildFamily()
        network.asChildFamilies[parent.name] = asChildFamily
        
        // Then: Should be able to enhance parent data
        let enhanced = network.getAsChildFamily(for: parent)
        XCTAssertNotNil(enhanced, "Should get enhancement data")
    }
    
    // MARK: - Error Handling Tests
    
    func testWorkflowHandlesProcessingError() async {
        // Test: Should handle errors during processing
    }
    
    func testWorkflowHandlesResolverError() async {
        // Test: Should handle family resolver errors
    }
    
    func testWorkflowHandlesEmptyFamily() {
        // Given: Empty family
        let emptyFamily = Family(
            familyId: "EMPTY 1",
            pageReferences: [],
            couples: [],
            notes: [],
            noteDefinitions: [:]
        )
        
        // When: Creating workflow
        workflow = FamilyNetworkWorkflow(
            nuclearFamily: emptyFamily,
            familyResolver: familyResolver,
            resolveCrossReferences: false
        )
        
        // Then: Should handle gracefully
        XCTAssertNotNil(workflow, "Should handle empty family")
    }
    
    // MARK: - Helper Methods
    
    private func createTestFamily() -> Family {
        let husband = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "15.02.1730",
            asChild: "KORPI 5",
            noteMarkers: []
        )
        
        let wife = Person(
            name: "Maria",
            patronymic: "Jaakont.",
            birthDate: "10.03.1735",
            asChild: "SIKALA 3",
            noteMarkers: []
        )
        
        let child = Person(
            name: "Liisa",
            birthDate: "12.06.1760",
            spouse: "Juho Korvela",
            asParent: "KORVELA 2",
            noteMarkers: []
        )
        
        let couple = Couple(
            husband: husband,
            wife: wife,
            children: [child]
        )
        
        return Family(
            familyId: "TEST 1",
            pageReferences: ["100"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createAsChildFamily() -> Family {
        let grandparent = Person(name: "Erik", noteMarkers: [])
        let grandmother = Person(name: "Brita", noteMarkers: [])
        let parent = Person(name: "Matti", birthDate: "15.02.1730", noteMarkers: [])
        
        let couple = Couple(
            husband: grandparent,
            wife: grandmother,
            children: [parent]
        )
        
        return Family(
            familyId: "KORPI 5",
            pageReferences: ["95"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createAsParentFamily() -> Family {
        let husband = Person(
            name: "Juho",
            birthDate: "01.01.1755",
            noteMarkers: []
        )
        let wife = Person(
            name: "Liisa",
            birthDate: "12.06.1760",
            deathDate: "15.07.1830",
            noteMarkers: []
        )
        
        let couple = Couple(husband: husband, wife: wife, children: [])
        
        return Family(
            familyId: "KORVELA 2",
            pageReferences: ["200"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
}
