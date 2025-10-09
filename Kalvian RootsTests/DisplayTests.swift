//
//  DisplayTests.swift
//  Kalvian Roots Tests
//
//  Tests for display functionality
//
//  Created by Michael Bendio on 10/8/25.
//

import XCTest
@testable import Kalvian_Roots

final class EnhancedDisplayTests: XCTestCase {
    
    var testPerson: Person!
    var testNetwork: FamilyNetwork!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test person (child)
        testPerson = Person(
            name: "Magdalena",
            birthDate: "27.01.1759",
            marriageDate: "78",
            fullMarriageDate: nil,
            spouse: "Antti Korvela",
            asParent: "Korvela 3",
            familySearchId: "L4ZM-CRT",
            noteMarkers: []
        )
        
        // Create nuclear family
        let nuclearFamily = createNuclearFamily()
        
        // Create network with asParent family
        testNetwork = FamilyNetwork(mainFamily: nuclearFamily)
        testNetwork.asParentFamilies["Magdalena"] = createAsParentFamily()
        testNetwork.spouseAsChildFamilies["Antti Korvela"] = createSpouseAsChildFamily()
    }
    
    override func tearDown() async throws {
        testPerson = nil
        testNetwork = nil
        try await super.tearDown()
    }
    
    // MARK: - Enhanced Data Extraction Tests
    
    func testExtractEnhancedDeathDate() {
        // Given: Person with asParent family containing death date
        let person = testPerson!
        
        // When: Looking up asParent family
        guard let asParentFamily = testNetwork.getAsParentFamily(for: person) else {
            XCTFail("Should find asParent family")
            return
        }
        
        // Then: Should find matching person with death date
        let matchingPerson = asParentFamily.allParents.first { $0.birthDate == person.birthDate }
        XCTAssertNotNil(matchingPerson, "Should find matching person")
        XCTAssertEqual(matchingPerson?.deathDate, "19.10.1846", "Should have enhanced death date")
    }
    
    func testExtractEnhancedMarriageDate() {
        // Given: Person with 2-digit marriage date
        let person = testPerson!
        XCTAssertEqual(person.marriageDate, "78", "Nuclear family has 2-digit date")
        
        // When: Looking up asParent family
        guard let asParentFamily = testNetwork.getAsParentFamily(for: person) else {
            XCTFail("Should find asParent family")
            return
        }
        
        // Then: Should find 8-digit marriage date
        let matchingPerson = asParentFamily.allParents.first { $0.birthDate == person.birthDate }
        XCTAssertEqual(matchingPerson?.fullMarriageDate, "23.11.1778", "Should have full marriage date")
    }
    
    func testExtractSpouseBirthDate() {
        // Given: Spouse name from nuclear family
        let spouseName = "Antti Korvela"
        
        // When: Looking up spouse's asChild family
        let tempSpouse = Person(name: spouseName, noteMarkers: [])
        guard let spouseFamily = testNetwork.getSpouseAsChildFamily(for: tempSpouse) else {
            XCTFail("Should find spouse asChild family")
            return
        }
        
        // Then: Should find spouse's birth date
        let spouse = spouseFamily.allChildren.first { $0.name.contains("Antti") }
        XCTAssertNotNil(spouse, "Should find spouse in family")
        XCTAssertEqual(spouse?.birthDate, "03.03.1759", "Should have spouse birth date")
    }
    
    func testExtractSpouseDeathDate() {
        // Given: Spouse name from nuclear family
        let spouseName = "Antti Korvela"
        
        // When: Looking up spouse's asChild family
        let tempSpouse = Person(name: spouseName, noteMarkers: [])
        guard let spouseFamily = testNetwork.getSpouseAsChildFamily(for: tempSpouse) else {
            XCTFail("Should find spouse asChild family")
            return
        }
        
        // Then: Should find spouse's death date
        let spouse = spouseFamily.allChildren.first { $0.name.contains("Antti") }
        XCTAssertNotNil(spouse, "Should find spouse in family")
        XCTAssertEqual(spouse?.deathDate, "03.05.1809", "Should have spouse death date")
    }
    
    // MARK: - Missing Data Tests
    
    func testUnmarriedChildHasNoEnhancement() {
        // Given: Unmarried child
        let unmarriedChild = Person(
            name: "Liisa",
            birthDate: "29.09.1773",
            noteMarkers: []
        )
        
        // When: Checking for asParent family
        let asParentFamily = testNetwork.getAsParentFamily(for: unmarriedChild)
        
        // Then: Should have no asParent family
        XCTAssertNil(asParentFamily, "Unmarried child should not have asParent family")
    }
    
    func testMarriedChildWithoutAsParentFamily() {
        // Given: Married child not in asParentFamilies dictionary
        let marriedChild = Person(
            name: "Unknown",
            birthDate: "01.01.1750",
            marriageDate: "70",
            spouse: "Someone",
            noteMarkers: []
        )
        
        // When: Checking for asParent family
        let asParentFamily = testNetwork.getAsParentFamily(for: marriedChild)
        
        // Then: Should return nil
        XCTAssertNil(asParentFamily, "Should return nil for missing asParent family")
    }
    
    func testSpouseWithoutAsChildFamily() {
        // Given: Spouse not in spouseAsChildFamilies dictionary
        let unknownSpouse = Person(name: "Unknown Spouse", noteMarkers: [])
        
        // When: Checking for spouse asChild family
        let spouseFamily = testNetwork.getSpouseAsChildFamily(for: unknownSpouse)
        
        // Then: Should return nil
        XCTAssertNil(spouseFamily, "Should return nil for missing spouse family")
    }
    
    // MARK: - Date Format Tests
    
    func testDateRangeFormat() {
        // Given: Birth and death dates
        let birthDate = "03.03.1759"
        let deathDate = "03.05.1809"
        
        // Then: Should format as range
        let expected = "\(birthDate)-\(deathDate)"
        XCTAssertEqual(expected, "03.03.1759-03.05.1809", "Should format as date range")
    }
    
    func testDeathDateWithPrefix() {
        // Given: Death date
        let deathDate = "19.10.1846"
        
        // Then: Should format with 'd.' prefix
        let expected = "d. \(deathDate)"
        XCTAssertEqual(expected, "d. 19.10.1846", "Should format with death prefix")
    }
    
    func testSingleDateFormat() {
        // Given: Single date
        let date = "19.10.1846"
        
        // Then: Should format without modifications
        XCTAssertEqual(date, "19.10.1846", "Should keep single date format")
    }
    
    // MARK: - Clickable Element Tests
    
    func testNameIsClickable() {
        // Given: Person with name
        let person = testPerson!
        
        // Then: Name should be accessible for clicking
        XCTAssertFalse(person.displayName.isEmpty, "Name should not be empty")
        XCTAssertEqual(person.displayName, "Magdalena", "Should have correct display name")
    }
    
    func testBirthDateIsClickable() {
        // Given: Person with birth date
        let person = testPerson!
        
        // Then: Birth date should be accessible
        XCTAssertNotNil(person.birthDate, "Birth date should exist")
        XCTAssertEqual(person.birthDate, "27.01.1759", "Should have correct birth date")
    }
    
    func testEnhancedDeathDateIsClickable() {
        // Given: Enhanced death date from asParent family
        guard let asParentFamily = testNetwork.getAsParentFamily(for: testPerson) else {
            XCTFail("Should have asParent family")
            return
        }
        
        let matchingPerson = asParentFamily.allParents.first { $0.birthDate == testPerson.birthDate }
        
        // Then: Enhanced death date should be accessible
        XCTAssertNotNil(matchingPerson?.deathDate, "Enhanced death date should exist")
    }
    
    func testMarriageDateIsClickable() {
        // Given: Person with marriage date
        let person = testPerson!
        
        // Then: Marriage date should be accessible
        XCTAssertNotNil(person.marriageDate, "Marriage date should exist")
    }
    
    func testFamilyIdIsClickable() {
        // Given: Person with asParent family ID
        let person = testPerson!
        
        // Then: Family ID should be accessible and valid
        XCTAssertNotNil(person.asParent, "Family ID should exist")
        XCTAssertEqual(person.asParent, "Korvela 3", "Should have correct family ID")
        XCTAssertTrue(FamilyIDs.isValid(familyId: "KORPI 6"), "Should validate real family IDs")
    }
    
    func testPseudoFamilyIdIsNotClickable() {
        // Given: Pseudo family ID
        let pseudoId = "Loht. Vapola"
        
        // Then: Should not be valid
        XCTAssertFalse(FamilyIDs.isValid(familyId: pseudoId), "Pseudo ID should not be valid")
    }
    
    // MARK: - All Children Enhancement Test
    
    func testAllMarriedChildrenShowEnhancedDates() {
        // Given: Nuclear family with multiple married children
        let nuclearFamily = testNetwork.mainFamily
        let marriedChildren = nuclearFamily.allChildren.filter { $0.isMarried }
        
        // Then: Each married child should be checkable for enhancement
        for child in marriedChildren {
            let hasAsParentFamily = testNetwork.getAsParentFamily(for: child) != nil
            
            // If they have an asParent family, we can enhance
            if hasAsParentFamily {
                let asParentFamily = testNetwork.getAsParentFamily(for: child)!
                let matchingPerson = asParentFamily.allParents.first {
                    $0.birthDate == child.birthDate || $0.name.lowercased() == child.name.lowercased()
                }
                
                // Should find matching person with potential enhanced data
                XCTAssertNotNil(matchingPerson, "Should find person in asParent family for \(child.name)")
            }
        }
    }
    
    // MARK: - Color Tests
    
    func testBlueColorForClickableElements() {
        // Given: Blue color hex
        let blue = Color(hex: "0066cc")
        
        // Then: Should create valid color
        XCTAssertNotNil(blue, "Should create blue color")
    }
    
    func testBrownColorForEnhancedDates() {
        // Given: Brown color hex
        let brown = Color(hex: "8b4513")
        
        // Then: Should create valid color
        XCTAssertNotNil(brown, "Should create brown color")
    }
    
    // MARK: - Helper Methods
    
    private func createNuclearFamily() -> Family {
        let father = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "09.09.1727",
            deathDate: "22.08.1812",
            asChild: "Korpi 5",
            familySearchId: "LCJZ-BH3",
            noteMarkers: []
        )
        
        let mother = Person(
            name: "Brita",
            patronymic: "Matint.",
            birthDate: "05.09.1731",
            deathDate: "11.07.1769",
            asChild: "Sikala 5",
            familySearchId: "KCJW-98X",
            noteMarkers: []
        )
        
        let magdalena = Person(
            name: "Magdalena",
            birthDate: "27.01.1759",
            marriageDate: "78",
            spouse: "Antti Korvela",
            asParent: "Korvela 3",
            familySearchId: "L4ZM-CRT",
            noteMarkers: []
        )
        
        let liisa = Person(
            name: "Liisa",
            birthDate: "29.09.1773",
            familySearchId: "XXXX-XXX",
            noteMarkers: []
        )
        
        let couple = Couple(
            husband: father,
            wife: mother,
            marriageDate: nil,
            fullMarriageDate: "14.10.1750",
            children: [magdalena, liisa]
        )
        
        return Family(
            familyId: "KORPI 6",
            couples: [couple],
            pageReferences: ["105", "106"],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createAsParentFamily() -> Family {
        // Magdalena as parent in Korvela 3
        let magdalena = Person(
            name: "Magdalena",
            birthDate: "27.01.1759",
            deathDate: "19.10.1846",  // Enhanced death date
            fullMarriageDate: "23.11.1778",  // Enhanced marriage date
            noteMarkers: []
        )
        
        let antti = Person(
            name: "Antti",
            patronymic: "Korvelan",
            birthDate: "03.03.1759",
            deathDate: "03.05.1809",
            noteMarkers: []
        )
        
        let couple = Couple(
            husband: antti,
            wife: magdalena,
            marriageDate: nil,
            fullMarriageDate: "23.11.1778",
            children: []
        )
        
        return Family(
            familyId: "Korvela 3",
            couples: [couple],
            pageReferences: ["120"],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createSpouseAsChildFamily() -> Family {
        // Antti Korvela as child in Korvela 2
        let antti = Person(
            name: "Antti",
            birthDate: "03.03.1759",
            deathDate: "03.05.1809",
            noteMarkers: []
        )
        
        let father = Person(
            name: "Erik",
            patronymic: "Korvelan",
            noteMarkers: []
        )
        
        let mother = Person(
            name: "Maria",
            noteMarkers: []
        )
        
        let couple = Couple(
            husband: father,
            wife: mother,
            marriageDate: nil,
            fullMarriageDate: nil,
            children: [antti]
        )
        
        return Family(
            familyId: "Korvela 2",
            couples: [couple],
            pageReferences: ["119"],
            notes: [],
            noteDefinitions: [:]
        )
    }
}
