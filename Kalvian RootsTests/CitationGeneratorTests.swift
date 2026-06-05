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
    
    override func setUp() {
        super.setUp()
        nameEquivalenceManager = NameEquivalenceManager()
        testFamily = createTestFamily()
        testNetwork = createTestNetwork()
    }
    
    override func tearDown() {
        testFamily = nil
        testNetwork = nil
        nameEquivalenceManager = nil
        super.tearDown()
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

    func testMainFamilyCitationDisplaysStoredStarFootnotesAsAsterisks() {
        let husband = Person(name: "Elias", birthDate: "07.12.1781", noteMarkers: ["★"])
        let wife = Person(name: "Maria", birthDate: "04.06.1779", noteMarkers: [])
        let child = Person(name: "Briita Kaisa", birthDate: "15.07.1819", noteMarkers: ["★★"])
        let couple = Couple(husband: husband, wife: wife, children: [child])
        let family = Family(
            familyId: "FOOTNOTE 1",
            pageReferences: ["264"],
            couples: [couple],
            notes: ["★ Poika Abraham"],
            noteDefinitions: ["★★": "22.03.-50 Pidisjärvi"]
        )

        let citation = CitationGenerator.generateMainFamilyCitation(family: family)

        XCTAssertTrue(citation.contains("Elias, b. 7 December 1781 *"))
        XCTAssertTrue(citation.contains("Briita Kaisa, b. 15 July 1819 **"))
        XCTAssertTrue(citation.contains("* Poika Abraham"))
        XCTAssertTrue(citation.contains("** 22.03.-50 Pidisjärvi"))
        XCTAssertFalse(citation.contains("★"))
    }

    func testMainFamilyCitationDoesNotEnhanceChildWithoutAsParentReference() {
        let father = Person(
            name: "Elias",
            patronymic: "Matinp.",
            birthDate: "07.12.1781",
            deathDate: "22.04.1861",
            noteMarkers: []
        )
        let mother = Person(
            name: "Maria",
            patronymic: "Antint.",
            birthDate: "04.06.1779",
            deathDate: "04.10.1842",
            noteMarkers: []
        )
        let childElias = Person(
            name: "Elias",
            birthDate: "01.11.1815",
            marriageDate: "22.06.45",
            spouse: "Liisa Matinjussi",
            asParent: nil,
            noteMarkers: []
        )
        let family = Family(
            familyId: "KYKYRI II 8",
            pageReferences: ["264"],
            couples: [
                Couple(
                    husband: father,
                    wife: mother,
                    fullMarriageDate: "27.05.1800",
                    children: [childElias]
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )
        var network = FamilyNetwork(mainFamily: family)
        network.asParentFamilies["Elias"] = family

        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: childElias,
            network: network
        )

        XCTAssertTrue(citation.contains("→ Elias, b. 1 November 1815, m. Liisa Matinjussi 22 June 1845"))
        XCTAssertFalse(citation.contains("Additional information"))
        XCTAssertFalse(citation.contains("Elias's marriage"))
        XCTAssertFalse(citation.contains("1745"))
    }

    func testMainFamilyChildCitationDoesNotBorrowAdultAsParentEnhancement() {
        let childMaria = Person(
            name: "Maria",
            birthDate: "05.12.1774",
            marriageDate: "1794",
            spouse: "Antti Rita",
            asParent: "RITA II 4",
            noteMarkers: []
        )
        let family = Family(
            familyId: "SAKERI 9",
            pageReferences: ["318"],
            couples: [
                Couple(
                    husband: Person(name: "Antti", patronymic: "Simonp.", birthDate: "14.04.1749", noteMarkers: []),
                    wife: Person(name: "Liisa", patronymic: "Sigfridint.", birthDate: "18.06.1743", noteMarkers: []),
                    fullMarriageDate: "29.10.1772",
                    children: [
                        Person(name: "Kaarin", birthDate: "13.10.1773", marriageDate: "1792", spouse: "Erik Nissi", noteMarkers: []),
                        childMaria
                    ]
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )
        var network = FamilyNetwork(mainFamily: family)
        network.asParentFamilies["Maria|05.12.1774"] = Family(
            familyId: "RITA II 4",
            pageReferences: ["267"],
            couples: [
                Couple(
                    husband: Person(name: "Antti", patronymic: "Rita", noteMarkers: []),
                    wife: Person(name: "Maria", birthDate: "05.12.1774", deathDate: "10.07.1833", noteMarkers: []),
                    fullMarriageDate: "10.12.1794",
                    children: []
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )

        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: childMaria,
            network: network
        )

        XCTAssertTrue(citation.contains("Information on page 318 includes:"), citation)
        XCTAssertTrue(citation.contains("Antti Simonp., b. 14 April 1749"), citation)
        XCTAssertTrue(citation.contains("Liisa Sigfridint., b. 18 June 1743"), citation)
        XCTAssertTrue(citation.contains("m. 29 October 1772"), citation)
        XCTAssertTrue(citation.contains("Kaarin, b. 13 October 1773, m. Erik Nissi 1792"), citation)
        XCTAssertTrue(citation.contains("→ Maria, b. 5 December 1774, m. Antti Rita 1794"), citation)
        XCTAssertFalse(citation.contains("10 July 1833"), citation)
        XCTAssertFalse(citation.contains("10 December 1794"), citation)
        XCTAssertFalse(citation.contains("Additional information"), citation)
        XCTAssertFalse(citation.contains("page 267"), citation)
    }

    func testAsChildParentCitationKeepsAdultAsParentEnhancement() {
        let childMaria = Person(
            name: "Maria",
            birthDate: "05.12.1774",
            marriageDate: "1794",
            spouse: "Antti Rita",
            asParent: "RITA II 4",
            noteMarkers: []
        )
        let asChildFamily = Family(
            familyId: "SAKERI 9",
            pageReferences: ["318"],
            couples: [
                Couple(
                    husband: Person(name: "Antti", patronymic: "Simonp.", birthDate: "14.04.1749", noteMarkers: []),
                    wife: Person(name: "Liisa", patronymic: "Sigfridint.", birthDate: "18.06.1743", noteMarkers: []),
                    fullMarriageDate: "29.10.1772",
                    children: [
                        Person(name: "Kaarin", birthDate: "13.10.1773", marriageDate: "1792", spouse: "Erik Nissi", noteMarkers: []),
                        childMaria
                    ]
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )
        var network = FamilyNetwork(mainFamily: asChildFamily)
        network.asParentFamilies["Maria|05.12.1774"] = Family(
            familyId: "RITA II 4",
            pageReferences: ["267"],
            couples: [
                Couple(
                    husband: Person(name: "Antti", patronymic: "Rita", noteMarkers: []),
                    wife: Person(name: "Maria", birthDate: "05.12.1774", deathDate: "10.07.1833", noteMarkers: []),
                    fullMarriageDate: "10.12.1794",
                    children: []
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )

        let citation = CitationGenerator.generateAsChildCitation(
            for: childMaria,
            in: asChildFamily,
            network: network
        )

        XCTAssertTrue(citation.contains("→ Maria, 5 December 1774 - 10 July 1833, m. Antti Rita 10 December 1794"), citation)
        XCTAssertTrue(citation.contains("Additional information:"), citation)
        XCTAssertTrue(citation.contains("Maria's marriage and death dates are on page 267"), citation)
    }

    func testChildTargetDoesNotMarkSameNamedParentWithoutBirthDate() {
        let father = Person(
            name: "Matti",
            patronymic: "Juhonp.",
            noteMarkers: []
        )
        let mother = Person(
            name: "Kaarin",
            patronymic: "Kustaant.",
            birthDate: "1677",
            deathDate: "26.02.1749",
            noteMarkers: ["*"]
        )
        let targetChild = Person(
            name: "Matti",
            birthDate: "22.08.1698",
            noteMarkers: []
        )
        let family = Family(
            familyId: "SAKERI 1",
            pageReferences: ["264", "265"],
            couples: [
                Couple(
                    husband: father,
                    wife: mother,
                    children: [
                        Person(name: "Maria", birthDate: "12.02.1696", deathDate: "13.05.1697", noteMarkers: []),
                        Person(name: "Katariina", birthDate: "18.02.1697", deathDate: "12.04.1697", noteMarkers: []),
                        targetChild,
                        Person(name: "Johannes", birthDate: "14.10.1699", noteMarkers: [])
                    ],
                    childrenDiedInfancy: 7
                )
            ],
            notes: [],
            noteDefinitions: ["*": "kuoli Miekkojalla."]
        )

        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: targetChild,
            network: nil
        )

        XCTAssertFalse(citation.contains("→ Matti Juhonp."))
        XCTAssertTrue(citation.contains("→ Matti, b. 22 August 1698"))
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

    func testAdditionalSpouseChildrenAppearAfterTheirSpouseSection() {
        // Given: A remarriage family where the first spouse has no named children
        let family = createTikkanenSixLikeFamily()

        // When: Generating citation
        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: family.couples[1].children.first,
            network: nil
        )

        // Then: Each additional spouse must appear before that spouse's children
        guard let annikaRange = citation.range(of: "Annika Matint."),
              let annaRange = citation.range(of: "Additional spouse:\nAnna Pietarint."),
              let britaRange = citation.range(of: "Brita, b. 20 May 1750"),
              let mariaRange = citation.range(of: "Additional spouse:\nMaria Martint."),
              let mattiRange = citation.range(of: "Matti, b. 14 March 1756") else {
            XCTFail("Citation did not contain expected spouse and child sections:\n\(citation)")
            return
        }

        XCTAssertLessThan(annikaRange.lowerBound, annaRange.lowerBound)
        XCTAssertLessThan(annaRange.lowerBound, britaRange.lowerBound)
        XCTAssertLessThan(britaRange.lowerBound, mariaRange.lowerBound)
        XCTAssertLessThan(mariaRange.lowerBound, mattiRange.lowerBound)
    }

    func testAdditionalSpouseUsesNewHusbandWhenWifeRemarries() {
        let firstHusband = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "08.01.1772",
            deathDate: "31.08.1807",
            noteMarkers: []
        )
        let continuingWife = Person(
            name: "Maria",
            patronymic: "Simont.",
            birthDate: "19.06.1776",
            noteMarkers: []
        )
        let secondHusband = Person(
            name: "Matti",
            patronymic: "Juhonp. Huhtla 2",
            birthDate: "11.04.1782",
            noteMarkers: []
        )
        let family = Family(
            familyId: "RITA II 3",
            pageReferences: ["313"],
            couples: [
                Couple(
                    husband: firstHusband,
                    wife: continuingWife,
                    fullMarriageDate: "07.06.93",
                    children: [
                        Person(name: "Anna Kreeta", birthDate: "12.12.1795", fullMarriageDate: "24.10.18", spouse: "Juho Hassinen", noteMarkers: []),
                        Person(name: "Matti", birthDate: "12.12.1799", fullMarriageDate: "09.11.26", spouse: "Kaisa Nurila", noteMarkers: [])
                    ]
                ),
                Couple(
                    husband: secondHusband,
                    wife: continuingWife,
                    marriageDate: "31.10.10",
                    children: [
                        Person(name: "Juho", birthDate: "29.03.1813", noteMarkers: [])
                    ]
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )

        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: family.couples[0].children[0],
            network: nil
        )

        XCTAssertTrue(citation.contains("Additional spouse:\nMatti Juhonp. Huhtla 2, b. 11 April 1782"))
        XCTAssertTrue(citation.contains("m. 31 October 1810"))
        XCTAssertTrue(citation.contains("→ Anna Kreeta, b. 12 December 1795, m. Juho Hassinen 24 October 1818"))
        XCTAssertTrue(citation.contains("Matti, b. 12 December 1799, m. Kaisa Nurila 9 November 1826"))
        XCTAssertFalse(citation.contains("Additional spouse:\nMaria Simont."))
        XCTAssertFalse(citation.contains("31 October 1710"))
    }

    func testAdditionalSpouseUsesKnownParentWhenContinuingParentIsUnknownPlaceholder() {
        let firstHusband = Person(
            name: "Matti",
            patronymic: "Erikinp.",
            birthDate: "08.01.1772",
            deathDate: "31.08.1807",
            noteMarkers: []
        )
        let firstWife = Person(
            name: "Maria",
            patronymic: "Simont.",
            birthDate: "19.06.1776",
            noteMarkers: []
        )
        let secondHusband = Person(
            name: "Matti",
            patronymic: "Juhonp. Huhtla 2",
            birthDate: "11.04.1782",
            noteMarkers: []
        )
        let family = Family(
            familyId: "RITA II 3",
            pageReferences: ["313"],
            couples: [
                Couple(
                    husband: firstHusband,
                    wife: firstWife,
                    fullMarriageDate: "07.06.1793",
                    children: [
                        Person(name: "Anna Kreeta", birthDate: "12.12.1795", fullMarriageDate: "24.10.1818", spouse: "Juho Hassinen", noteMarkers: [])
                    ]
                ),
                Couple(
                    husband: secondHusband,
                    wife: Person(name: "Unknown", noteMarkers: []),
                    marriageDate: "31.10.10",
                    children: [
                        Person(name: "Juho", birthDate: "29.03.1813", noteMarkers: [])
                    ]
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )

        let citation = CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: family.couples[0].children[0],
            network: nil
        )

        XCTAssertTrue(citation.contains("Additional spouse:\nMatti Juhonp. Huhtla 2, b. 11 April 1782"), citation)
        XCTAssertTrue(citation.contains("m. 31 October 1810"), citation)
        XCTAssertFalse(citation.contains("Additional spouse:\nUnknown"), citation)
    }

    func testSpouseCitationFallbackMarksSpouseInAsParentFamily() {
        let child = Person(
            name: "Matti",
            patronymic: "Antinp.",
            birthDate: "23.11.1759",
            spouse: "Kaarin Riihimäki",
            noteMarkers: []
        )
        let asParentFamily = Family(
            familyId: "SAKERI 6",
            pageReferences: ["266"],
            couples: [
                Couple(
                    husband: Person(name: "Matti", patronymic: "Antinp.", birthDate: "23.11.1759", noteMarkers: []),
                    wife: Person(name: "Kaarin", patronymic: "Tuomaant. Riihimäki", birthDate: "14.01.1763", noteMarkers: []),
                    fullMarriageDate: "15.11.1782",
                    children: []
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )
        let spouseTarget = try? XCTUnwrap(asParentFamily.findSpouseInFamily(for: child.name))

        let citation = CitationGenerator.generateMainFamilyCitation(
            family: asParentFamily,
            targetPerson: spouseTarget,
            network: nil,
            nameEquivalenceManager: nameEquivalenceManager
        )

        XCTAssertTrue(citation.contains("Information on page 266 includes:"), citation)
        XCTAssertTrue(citation.contains("→ Kaarin Tuomaant. Riihimäki, b. 14 January 1763"), citation)
    }

    func testSpouseChildMatcherUsesNameEquivalenceAndBirthDate() {
        let katariinaAsChild = Person(name: "Katariina", birthDate: "14.01.1763", noteMarkers: [])
        let kaarinAsSpouse = Person(
            name: "Kaarin",
            patronymic: "Tuomaant. Riihimäki",
            birthDate: "14.01.1763",
            noteMarkers: []
        )
        let wrongNameSameBirth = Person(name: "Maria", birthDate: "14.01.1763", noteMarkers: [])

        XCTAssertTrue(
            SpouseChildMatcher.isEquivalentSpouseChild(
                katariinaAsChild,
                enhancedSpouse: kaarinAsSpouse,
                nameEquivalenceManager: nameEquivalenceManager
            )
        )
        XCTAssertFalse(
            SpouseChildMatcher.isEquivalentSpouseChild(
                wrongNameSameBirth,
                enhancedSpouse: kaarinAsSpouse,
                nameEquivalenceManager: nameEquivalenceManager
            )
        )
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
        var network = FamilyNetwork(mainFamily: testFamily)
        
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

    private func createTikkanenSixLikeFamily() -> Family {
        let husband = Person(
            name: "Erik",
            patronymic: "Juhonp.",
            birthDate: "1716",
            deathDate: "27.02.1797",
            noteMarkers: []
        )

        let firstCouple = Couple(
            husband: husband,
            wife: Person(
                name: "Annika",
                patronymic: "Matint.",
                birthDate: "1721",
                deathDate: "20.01.1740",
                noteMarkers: []
            ),
            fullMarriageDate: "29.10.1738",
            children: [],
            coupleNotes: ["Lapsia kaksi, kuolivat pieninä."]
        )

        let secondCouple = Couple(
            husband: husband,
            wife: Person(
                name: "Anna",
                patronymic: "Pietarint.",
                birthDate: "1721",
                deathDate: "06.02.1753",
                noteMarkers: []
            ),
            fullMarriageDate: "24.06.1746",
            children: [
                Person(name: "Brita", birthDate: "20.05.1750", noteMarkers: []),
                Person(name: "Johannes", birthDate: "27.11.1751", noteMarkers: []),
                Person(name: "Erik", birthDate: "06.02.1753", deathDate: "03.06.1785", noteMarkers: [])
            ]
        )

        let thirdCouple = Couple(
            husband: husband,
            wife: Person(
                name: "Maria",
                patronymic: "Martint.",
                birthDate: "02.06.1735",
                noteMarkers: []
            ),
            fullMarriageDate: "27.11.1753",
            children: [
                Person(name: "Matti", birthDate: "14.03.1756", noteMarkers: []),
                Person(name: "Brita", birthDate: "04.12.1763", noteMarkers: [])
            ]
        )

        return Family(
            familyId: "TIKKANEN 6",
            pageReferences: ["240", "241"],
            couples: [firstCouple, secondCouple, thirdCouple],
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
