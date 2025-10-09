//
//  Kalvian_RootsTests.swift
//  Kalvian RootsTests
//
//  Created by Michael Bendio on 7/11/25.
//

import Foundation
import Testing
@testable import Kalvian_Roots

struct Kalvian_RootsTests {

    // MARK: - Family ID validation
    @Test func testFamilyIDsValidation() async throws {
        #expect(FamilyIDs.isValid(familyId: "KORPI 6"))
        #expect(!FamilyIDs.isValid(familyId: "NON-EXISTENT 99"))
    }

    // MARK: - Hiski service initialization
    @Test func testHiskiServiceInitialization() async throws {
        let service = HiskiService()
        service.setCurrentFamily("KORPI 6")
        
        // Just verify service can be created
        #expect(service != nil)
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
        let husband = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "15.02.1730",
            deathDate: "20.05.1800",
            noteMarkers: []
        )
        
        let wife = Person(
            name: "Maria",
            patronymic: "Jaakont.",
            birthDate: "10.03.1735",
            deathDate: nil,
            noteMarkers: []
        )
        
        let child = Person(
            name: "Liisa",
            birthDate: "12.06.1760",
            noteMarkers: []
        )
        
        let family = Family(
            familyId: "TEST 1",
            pageReferences: ["105", "106"],
            husband: husband,
            wife: wife,
            marriageDate: "1755",
            children: [child]
        )
        
        let citation = CitationGenerator.generateMainFamilyCitation(family: family)

        // Basic structure checks
        #expect(citation.contains("Information on pages 105, 106 includes:"))
        #expect(citation.contains("Matti Erikinp."))
        #expect(citation.contains("Maria Jaakont."))
    }

    // MARK: - Citation generation (as_child style)
    @Test func testAsChildCitationStyle() async throws {
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
        
        let family = Family(
            familyId: "TEST 1",
            pageReferences: ["105"],
            husband: husband,
            wife: wife,
            children: [child]
        )
        
        // Generate as_child citation for the father
        let citation = CitationGenerator.generateAsChildCitation(for: husband, in: family)

        // Should contain children section
        #expect(citation.contains("Children"))
        #expect(citation.contains("Liisa"))
    }
    
    // MARK: - Person parent name extraction
    @Test func testPersonParentNames() async throws {
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
        
        let family = Family(
            familyId: "TEST 1",
            pageReferences: ["105"],
            husband: husband,
            wife: wife,
            marriageDate: "1755",
            children: [child]
        )
        
        // Test getParentNames method
        if let parentNames = family.getParentNames(for: child) {
            #expect(parentNames.father == "Matti Erikinp.")
            #expect(parentNames.mother == "Maria Jaakont.")
        } else {
            Issue.record("Parent names should be found")
        }
    }
    
    // MARK: - File Manager initialization
    @Test func testFileManagerInitialization() async throws {
        let fileManager = RootsFileManager()
        
        // Just verify it initializes
        #expect(fileManager != nil)
    }
}
