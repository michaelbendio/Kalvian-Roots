//
//  ModelTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for Person, Couple, and Family models
//

import XCTest
@testable import Kalvian_Roots

// MARK: - Person Tests

final class PersonTests: XCTestCase {
    
    func testPersonInitialization() {
        // When: Creating a person with all properties
        let person = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "15.02.1730",
            deathDate: "20.05.1800",
            marriageDate: "55",
            fullMarriageDate: "10.10.1755",
            spouse: "Maria Korpi",
            asChild: "KORPI 5",
            asParent: "SIKALA 3",
            familySearchId: "L4ZM-ABC",
            noteMarkers: ["*"],
            fatherName: "Erik",
            motherName: "Brita",
            spouseBirthDate: "01.01.1735",
            spouseParentsFamilyId: "KORPI 4"
        )
        
        // Then: All properties should be set
        XCTAssertEqual(person.name, "Matti")
        XCTAssertEqual(person.patronymic, "Erikinp.")
        XCTAssertEqual(person.birthDate, "15.02.1730")
        XCTAssertEqual(person.deathDate, "20.05.1800")
        XCTAssertEqual(person.marriageDate, "55")
        XCTAssertEqual(person.fullMarriageDate, "10.10.1755")
        XCTAssertEqual(person.spouse, "Maria Korpi")
        XCTAssertEqual(person.asChild, "KORPI 5")
        XCTAssertEqual(person.asParent, "SIKALA 3")
        XCTAssertEqual(person.familySearchId, "L4ZM-ABC")
        XCTAssertEqual(person.noteMarkers, ["*"])
        XCTAssertEqual(person.fatherName, "Erik")
        XCTAssertEqual(person.motherName, "Brita")
    }
    
    func testPersonMinimalInitialization() {
        // When: Creating person with only required fields
        let person = Person(
            name: "Liisa",
            noteMarkers: []
        )
        
        // Then: Should have name and empty arrays
        XCTAssertEqual(person.name, "Liisa")
        XCTAssertNil(person.birthDate)
        XCTAssertNil(person.spouse)
        XCTAssertEqual(person.noteMarkers, [])
    }
    
    func testPersonDisplayName() {
        // Given: Person with name
        let person = Person(name: "Matti Erikinp.", noteMarkers: [])
        
        // Then: Display name should match name
        XCTAssertEqual(person.displayName, "Matti Erikinp.")
    }
    
    func testPersonIsMarried() {
        // Given: Married person
        let married = Person(name: "Matti", spouse: "Maria", noteMarkers: [])
        let unmarried = Person(name: "Liisa", noteMarkers: [])
        
        // Then: Should detect marriage status
        XCTAssertTrue(married.isMarried)
        XCTAssertFalse(unmarried.isMarried)
    }
    
    func testPersonBestMarriageDate() {
        // Test: Full marriage date takes precedence
        let person1 = Person(
            name: "Matti",
            marriageDate: "55",
            fullMarriageDate: "10.10.1755",
            noteMarkers: []
        )
        XCTAssertEqual(person1.bestMarriageDate, "10.10.1755")
        
        // Test: Falls back to marriageDate
        let person2 = Person(
            name: "Maria",
            marriageDate: "55",
            noteMarkers: []
        )
        XCTAssertEqual(person2.bestMarriageDate, "55")
    }
    
    func testPersonID() {
        // Given: Two persons with different data
        let person1 = Person(name: "Matti", birthDate: "01.01.1730", noteMarkers: [])
        let person2 = Person(name: "Maria", birthDate: "01.01.1735", noteMarkers: [])
        
        // Then: Should have different IDs
        XCTAssertNotEqual(person1.id, person2.id)
    }
    
    func testPersonEquality() {
        // Given: Two persons with same data
        let person1 = Person(name: "Matti", birthDate: "01.01.1730", noteMarkers: [])
        let person2 = Person(name: "Matti", birthDate: "01.01.1730", noteMarkers: [])
        
        // Then: Should be equal
        XCTAssertEqual(person1, person2)
    }
    
    func testPersonHashable() {
        // Given: Person in a set
        let person = Person(name: "Matti", noteMarkers: [])
        var set = Set<Person>()
        set.insert(person)
        
        // Then: Should be in set
        XCTAssertTrue(set.contains(person))
    }
    
    func testPersonValidateData() {
        // Test: Validation warnings
        let validPerson = Person(
            name: "Matti",
            birthDate: "15.02.1730",
            noteMarkers: []
        )
        XCTAssertEqual(validPerson.validateData().count, 0, "Valid person should have no warnings")
        
        // Test: Person with empty name
        let invalidPerson = Person(name: "", noteMarkers: [])
        XCTAssertGreaterThan(invalidPerson.validateData().count, 0, "Empty name should warn")
    }
    
    func testPersonEnhanceWithSpouseData() {
        // Given: Person
        var person = Person(name: "Matti", noteMarkers: [])
        
        // When: Enhancing with spouse data
        person.enhanceWithSpouseData(
            birthDate: "01.01.1735",
            parentsFamilyId: "KORPI 4"
        )
        
        // Then: Should have spouse data
        XCTAssertEqual(person.spouseBirthDate, "01.01.1735")
        XCTAssertEqual(person.spouseParentsFamilyId, "KORPI 4")
    }
    
    func testPersonEnhanceWithParentNames() {
        // Given: Person
        var person = Person(name: "Matti", noteMarkers: [])
        
        // When: Enhancing with parent names
        person.enhanceWithParentNames(father: "Erik", mother: "Brita")
        
        // Then: Should have parent names
        XCTAssertEqual(person.fatherName, "Erik")
        XCTAssertEqual(person.motherName, "Brita")
    }
}

// MARK: - Couple Tests

final class CoupleTests: XCTestCase {
    
    func testCoupleInitialization() {
        // Given: Husband and wife
        let husband = Person(name: "Matti", noteMarkers: [])
        let wife = Person(name: "Maria", noteMarkers: [])
        let child = Person(name: "Liisa", noteMarkers: [])
        
        // When: Creating couple
        let couple = Couple(
            husband: husband,
            wife: wife,
            marriageDate: "1755",
            fullMarriageDate: "10.10.1755",
            children: [child],
            childrenDiedInfancy: 2,
            coupleNotes: ["Note 1"]
        )
        
        // Then: Should have all properties
        XCTAssertEqual(couple.husband.name, "Matti")
        XCTAssertEqual(couple.wife.name, "Maria")
        XCTAssertEqual(couple.marriageDate, "1755")
        XCTAssertEqual(couple.fullMarriageDate, "10.10.1755")
        XCTAssertEqual(couple.children.count, 1)
        XCTAssertEqual(couple.childrenDiedInfancy, 2)
        XCTAssertEqual(couple.coupleNotes.count, 1)
    }
    
    func testCoupleMinimalInitialization() {
        // When: Creating couple with only required fields
        let husband = Person(name: "Matti", noteMarkers: [])
        let wife = Person(name: "Maria", noteMarkers: [])
        let couple = Couple(husband: husband, wife: wife)
        
        // Then: Should have defaults
        XCTAssertNil(couple.marriageDate)
        XCTAssertNil(couple.fullMarriageDate)
        XCTAssertEqual(couple.children.count, 0)
        XCTAssertNil(couple.childrenDiedInfancy)
        XCTAssertEqual(couple.coupleNotes.count, 0)
    }
    
    func testCoupleEquality() {
        // Given: Two identical couples
        let husband1 = Person(name: "Matti", noteMarkers: [])
        let wife1 = Person(name: "Maria", noteMarkers: [])
        let couple1 = Couple(husband: husband1, wife: wife1)
        
        let husband2 = Person(name: "Matti", noteMarkers: [])
        let wife2 = Person(name: "Maria", noteMarkers: [])
        let couple2 = Couple(husband: husband2, wife: wife2)
        
        // Then: Should be equal
        XCTAssertEqual(couple1, couple2)
    }
    
    func testCoupleHashable() {
        // Given: Couple in a set
        let husband = Person(name: "Matti", noteMarkers: [])
        let wife = Person(name: "Maria", noteMarkers: [])
        let couple = Couple(husband: husband, wife: wife)
        var set = Set<Couple>()
        set.insert(couple)
        
        // Then: Should be in set
        XCTAssertTrue(set.contains(couple))
    }
}

// MARK: - Family Tests

final class FamilyTests: XCTestCase {
    
    var testFamily: Family!
    
    override func setUp() throws {
        try super.setUp()
        testFamily = createTestFamily()
    }
    
    override func tearDown() throws {
        testFamily = nil
        try super.tearDown()
    }
    
    func testFamilyInitialization() {
        // Then: Should have all properties
        XCTAssertEqual(testFamily.familyId, "TEST 1")
        XCTAssertEqual(testFamily.pageReferences, ["100", "101"])
        XCTAssertEqual(testFamily.couples.count, 1)
        XCTAssertEqual(testFamily.notes.count, 0)
    }
    
    func testFamilyPrimaryCouple() {
        // When: Getting primary couple
        let primary = testFamily.primaryCouple
        
        // Then: Should be first couple
        XCTAssertNotNil(primary)
        XCTAssertEqual(primary?.husband.name, "Matti")
    }
    
    func testFamilyAllParents() {
        // When: Getting all parents
        let parents = testFamily.allParents
        
        // Then: Should include all parents from all couples
        XCTAssertEqual(parents.count, 2)
        XCTAssertTrue(parents.contains { $0.name == "Matti" })
        XCTAssertTrue(parents.contains { $0.name == "Maria" })
    }
    
    func testFamilyAllChildren() {
        // When: Getting all children
        let children = testFamily.allChildren
        
        // Then: Should include children from all couples
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].name, "Liisa")
    }
    
    func testFamilyMarriedChildren() {
        // Given: Family with married and unmarried children
        let married = Person(name: "Married", spouse: "Someone", noteMarkers: [])
        let unmarried = Person(name: "Unmarried", noteMarkers: [])
        
        let husband = Person(name: "Father", noteMarkers: [])
        let wife = Person(name: "Mother", noteMarkers: [])
        let couple = Couple(husband: husband, wife: wife, children: [married, unmarried])
        let family = Family(
            familyId: "MIXED 1",
            pageReferences: ["1"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
        
        // When: Getting married children
        let marriedChildren = family.marriedChildren
        
        // Then: Should only include married
        XCTAssertEqual(marriedChildren.count, 1)
        XCTAssertEqual(marriedChildren[0].name, "Married")
    }
    
    func testFamilyTotalChildrenDiedInfancy() {
        // Given: Multiple couples with infant deaths
        let couple1 = Couple(
            husband: Person(name: "H1", noteMarkers: []),
            wife: Person(name: "W1", noteMarkers: []),
            childrenDiedInfancy: 2
        )
        let couple2 = Couple(
            husband: Person(name: "H1", noteMarkers: []),
            wife: Person(name: "W2", noteMarkers: []),
            childrenDiedInfancy: 3
        )
        let family = Family(
            familyId: "DEATHS 1",
            pageReferences: ["1"],
            couples: [couple1, couple2],
            notes: [],
            noteDefinitions: [:]
        )
        
        // Then: Should sum across couples
        XCTAssertEqual(family.totalChildrenDiedInfancy, 5)
    }
    
    func testFamilyPageReferenceString() {
        // Test: Single page
        let family1 = Family(
            familyId: "SINGLE 1",
            pageReferences: ["100"],
            couples: [],
            notes: [],
            noteDefinitions: [:]
        )
        XCTAssertEqual(family1.pageReferenceString, "page 100")
        
        // Test: Multiple pages
        let family2 = testFamily!
        XCTAssertEqual(family2.pageReferenceString, "pages 100, 101")
    }
    
    func testFamilyIsValid() {
        // Test: Valid family
        XCTAssertTrue(testFamily.isValid)
        
        // Test: Invalid family (empty ID)
        let invalid = Family(
            familyId: "",
            pageReferences: ["100"],
            couples: [],
            notes: [],
            noteDefinitions: [:]
        )
        XCTAssertFalse(invalid.isValid)
    }
    
    func testFamilyFindPerson() {
        // When: Finding person by name
        let found = testFamily.findPerson(named: "Matti")
        
        // Then: Should find the person
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Matti")
    }
    
    func testFamilyFindPersonCaseInsensitive() {
        // When: Finding with different case
        let found = testFamily.findPerson(named: "matti")
        
        // Then: Should find the person
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Matti")
    }
    
    func testFamilyFindPersonNotFound() {
        // When: Finding non-existent person
        let found = testFamily.findPerson(named: "NonExistent")
        
        // Then: Should return nil
        XCTAssertNil(found)
    }
    
    func testFamilyAllPersons() {
        // When: Getting all unique persons
        let allPersons = testFamily.allPersons
        
        // Then: Should have all unique persons
        XCTAssertEqual(allPersons.count, 3) // 2 parents + 1 child
    }
    
    func testFamilyFindCoupleForChild() {
        // When: Finding couple for child
        let couple = testFamily.findCoupleForChild("Liisa")
        
        // Then: Should find the couple
        XCTAssertNotNil(couple)
        XCTAssertEqual(couple?.husband.name, "Matti")
    }
    
    func testFamilyGetParentNames() {
        // Given: Child in family
        let child = testFamily.allChildren.first!
        
        // When: Getting parent names
        if let parentNames = testFamily.getParentNames(for: child) {
            // Then: Should have parent names
            XCTAssertEqual(parentNames.father, "Matti")
            XCTAssertEqual(parentNames.mother, "Maria")
        } else {
            XCTFail("Should find parent names")
        }
    }
    
    func testFamilyEquality() {
        // Given: Two identical families
        let family1 = testFamily!
        let family2 = createTestFamily()
        
        // Then: Should be equal
        XCTAssertEqual(family1, family2)
    }
    
    func testFamilyHashable() {
        // Given: Family in a set
        var set = Set<Family>()
        set.insert(testFamily)
        
        // Then: Should be in set
        XCTAssertTrue(set.contains(testFamily))
    }
    
    func testFamilyWithMultipleCouples() {
        // Given: Family with remarriage
        let husband = Person(name: "Matti", noteMarkers: [])
        let firstWife = Person(name: "Maria", deathDate: "01.01.1760", noteMarkers: [])
        let secondWife = Person(name: "Brita", noteMarkers: [])
        
        let couple1 = Couple(husband: husband, wife: firstWife)
        let couple2 = Couple(husband: husband, wife: secondWife)
        
        let family = Family(
            familyId: "REMARRIAGE 1",
            pageReferences: ["200"],
            couples: [couple1, couple2],
            notes: [],
            noteDefinitions: [:]
        )
        
        // Then: Should have two couples
        XCTAssertEqual(family.couples.count, 2)
        XCTAssertEqual(family.allParents.count, 3) // Husband counted once, two wives
    }
    
    // MARK: - Helper Methods
    
    private func createTestFamily() -> Family {
        let husband = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "15.02.1730",
            noteMarkers: []
        )
        
        let wife = Person(
            name: "Maria",
            patronymic: "Jaakont.",
            birthDate: "10.03.1735",
            noteMarkers: []
        )
        
        let child = Person(
            name: "Liisa",
            birthDate: "12.06.1760",
            noteMarkers: []
        )
        
        let couple = Couple(
            husband: husband,
            wife: wife,
            children: [child]
        )
        
        return Family(
            familyId: "TEST 1",
            pageReferences: ["100", "101"],
            couples: [couple],
            notes: [],
            noteDefinitions: [:]
        )
    }
}
