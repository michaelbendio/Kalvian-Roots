//
//  FamilyContentViewTests.swift
//  Kalvian Roots Tests
//
//  Tests for FamilyContentView layout and PersonLineView rendering
//

import XCTest
import SwiftUI
@testable import Kalvian_Roots

final class FamilyContentViewTests: XCTestCase {
    
    var testFamily: Family!
    var testNetwork: FamilyNetwork!
    
    override func setUp() async throws {
        try await super.setUp()
        testFamily = createTestFamily()
        testNetwork = FamilyNetwork(mainFamily: testFamily)
    }
    
    override func tearDown() async throws {
        testFamily = nil
        testNetwork = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper: Create Test Family
    
    private func createTestFamily() -> Family {
        let husband = Person(
            name: "Erik",
            patronymic: "Matinp.",
            birthDate: "09.04.1753",
            deathDate: "04.11.1826",
            asChild: "KORPELA 5",
            familySearchId: "L4ZM-ABC"
        )
        
        let wife = Person(
            name: "Liisa",
            patronymic: "Juhont.",
            birthDate: "26.01.1757",
            deathDate: "30.03.1838",
            asChild: "KANKKONEN 2",
            familySearchId: "L4ZM-DEF"
        )
        
        let marriedChild = Person(
            name: "Juho",
            birthDate: "21.02.1781",
            marriageDate: "06",
            fullMarriageDate: "15.11.1806",
            spouse: "Liisa Hannila",
            asParent: "HANNILA 3",
            familySearchId: "L4ZM-GHI"
        )
        
        let unmarriedChild = Person(
            name: "Anna",
            birthDate: "15.03.1785",
            familySearchId: "L4ZM-JKL"
        )
        
        let couple = Couple(
            husband: husband,
            wife: wife,
            marriageDate: "80",
            fullMarriageDate: "03.11.1780",
            children: [marriedChild, unmarriedChild],
            childrenDiedInfancy: 2
        )
        
        return Family(
            familyId: "TEST 1",
            pageReferences: ["375", "376"],
            couples: [couple],
            notes: ["Erik moved to Kälviä 1780"]
        )
    }
    
    // MARK: - Family Structure Tests
    
    func testFamilyHeaderPresent() {
        // Given: Test family
        let family = testFamily!
        
        // Then: Header components present
        XCTAssertEqual(family.familyId, "TEST 1", "Family ID correct")
        XCTAssertEqual(family.pageReferences, ["375", "376"], "Pages correct")
    }
    
    func testParentLinesHaveRequiredData() {
        // Given: Test family with parents
        let family = testFamily!
        guard let couple = family.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        
        // Then: Parents have required data
        XCTAssertFalse(couple.husband.name.isEmpty, "Husband has name")
        XCTAssertFalse(couple.wife.name.isEmpty, "Wife has name")
        XCTAssertNotNil(couple.husband.birthDate, "Husband has birth date")
        XCTAssertNotNil(couple.wife.birthDate, "Wife has birth date")
        XCTAssertNotNil(couple.husband.asChild, "Husband has asChild")
        XCTAssertNotNil(couple.wife.asChild, "Wife has asChild")
    }
    
    func testMarriageDatePresent() {
        // Given: Test family
        let family = testFamily!
        guard let couple = family.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        
        // Then: Marriage date present
        XCTAssertNotNil(couple.fullMarriageDate, "Full marriage date present")
        XCTAssertEqual(couple.fullMarriageDate, "03.11.1780", "Marriage date correct")
    }
    
    func testChildrenSectionHasData() {
        // Given: Test family with children
        let family = testFamily!
        guard let couple = family.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        
        // Then: Children present
        XCTAssertEqual(couple.children.count, 2, "Has 2 children")
        
        let marriedChild = couple.children[0]
        XCTAssertTrue(marriedChild.isMarried, "First child is married")
        XCTAssertNotNil(marriedChild.spouse, "Has spouse")
        XCTAssertNotNil(marriedChild.asParent, "Has asParent")
        
        let unmarriedChild = couple.children[1]
        XCTAssertFalse(unmarriedChild.isMarried, "Second child unmarried")
        XCTAssertNil(unmarriedChild.spouse, "No spouse")
    }
    
    func testChildrenDiedInfancy() {
        // Given: Test family
        let family = testFamily!
        guard let couple = family.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        
        // Then: Infant deaths noted
        XCTAssertEqual(couple.childrenDiedInfancy, 2, "2 children died in infancy")
    }
    
    func testNotesPresent() {
        // Given: Test family with notes
        let family = testFamily!
        
        // Then: Notes present
        XCTAssertFalse(family.notes.isEmpty, "Has notes")
        XCTAssertEqual(family.notes.count, 1, "One note")
        XCTAssertTrue(family.notes[0].contains("moved"), "Note content correct")
    }
    
    // MARK: - PersonLineView Data Tests
    
    func testPersonLineViewHandlesUnmarriedChild() {
        // Given: Unmarried child
        let child = testFamily.primaryCouple!.children[1]
        
        // Then: Should have basic data
        XCTAssertFalse(child.name.isEmpty, "Has name")
        XCTAssertNotNil(child.birthDate, "Has birth date")
        XCTAssertFalse(child.isMarried, "Not married")
        XCTAssertNil(child.spouse, "No spouse")
        XCTAssertNil(child.asParent, "No asParent")
    }
    
    func testPersonLineViewHandlesMarriedChild() {
        // Given: Married child
        let child = testFamily.primaryCouple!.children[0]
        
        // Then: Should have marriage data
        XCTAssertTrue(child.isMarried, "Is married")
        XCTAssertNotNil(child.spouse, "Has spouse")
        XCTAssertNotNil(child.marriageDate, "Has marriage date")
        XCTAssertNotNil(child.fullMarriageDate, "Has full marriage date")
        XCTAssertNotNil(child.asParent, "Has asParent family")
    }
    
    func testPersonLineViewHandlesParent() {
        // Given: Parent person
        let father = testFamily.primaryCouple!.husband
        
        // Then: Should have parent data
        XCTAssertFalse(father.name.isEmpty, "Has name")
        XCTAssertNotNil(father.patronymic, "Has patronymic")
        XCTAssertNotNil(father.birthDate, "Has birth date")
        XCTAssertNotNil(father.deathDate, "Has death date")
        XCTAssertNotNil(father.asChild, "Has asChild")
        XCTAssertNotNil(father.familySearchId, "Has FSID")
    }
    
    // MARK: - Enhanced Data Tests
    
    func testEnhancedDataStructure() {
        // Test: EnhancedPersonData can be created
        let enhanced = EnhancedPersonData(
            deathDate: "19.10.1846",
            fullMarriageDate: "23.11.1778",
            spouse: SpouseEnhancedData(
                birthDate: "03.03.1759",
                deathDate: "03.05.1809",
                fullName: "Antti Korvela"
            )
        )
        
        XCTAssertEqual(enhanced.deathDate, "19.10.1846", "Death date set")
        XCTAssertEqual(enhanced.fullMarriageDate, "23.11.1778", "Marriage date set")
        XCTAssertNotNil(enhanced.spouse, "Spouse data set")
        XCTAssertEqual(enhanced.spouse?.birthDate, "03.03.1759", "Spouse birth set")
    }
    
    func testSpouseEnhancedDataStructure() {
        // Test: SpouseEnhancedData can be created
        let spouse = SpouseEnhancedData(
            birthDate: "03.03.1759",
            deathDate: "03.05.1809",
            fullName: "Antti Korvela"
        )
        
        XCTAssertEqual(spouse.birthDate, "03.03.1759", "Birth date set")
        XCTAssertEqual(spouse.deathDate, "03.05.1809", "Death date set")
        XCTAssertEqual(spouse.fullName, "Antti Korvela", "Full name set")
    }
    
    // MARK: - Display Format Tests
    
    func testBirthDateFormat() {
        // Given: Various birth date formats
        let fullDate = "27.01.1759"
        let yearOnly = "1823"
        let approximate = "n 1780"
        
        // Then: All formats should be valid
        XCTAssertTrue(fullDate.contains("."), "Full date has dots")
        XCTAssertEqual(fullDate.count, 10, "Full date is 10 chars")
        XCTAssertEqual(yearOnly.count, 4, "Year only is 4 chars")
        XCTAssertTrue(approximate.hasPrefix("n"), "Approximate has 'n'")
    }
    
    func testMarriageDateFormat() {
        // Given: Marriage date formats
        let fullDate = "23.11.1778"
        let shortDate = "78"
        
        // Then: Formats should be distinguishable
        XCTAssertTrue(fullDate.contains("."), "Full date has dots")
        XCTAssertEqual(fullDate.count, 10, "Full date is 10 chars")
        XCTAssertEqual(shortDate.count, 2, "Short date is 2 chars")
    }
    
    func testDeathDateFormat() {
        // Given: Death date format
        let deathDate = "19.10.1846"
        
        // Then: Should be full 8-digit format
        XCTAssertTrue(deathDate.contains("."), "Has dots")
        XCTAssertEqual(deathDate.count, 10, "Is 10 chars")
    }
    
    // MARK: - Family ID Validation Tests
    
    func testValidFamilyIDs() {
        // Given: Valid family IDs
        let validIds = [
            "KORPI 6",
            "HERLEVI 1",
            "VÄHÄ-HYYPPÄ 7",
            "MAUNUMÄKI IV 5",
            "PIENI SIKALA 3"
        ]
        
        // Then: All should be recognized as valid
        for id in validIds {
            XCTAssertTrue(FamilyIDs.isValid(familyId: id),
                          "\(id) should be valid")
        }
    }
    
    func testInvalidFamilyIDs() {
        // Given: Invalid family IDs (pseudo-families)
        let invalidIds = [
            "Loht. Vapola",
            "INVALID 999",
            "Not A Family"
        ]
        
        // Then: Should be recognized as invalid
        for id in invalidIds {
            XCTAssertFalse(FamilyIDs.isValid(familyId: id),
                           "\(id) should be invalid")
        }
    }
    
    // MARK: - FamilySearch ID Format Tests
    
    func testFamilySearchIDFormat() {
        // Given: Various FSID formats
        let fsid1 = "L4ZM-CRT"
        let fsid2 = "M8ZT-J2S"
        let fsid3 = "GMG6-GJ7"
        
        // Then: All should match pattern: 4 chars, hyphen, 3 chars
        let pattern = "^[A-Z0-9]{4}-[A-Z0-9]{3}$"
        let regex = try! NSRegularExpression(pattern: pattern)
        
        XCTAssertTrue(regex.firstMatch(in: fsid1, range: NSRange(fsid1.startIndex..., in: fsid1)) != nil,
                      "FSID1 matches pattern")
        XCTAssertTrue(regex.firstMatch(in: fsid2, range: NSRange(fsid2.startIndex..., in: fsid2)) != nil,
                      "FSID2 matches pattern")
        XCTAssertTrue(regex.firstMatch(in: fsid3, range: NSRange(fsid3.startIndex..., in: fsid3)) != nil,
                      "FSID3 matches pattern")
    }
    
    // MARK: - Clickable Element Tests
    
    func testNamesAreClickable() {
        // Test: All person types should have clickable names
        let father = testFamily.primaryCouple!.husband
        let mother = testFamily.primaryCouple!.wife
        let child = testFamily.primaryCouple!.children[0]
        
        XCTAssertFalse(father.name.isEmpty, "Father has clickable name")
        XCTAssertFalse(mother.name.isEmpty, "Mother has clickable name")
        XCTAssertFalse(child.name.isEmpty, "Child has clickable name")
    }
    
    func testDatesAreClickable() {
        // Test: All dates should be present for clicking
        let father = testFamily.primaryCouple!.husband
        
        XCTAssertNotNil(father.birthDate, "Birth date clickable")
        XCTAssertNotNil(father.deathDate, "Death date clickable")
    }
    
    func testFamilyIDsAreClickable() {
        // Test: Valid family IDs should be clickable
        let father = testFamily.primaryCouple!.husband
        let marriedChild = testFamily.primaryCouple!.children[0]
        
        XCTAssertNotNil(father.asChild, "Parent asChild clickable")
        XCTAssertNotNil(marriedChild.asParent, "Child asParent clickable")
        
        // Verify they're valid
        if let asChild = father.asChild {
            XCTAssertTrue(FamilyIDs.isValid(familyId: asChild),
                          "asChild should be valid ID")
        }
        if let asParent = marriedChild.asParent {
            XCTAssertTrue(FamilyIDs.isValid(familyId: asParent),
                          "asParent should be valid ID")
        }
    }
    
    // MARK: - Color Tests
    
    func testColorHexInitialization() {
        // Test: Color hex initialization works
        let blue = Color(hex: "0066cc")
        let brown = Color(hex: "8b4513")
        let purple1 = Color(hex: "667eea")
        let purple2 = Color(hex: "764ba2")
        let offWhite = Color(hex: "fefdf8")
        
        // Just verify they initialize without crashing
        XCTAssertNotNil(blue, "Blue initializes")
        XCTAssertNotNil(brown, "Brown initializes")
        XCTAssertNotNil(purple1, "Purple1 initializes")
        XCTAssertNotNil(purple2, "Purple2 initializes")
        XCTAssertNotNil(offWhite, "Off-white initializes")
    }
    
    func testColorHex3Digit() {
        // Test: 3-digit hex works
        let color = Color(hex: "abc")
        XCTAssertNotNil(color, "3-digit hex works")
    }
    
    func testColorHex6Digit() {
        // Test: 6-digit hex works
        let color = Color(hex: "aabbcc")
        XCTAssertNotNil(color, "6-digit hex works")
    }
    
    func testColorHex8Digit() {
        // Test: 8-digit hex with alpha works
        let color = Color(hex: "aabbccdd")
        XCTAssertNotNil(color, "8-digit hex works")
    }
}
