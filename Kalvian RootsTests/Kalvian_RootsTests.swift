//
//  Kalvian_RootsTests.swift
//  Kalvian RootsTests
//
//  Created by Michael Bendio on 7/11/25.
//

import Testing
@testable import Kalvian_Roots

struct Kalvian_RootsTests {

    // MARK: - Family ID validation
    @Test func testFamilyIDsValidation() async throws {
        #expect(FamilyIDs.isValid(familyId: "KORPI 6"))
        #expect(!FamilyIDs.isValid(familyId: "NON-EXISTENT 99"))
    }

    // MARK: - Hiski query building
    @Test func testHiskiQueryBirthAndDeath() async throws {
        var person = Person(name: "Maria", patronymic: "Jaakont.", birthDate: "27.03.1763", deathDate: "28.07.1784", noteMarkers: [])
        person.fatherName = "Jaakko Jaakonp."
        person.motherName = "Maria Jaakont."

        // Birth query
        let birth = HiskiQuery.from(person: person, eventType: .birth)
        #expect(birth != nil)
        #expect(birth?.queryURL.contains("et=birth") == true)
        #expect(birth?.queryURL.contains("child=Maria") == true)
        #expect(birth?.queryURL.contains("date=27.03.1763") == true)

        // Death query
        let death = HiskiQuery.from(person: person, eventType: .death)
        #expect(death != nil)
        #expect(death?.queryURL.contains("et=death") == true)
        #expect(death?.queryURL.contains("person=Maria%20Jaakont.") == true)
        #expect(death?.queryURL.contains("date=28.07.1784") == true)
    }

    // MARK: - Name equivalence defaults
    @Test func testNameEquivalenceDefaults() async throws {
        let mgr = NameEquivalenceManager()
        #expect(mgr.areNamesEquivalent("Johan", "Juho"))
        #expect(mgr.areNamesEquivalent("Matti", "Matias"))
        #expect(!mgr.areNamesEquivalent("Matti", "Henrik"))
    }

    // MARK: - Citation generation (main family)
    @Test func testMainFamilyCitation() async throws {
        let family = Family.sampleFamily()
        let citation = EnhancedCitationGenerator.generateMainFamilyCitation(family: family)

        // Basic structure checks
        #expect(citation.contains("Information on pages 105, 106 includes:"))
        #expect(citation.contains("Matti Erikinp."))
        #expect(citation.contains("Children:"))
        #expect(citation.contains("Maria"))
    }

    // MARK: - Citation generation (as_child style)
    @Test func testAsChildCitationStyle() async throws {
        let family = Family.sampleFamily()
        // Choose father as the target person in parent's family context
        let person = family.father
        let citation = EnhancedCitationGenerator.generateAsChildCitation(for: person, in: family)

        // Should use b. for birth and show marriage year (not 8-digit date formatting)
        #expect(citation.contains("Children"))
        #expect(citation.contains("Maria, b. 10 February 1752"))
    }

    // MARK: - Person validation (date formats)
    @Test func testPersonDateValidationWarnings() async throws {
        // Invalid birth date should produce a warning
        let p1 = Person(name: "Test", birthDate: "31.02.1700", noteMarkers: [])
        let warnings1 = p1.validateData()
        #expect(warnings1.contains(where: { $0.contains("Unusual birth date format") }))

        // Valid full date should be ok
        let p2 = Person(name: "Valid", birthDate: "09.09.1727", noteMarkers: [])
        let warnings2 = p2.validateData()
        #expect(!warnings2.contains(where: { $0.contains("Unusual birth date format") }))
    }

    // MARK: - FileManager family extraction
    @Test func testExtractFamilyText() async throws {
        let content = """
        HYYPPÄ 6, page 370
        ★ 09.10.1726    Jaakko Jaakonp. {Hyyppä 5}                            † 07.03.1789
        ★ 02.03.1733    Maria Jaakont. {Pietilä 7}                            † 18.04.1753
        ∞ 08.10.1752.
        Lapset
        ★ 27.03.1763    Maria            ∞ 82 Matti Korpi                     Korpi 9

        HYYPPÄ 5, page 369
        ★ 11.07.1698    Jaakko Jaakonp. {Hyyppä 4}                            † 31.08.1735
        """
        let fm = FileManager()
        let extracted = fm.extractFamilyText(familyId: "HYYPPÄ 6", from: content)
        #expect(extracted != nil)
        #expect(extracted?.contains("Lapset") == true)
        #expect(extracted?.contains("Maria            ∞ 82 Matti Korpi") == true)
    }
}
