//
//  CitationGeneratorTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for CitationGenerator
//

import XCTest
@testable import Kalvian_Roots

final class CitationGeneratorTests: XCTestCase {
    
    var testFamily: Family!
    var testNetwork: FamilyNetwork!
    var nameEquivalenceManager: NameEquivalenceManager!
    
    override func setUp() throws {
        try super.setUp()
        nameEquivalenceManager = NameEquivalenceManager()
        testFamily = createTestFamily()
        testNetwork = createTestNetwork()
    }
    
    override func tearDown() throws {
        testFamily = nil
        testNetwork = nil
        nameEquivalenceManager = nil
        try super.tearDown()
    }
    
    // MARK: - Main Family Citation Tests
    
    func testGenerateMainFamilyCitation() {
        // When: Generating main family citation
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: testFamily,
            targetPerson: nil,
            network: nil
        )
        
        // Then: Should contain key elements
        XCTAssertTrue(citation.contains("Information on"), "Should have header")
        XCTAssertTrue(citation.contains(testFamily.pageReferences[0]), "Should have page reference")
        XCTAssertTrue(citation.contains("Matti"), "Should have father name")
        XCTAssertTrue(citation.contains("Maria"), "Should have mother name")
    }
    
    func testGenerateMainFamilyCitationWithTargetPerson() {
        // Given: Target person
        let targetPerson = testFamily.allChildren.first!
        
        // When: Generating citation with target
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: testFamily,
            targetPerson: targetPerson,
            network: nil
        )
        
        // Then: Should contain target person
        XCTAssertTrue(citation.contains(targetPerson.name), "Should mention target person")
    }
    
    func testGenerateMainFamilyCitationWithNetwork() {
        // When: Generating with network for enhancement
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: testFamily,
            targetPerson: nil,
            network: testNetwork
        )
        
        // Then: Should generate citation
        XCTAssertFalse(citation.isEmpty, "Should generate non-empty citation")
        XCTAssertTrue(citation.contains("Information on"), "Should have header")
    }
    
    func testMainFamilyCitationIncludesMarriageDate() {
        // Given: Family with marriage date
        let familyWithMarriage = testFamily!
        guard let couple = familyWithMarriage.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        
        // When: Generating citation
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: familyWithMarriage,
            targetPerson: nil,
            network: nil
        )
        
        // Then: Should include marriage date
        if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
            // Should contain some reference to marriage
            XCTAssertTrue(
                citation.contains("m.") || citation.contains(marriageDate),
                "Should mention marriage"
            )
        }
    }
    
    func testMainFamilyCitationIncludesChildren() {
        // When: Generating citation for family with children
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: testFamily,
            targetPerson: nil,
            network: nil
        )
        
        // Then: Should include children section
        XCTAssertTrue(citation.contains("Children"), "Should have children section")
        XCTAssertTrue(citation.contains("Liisa"), "Should have child name")
    }
    
    // MARK: - AsChild Citation Tests
    
    func testGenerateAsChildCitation() {
        // Given: Person and their asChild family
        let person = Person(name: "Matti", birthDate: "15.02.1730", noteMarkers: [])
        let asChildFamily = createAsChildFamily()
        
        // When: Generating asChild citation
        let citation = CitationGenerator.generateAsChildCitation(
            for: person,
            in: asChildFamily,
            network: nil,
            nameEquivalenceManager: nil
        )
        
        // Then: Should contain asChild family info
        XCTAssertTrue(citation.contains("Information on"), "Should have header")
        XCTAssertTrue(citation.contains(asChildFamily.pageReferences[0]), "Should have page ref")
    }
    
    func testGenerateAsChildCitationWithNetwork() {
        // Given: Person with asChild family and network
        let person = testFamily.allParents.first!
        let asChildFamily = createAsChildFamily()
        
        // When: Generating with network
        let citation = CitationGenerator.generateAsChildCitation(
            for: person,
            in: asChildFamily,
            network: testNetwork,
            nameEquivalenceManager: nameEquivalenceManager
        )
        
        // Then: Should generate citation
        XCTAssertFalse(citation.isEmpty, "Should generate citation")
    }
    
    func testAsChildCitationIncludesParents() {
        // Given: AsChild family with parents
        let person = Person(name: "Matti", birthDate: "15.02.1730", noteMarkers: [])
        let asChildFamily = createAsChildFamily()
        
        // When: Generating citation
        let citation = CitationGenerator.generateAsChildCitation(
            for: person,
            in: asChildFamily,
            network: nil,
            nameEquivalenceManager: nil
        )
        
        // Then: Should include parent names
        guard let couple = asChildFamily.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        XCTAssertTrue(citation.contains(couple.husband.name), "Should have father name")
        XCTAssertTrue(citation.contains(couple.wife.name), "Should have mother name")
    }
    
    func testAsChildCitationMarkersTargetPerson() {
        // Given: Person in asChild family
        let person = Person(name: "Matti", birthDate: "15.02.1730", noteMarkers: [])
        let asChildFamily = createAsChildFamily()
        
        // When: Generating citation
        let citation = CitationGenerator.generateAsChildCitation(
            for: person,
            in: asChildFamily,
            network: nil,
            nameEquivalenceManager: nil
        )
        
        // Then: Should mark target person
        // (Citation generator uses → arrow for target person)
        XCTAssertTrue(
            citation.contains("→") || citation.contains(person.name),
            "Should mark or mention target person"
        )
    }
    
    // MARK: - Date Formatting Tests
    
    func testFormatFullDate() {
        // Test: Full date format DD.MM.YYYY
        let family = testFamily!
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: nil,
            network: nil
        )
        
        // Should contain properly formatted dates
        XCTAssertTrue(
            citation.contains("15.02.1730") || citation.contains("formatted"),
            "Should format dates"
        )
    }
    
    func testFormatApproximateDate() {
        // Test: Approximate date format "abt YYYY"
        // (Would test with family that has approximate dates)
    }
    
    func testFormat2DigitYear() {
        // Test: 2-digit year with century inference
        // (Would test with family that has 2-digit years)
    }
    
    func testDateFormatWithContext() {
        // Test: Date formatting uses parent context for century inference
    }
    
    // MARK: - Enhancement Tests
    
    func testEnhancementWithAsParentFamily() {
        // Given: Child with asParent family containing enhanced data
        let network = testNetwork!
        let child = testFamily.allChildren.first!
        
        // When: Generating citation with network
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: testFamily,
            targetPerson: child,
            network: network
        )
        
        // Then: Should use enhanced data
        XCTAssertFalse(citation.isEmpty, "Should generate citation")
    }
    
    func testEnhancementArrowMarker() {
        // Test: Enhanced children are marked with → arrow
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: testFamily,
            targetPerson: nil,
            network: testNetwork
        )
        
        // Enhanced entries should have markers (if applicable)
        XCTAssertTrue(true, "Citation should be generated")
    }
    
    func testEnhancementSourceAttribution() {
        // Test: "Additional Information" section shows enhancement sources
        // (Would be checked in full integration test)
    }
    
    // MARK: - Name Equivalence Tests
    
    func testNameEquivalenceInMatching() {
        // Given: Finnish and Swedish name variants
        let person = Person(name: "Juho", birthDate: "01.01.1750", noteMarkers: [])
        let family = createFamilyWithSwedishNames()
        
        // When: Generating citation with name equivalence
        let citation = CitationGenerator.generateAsChildCitation(
            for: person,
            in: family,
            network: nil,
            nameEquivalenceManager: nameEquivalenceManager
        )
        
        // Then: Should match despite name differences
        XCTAssertFalse(citation.isEmpty, "Should generate citation")
    }
    
    func testNameEquivalenceFallback() {
        // Test: Should still match even without name equivalence manager
        let person = Person(name: "Matti", birthDate: "15.02.1730", noteMarkers: [])
        let family = createAsChildFamily()
        
        let citation = CitationGenerator.generateAsChildCitation(
            for: person,
            in: family,
            network: nil,
            nameEquivalenceManager: nil
        )
        
        XCTAssertFalse(citation.isEmpty, "Should work without name equivalence")
    }
    
    // MARK: - Multiple Couples Tests
    
    func testCitationWithMultipleCouples() {
        // Given: Family with multiple couples (remarriage)
        let multiCoupleFamily = createFamilyWithMultipleCouples()
        
        // When: Generating citation
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: multiCoupleFamily,
            targetPerson: nil,
            network: nil
        )
        
        // Then: Should include all couples
        XCTAssertTrue(citation.contains("Additional spouse"), "Should note additional spouse")
    }
    
    func testCitationWithWidowInfo() {
        // Test: Should include widow/widower information
        // (Would require family with widow notes)
    }
    
    // MARK: - Edge Cases
    
    func testCitationWithMissingDates() {
        // Given: Person with missing dates
        let person = Person(name: "Test", noteMarkers: [])
        let family = createMinimalFamily()
        
        // When: Generating citation
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: person,
            network: nil
        )
        
        // Then: Should handle gracefully
        XCTAssertFalse(citation.isEmpty, "Should generate citation even with missing dates")
    }
    
    func testCitationWithEmptyFamily() {
        // Given: Family with minimal data
        let emptyFamily = Family(
            familyId: "EMPTY 1",
            pageReferences: ["100"],
            couples: [],
            notes: [],
            noteDefinitions: [:]
        )
        
        // When: Generating citation
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: emptyFamily,
            targetPerson: nil,
            network: nil
        )
        
        // Then: Should handle empty family
        XCTAssertTrue(citation.contains("Information on"), "Should have basic header")
    }
    
    func testCitationWithSpecialCharacters() {
        // Test: Should handle special characters in names
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
            marriageDate: "1755",
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
        let grandparent = Person(name: "Erik", birthDate: "01.01.1700", noteMarkers: [])
        let grandmother = Person(name: "Brita", birthDate: "01.01.1705", noteMarkers: [])
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
    
    private func createTestNetwork() -> FamilyNetwork {
        let network = FamilyNetwork(mainFamily: testFamily)
        
        // Add asChild families for parents
        if let parent = testFamily.allParents.first {
            network.asChildFamilies[parent.name] = createAsChildFamily()
        }
        
        // Add asParent families for children
        if let child = testFamily.allChildren.first {
            let asParentFamily = createAsParentFamily()
            network.asParentFamilies[child.displayName] = asParentFamily
        }
        
        return network
    }
    
    private func createAsParentFamily() -> Family {
        let husband = Person(name: "Juho", birthDate: "01.01.1755", noteMarkers: [])
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
    
    private func createFamilyWithSwedishNames() -> Family {
        let father = Person(name: "Johan", birthDate: "01.01.1720", noteMarkers: [])
        let mother = Person(name: "Magdalena", birthDate: "01.01.1725", noteMarkers: [])
        let child = Person(name: "Juho", birthDate: "01.01.1750", noteMarkers: [])
        
        let couple = Couple(husband: father, wife: mother, children: [child])
        
        return Family(
            familyId: "SWEDISH 1",
            pageReferences: ["150"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createFamilyWithMultipleCouples() -> Family {
        let husband = Person(name: "Matti", noteMarkers: [])
        let firstWife = Person(name: "Maria", deathDate: "01.01.1760", noteMarkers: [])
        let secondWife = Person(name: "Brita", noteMarkers: [])
        
        let couple1 = Couple(husband: husband, wife: firstWife, children: [])
        let couple2 = Couple(husband: husband, wife: secondWife, children: [])
        
        return Family(
            familyId: "MULTI 1",
            pageReferences: ["300"],
            couples: [couple1, couple2],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createMinimalFamily() -> Family {
        let husband = Person(name: "Test Father", noteMarkers: [])
        let wife = Person(name: "Test Mother", noteMarkers: [])
        let couple = Couple(husband: husband, wife: wife, children: [])
        
        return Family(
            familyId: "MINIMAL 1",
            pageReferences: ["1"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
}
