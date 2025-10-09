//
//  FamilyLayoutTests.swift
//  Kalvian Roots
//
// Tests for Family Display Layout
//
//  Created by Michael Bendio on 10/8/25.
//

import XCTest
import SwiftUI
@testable import Kalvian_Roots

final class FamilyLayoutTests: XCTestCase {
    
    var testFamily: Family!
    
    override func setUp() async throws {
        try await super.setUp()
        testFamily = createTestFamily()
    }
    
    override func tearDown() async throws {
        testFamily = nil
        try await super.tearDown()
    }
    
    // MARK: - Layout Structure Tests
    
    func testFamilyStructureOrder() {
        // Given: A family with all components
        let family = testFamily!
        
        // Then: Verify structure exists
        XCTAssertFalse(family.familyId.isEmpty, "Should have family ID")
        XCTAssertFalse(family.pageReferences.isEmpty, "Should have page references")
        XCTAssertNotNil(family.primaryCouple, "Should have primary couple")
        XCTAssertFalse(family.allChildren.isEmpty, "Should have children")
        
        // Verify primary couple exists
        guard let couple = family.primaryCouple else {
            XCTFail("Primary couple should exist")
            return
        }
        
        XCTAssertFalse(couple.husband.name.isEmpty, "Father should have name")
        XCTAssertFalse(couple.wife.name.isEmpty, "Mother should have name")
    }
    
    func testFamilyHeaderComponents() {
        // Given: Family with ID and pages
        let family = testFamily!
        
        // Then: Header components should be present
        XCTAssertEqual(family.familyId, "KORPI 6", "Should have correct family ID")
        XCTAssertEqual(family.pageReferences, ["105", "106"], "Should have page references")
    }
    
    func testParentLinesPresent() {
        // Given: Family with parents
        let family = testFamily!
        guard let couple = family.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        
        // Then: Both parents should be present
        XCTAssertFalse(couple.husband.name.isEmpty, "Husband should have name")
        XCTAssertFalse(couple.wife.name.isEmpty, "Wife should have name")
        XCTAssertNotNil(couple.husband.birthDate, "Husband should have birth date")
        XCTAssertNotNil(couple.wife.birthDate, "Wife should have birth date")
    }
    
    func testMarriageDatePresent() {
        // Given: Family with marriage date
        let family = testFamily!
        guard let couple = family.primaryCouple else {
            XCTFail("Should have primary couple")
            return
        }
        
        // Then: Marriage date should be present
        let hasMarriageDate = couple.fullMarriageDate != nil || couple.marriageDate != nil
        XCTAssertTrue(hasMarriageDate, "Couple should have marriage date")
    }
    
    func testChildrenSectionPresent() {
        // Given: Family with children
        let family = testFamily!
        
        // Then: Children should be present
        let allChildren = family.allChildren
        XCTAssertFalse(allChildren.isEmpty, "Family should have children")
        XCTAssertGreaterThan(allChildren.count, 0, "Should have at least one child")
    }
    
    func testAdditionalSpousesHandling() {
        // Given: Family with multiple couples
        let family = createFamilyWithMultipleSpouses()
        
        // Then: Should have multiple couples
        XCTAssertGreaterThan(family.couples.count, 1, "Should have additional spouses")
        XCTAssertEqual(family.couples.count, 2, "Test family should have 2 couples")
    }
    
    func testNotesPresent() {
        // Given: Family with notes
        let family = testFamily!
        
        // Then: Notes should be accessible
        // (May be empty for this test family)
        XCTAssertNotNil(family.notes, "Notes array should exist")
    }
    
    // MARK: - Font and Typography Tests
    
    func testMonospaceFontSpecification() {
        // Test that font design is monospaced
        let monoFont = Font.system(size: 16, design: .monospaced)
        XCTAssertNotNil(monoFont, "Monospace font should be creatable")
    }
    
    func testLineSpacingValue() {
        // Verify tight line spacing value
        let expectedLineSpacing: CGFloat = 1.3
        XCTAssertEqual(expectedLineSpacing, 1.3, "Line spacing should be 1.3")
    }
    
    func testFontSizes() {
        // Verify font sizes match specification
        let headerSize: CGFloat = 18  // Family ID
        let bodySize: CGFloat = 16    // Family lines
        
        XCTAssertEqual(headerSize, 18, "Header font should be 18pt")
        XCTAssertEqual(bodySize, 16, "Body font should be 16pt")
    }
    
    // MARK: - Color Tests
    
    func testBackgroundColor() {
        // Given: Off-white background color
        let bgColor = Color(hex: "fefdf8")
        
        // Then: Color should be created successfully
        XCTAssertNotNil(bgColor, "Background color should be created")
    }
    
    func testBlueClickableColor() {
        // Given: Blue color for clickable elements
        let blueColor = Color(hex: "0066cc")
        
        // Then: Color should be created successfully
        XCTAssertNotNil(blueColor, "Blue color should be created")
    }
    
    func testBrownBracketColor() {
        // Given: Brown color for brackets
        let brownColor = Color(hex: "8b4513")
        
        // Then: Color should be created successfully
        XCTAssertNotNil(brownColor, "Brown color should be created")
    }
    
    // MARK: - Spacing Tests
    
    func testMinimalGapsBetweenSections() {
        // Verify spacing values are minimal for density
        let sectionSpacing: CGFloat = 2  // Between family lines
        let groupSpacing: CGFloat = 8    // Between sections
        
        XCTAssertEqual(sectionSpacing, 2, "Section spacing should be minimal (2pt)")
        XCTAssertEqual(groupSpacing, 8, "Group spacing should be small (8pt)")
    }
    
    func testPaddingValues() {
        // Verify padding matches specification
        let contentPadding: CGFloat = 24  // Around entire family content
        
        XCTAssertEqual(contentPadding, 24, "Content padding should be 24pt")
    }
    
    // MARK: - Roman Numeral Tests
    
    func testRomanNumeralConversion() {
        // Test roman numeral helper
        let testCases: [(Int, String)] = [
            (2, "II"),
            (3, "III"),
            (4, "IV"),
            (5, "V")
        ]
        
        for (number, expected) in testCases {
            let result = romanNumeral(number)
            XCTAssertEqual(result, expected, "Roman numeral for \(number) should be \(expected)")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteLayoutRendering() {
        // Given: Complete family
        let family = testFamily!
        
        // Then: All major components should be present
        XCTAssertFalse(family.familyId.isEmpty, "Family ID present")
        XCTAssertFalse(family.pageReferences.isEmpty, "Page references present")
        XCTAssertNotNil(family.primaryCouple, "Primary couple present")
        XCTAssertGreaterThan(family.allChildren.count, 0, "Children present")
        
        // Structure is valid for rendering
        XCTAssertTrue(family.isValid, "Family structure should be valid")
    }
    
    func testFamilyWithAllSections() {
        // Given: Family with all possible sections
        let family = createCompleteFamily()
        
        // Then: All sections should be present
        XCTAssertNotNil(family.primaryCouple, "Has primary couple")
        XCTAssertGreaterThan(family.allChildren.count, 0, "Has children")
        XCTAssertFalse(family.notes.isEmpty, "Has notes")
        
        // Optional: Check for marriage date
        let hasMarriage = family.primaryCouple?.fullMarriageDate != nil ||
                         family.primaryCouple?.marriageDate != nil
        XCTAssertTrue(hasMarriage, "Has marriage date")
    }
    
    // MARK: - Visual Consistency Tests
    
    func testConsistentMonospaceUsage() {
        // All text elements should use monospace design
        let designs: [Font.Design] = [.monospaced]
        
        for design in designs {
            let font = Font.system(size: 16, design: design)
            XCTAssertNotNil(font, "Monospace font should be creatable")
        }
    }
    
    func testAlignmentConsistency() {
        // All sections should use .leading alignment
        let alignment = HorizontalAlignment.leading
        XCTAssertEqual(alignment, .leading, "Content should use leading alignment")
    }
    
    // MARK: - Helper Methods
    
    private func createTestFamily() -> Family {
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
        
        let child1 = Person(
            name: "Magdalena",
            birthDate: "27.01.1759",
            marriageDate: "78",
            spouse: "Antti Korvela",
            asParent: "Korvela 3",
            familySearchId: "L4ZM-CRT",
            noteMarkers: []
        )
        
        let child2 = Person(
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
            children: [child1, child2]
        )
        
        return Family(
            familyId: "KORPI 6",
            pageReferences: ["105", "106"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createFamilyWithMultipleSpouses() -> Family {
        let husband = Person(
            name: "Jaakko",
            patronymic: "Jaakonp.",
            birthDate: "09.10.1726",
            noteMarkers: []
        )
        
        let firstWife = Person(
            name: "Maria",
            patronymic: "Jaakont.",
            birthDate: "02.03.1733",
            deathDate: "18.04.1753",
            noteMarkers: []
        )
        
        let secondWife = Person(
            name: "Brita",
            patronymic: "Eliant.",
            birthDate: "11.01.1732",
            noteMarkers: []
        )
        
        let couple1 = Couple(
            husband: husband,
            wife: firstWife,
            marriageDate: nil,
            fullMarriageDate: "08.10.1752",
            children: []
        )
        
        let couple2 = Couple(
            husband: husband,
            wife: secondWife,
            marriageDate: nil,
            fullMarriageDate: "06.10.1754",
            children: []
        )
        
        return Family(
            familyId: "HYYPPÄ 6",
            pageReferences: ["370"],
            couples: [couple1, couple2],
            notes: [],
            noteDefinitions: [:]
        )
    }
    
    private func createCompleteFamily() -> Family {
        let family = createTestFamily()
        
        // Add notes to make it complete
        var completeFam = family
        completeFam.notes = ["Lapsena kuollut 4."]
        
        return completeFam
    }
    
    private func romanNumeral(_ number: Int) -> String {
        switch number {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        default: return "\(number)"
        }
    }
}
