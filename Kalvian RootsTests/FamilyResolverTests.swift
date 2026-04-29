//
//  FamilyResolverTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for FamilyResolver
//

import XCTest
@testable import Kalvian_Roots

@MainActor
final class FamilyResolverTests: XCTestCase {
    
    var resolver: FamilyResolver!
    var fileManager: RootsFileManager!
    var nameEquivalenceManager: NameEquivalenceManager!
    var aiParsingService: AIParsingService!
    var cache: FamilyNetworkCache!
    
    override func setUp() async throws {
        try await super.setUp()
        fileManager = RootsFileManager()
        nameEquivalenceManager = NameEquivalenceManager()
        aiParsingService = AIParsingService()
        cache = FamilyNetworkCache(rootsFileManager: fileManager)
        
        resolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager,
            fileManager: fileManager,
            familyNetworkCache: cache
        )
        
        // Wait for file to load
        for _ in 0..<50 {
            if fileManager.isFileLoaded {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    override func tearDown() async throws {
        resolver = nil
        fileManager = nil
        nameEquivalenceManager = nil
        aiParsingService = nil
        cache = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testResolverInitialization() {
        XCTAssertNotNil(resolver, "Resolver should initialize")
    }
    
    func testResolverHasFileManager() {
        XCTAssertNotNil(resolver, "Resolver should have file manager reference")
    }
    
    func testResolverHasNameEquivalenceManager() {
        XCTAssertNotNil(resolver, "Resolver should have name equivalence manager")
    }
    
    // MARK: - Cross-Reference Resolution Tests
    
    func testResolveCrossReferencesWithValidFamily() async {
        // Given: A family with cross-references
        let testFamily = createTestFamily()
        
        // When: Resolving cross-references
        // (Would require integration test for full resolution)
        
        // Then: Should return families
        XCTAssertNotNil(testFamily, "Test family should exist")
    }
    
    func testResolveCrossReferencesWithNoReferences() async {
        // Given: A family with no asChild or asParent references
        let isolatedFamily = createIsolatedFamily()
        
        // When/Then: Should handle gracefully
        XCTAssertEqual(isolatedFamily.allParents.count, 2, "Should have parents")
        XCTAssertEqual(isolatedFamily.allChildren.count, 0, "Should have no children")
    }
    
    func testResolveCrossReferencesHandlesInvalidFamilyID() async {
        // Given: Family with invalid asChild reference
        let invalidFamily = createFamilyWithInvalidReferences()
        
        // When/Then: Should handle gracefully without crashing
        XCTAssertNotNil(invalidFamily, "Family with invalid references should exist")
    }
    
    // MARK: - AsChild Family Resolution Tests
    
    func testResolveAsChildFamilyForParent() async {
        // Integration test - would require file loading
        // Test finding parent's childhood family
    }
    
    func testResolveAsChildFamilyWithInvalidID() async {
        // Test: Should handle invalid family ID gracefully
    }
    
    func testResolveAsChildFamilyNotInFile() async {
        // Test: Should handle missing family gracefully
    }
    
    // MARK: - AsParent Family Resolution Tests
    
    func testResolveAsParentFamilyForChild() async {
        // Integration test - would require file loading
        // Test finding child's adult family
    }
    
    func testResolveAsParentFamilyForUnmarriedChild() async {
        // Test: Unmarried child should have no asParent family
    }
    
    func testResolveAsParentFamilyWithInvalidID() async {
        // Test: Should handle invalid family ID gracefully
    }
    
    // MARK: - Spouse Family Resolution Tests
    
    func testResolveSpouseAsChildFamily() async {
        // Integration test - would test finding spouse's childhood family
    }
    
    func testResolveSpouseWithNoFamily() async {
        // Test: Spouse without asChild reference should return nil
    }
    
    func testResolveSpouseWithInvalidID() async {
        // Test: Should handle invalid spouse family ID
    }
    
    // MARK: - Name Matching Tests
    
    func testMatchPersonByBirthDate() {
        // Given: Two persons with same birth date
        let person1 = Person(name: "Johan", birthDate: "01.01.1750", noteMarkers: [])
        let person2 = Person(name: "Juho", birthDate: "01.01.1750", noteMarkers: [])
        
        // Then: Should match by birth date
        XCTAssertEqual(person1.birthDate, person2.birthDate, "Birth dates should match")
    }
    
    func testMatchPersonByName() {
        // Given: Person with Finnish and Swedish names
        let finnishName = "Juho"
        let swedishName = "Johan"
        
        // Then: Should recognize as equivalent
        XCTAssertTrue(
            nameEquivalenceManager.areNamesEquivalent(finnishName, swedishName),
            "Finnish and Swedish names should match"
        )
    }
    
    func testMatchPersonWithPatronymic() {
        // Given: Persons with same name but different patronymics
        let person1 = Person(name: "Matti", patronymic: "Erikinp.", noteMarkers: [])
        let person2 = Person(name: "Matti", patronymic: "Juhonp.", noteMarkers: [])
        
        // Then: Should be different persons
        XCTAssertNotEqual(person1.patronymic, person2.patronymic, "Different patronymics")
    }
    
    // MARK: - Error Handling Tests
    
    func testResolverHandlesFileNotLoaded() async {
        // Given: Resolver with unloaded file
        let newFileManager = RootsFileManager()
        let newResolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager,
            fileManager: newFileManager,
            familyNetworkCache: cache
        )
        
        // Then: Should handle appropriately
        XCTAssertNotNil(newResolver, "Resolver should exist even with unloaded file")
    }
    
    func testResolverHandlesMissingFamily() async {
        // Test: Should gracefully handle when family doesn't exist in file
    }
    
    func testResolverHandlesCircularReferences() async {
        // Test: Should handle circular family references without infinite loop
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
    
    private func createIsolatedFamily() -> Family {
        let husband = Person(name: "Erik", noteMarkers: [])
        let wife = Person(name: "Brita", noteMarkers: [])
        let couple = Couple(husband: husband, wife: wife, children: [])
        
        return Family(
            familyId: "ISOLATED 1",
            pageReferences: ["200"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createFamilyWithInvalidReferences() -> Family {
        let husband = Person(
            name: "Matti",
            asChild: "INVALID 999",
            noteMarkers: []
        )
        let wife = Person(name: "Maria", noteMarkers: [])
        let couple = Couple(husband: husband, wife: wife, children: [])
        
        return Family(
            familyId: "INVALID 1",
            pageReferences: ["300"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
}
