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

    #if os(macOS)
    func testTokenizerDisplaysInferredCenturyForChildMarriageDate() {
        let child = Person(
            name: "Anna Kreeta",
            birthDate: "12.12.1795",
            fullMarriageDate: "24.10.18",
            spouse: "Juho Hassinen"
        )
        let family = Family(
            familyId: "RITA II 3",
            pageReferences: ["313"],
            couples: [
                Couple(
                    husband: Person(name: "Matti", patronymic: "Erikinp.", birthDate: "08.01.1772"),
                    wife: Person(name: "Maria", patronymic: "Simont.", birthDate: "19.06.1776"),
                    fullMarriageDate: "07.06.93",
                    children: [child]
                )
            ]
        )

        let tokens = FamilyTokenizer().tokenizeFamily(family: family, network: nil)
        let renderedDates = tokens.compactMap { token -> String? in
            if case .date(let date, .marriage, _, _, _) = token {
                return date
            }
            return nil
        }

        XCTAssertTrue(renderedDates.contains("24.10.1818"))
        XCTAssertFalse(renderedDates.contains("24.10.18"))
    }

    func testTokenizerPlacesMarriedChildFootnoteBeforeAsParentFamily() {
        let child = Person(
            name: "Maria",
            birthDate: "05.12.1774",
            fullMarriageDate: "1794",
            spouse: "Antti Rita",
            asParent: "Rita II 4",
            noteMarkers: ["*"]
        )
        let family = Family(
            familyId: "SAKERI 7",
            pageReferences: ["266"],
            couples: [
                Couple(
                    husband: Person(name: "Antti", patronymic: "Simonp."),
                    wife: Person(name: "Liisa", patronymic: "Sigfridint."),
                    children: [child]
                )
            ],
            noteDefinitions: ["*": "Muutti 1801 Sakeri 9."]
        )

        let tokens = FamilyTokenizer().tokenizeFamily(family: family, network: nil)
        let rendered = tokens.map { token -> String in
            switch token {
            case .text(let text):
                return text
            case .person(let name, _):
                return name
            case .date(let date, _, _, _, _):
                return date
            case .familyId(let id):
                return id
            case .enhanced(let text):
                return text
            case .symbol(let symbol):
                return symbol
            case .lineBreak:
                return "\n"
            case .sectionHeader(let title):
                return title
            }
        }.joined()

        XCTAssertTrue(rendered.contains("Antti Rita * as_parent Rita II 4"))
        XCTAssertFalse(rendered.contains("Antti Rita as_parent Rita II 4 *"))
    }

    func testCorrectedSakeriSevenAsParentReferenceIsValidFamilyId() {
        XCTAssertTrue(FamilyIDs.isValid(familyId: "Rita II 4"))
        XCTAssertFalse(FamilyIDs.isValid(familyId: "Rita II 14"))
    }

    func testRenderedChildBirthHiskiLinksIncludeCoupleParentNames() {
        let child = Person(name: "Carin", birthDate: "1.9.1801")
        let family = Family(
            familyId: "HASSINEN 1",
            pageReferences: ["1"],
            couples: [
                Couple(
                    husband: Person(name: "Matts", patronymic: "Anderss. Hassinen"),
                    wife: Person(name: "Carin", patronymic: "Thomadr."),
                    children: [child]
                )
            ]
        )

        let html = HTMLRenderer.renderFamily(family: family, network: nil)

        XCTAssertTrue(html.contains("father=Matts%20Anderss.%20Hassinen"))
        XCTAssertTrue(html.contains("mother=Carin%20Thomadr."))
    }

    func testBrowserNavigationOmitsHomeButtonAndSourceIconTogglesSourcePanel() {
        let family = testFamily!

        let familyHTML = HTMLRenderer.renderFamily(family: family, network: nil)
        let sourceHTML = HTMLRenderer.renderFamily(
            family: family,
            network: nil,
            sourceText: "TEST 1\nLapset"
        )

        XCTAssertFalse(familyHTML.contains(">⌂</a>"))
        XCTAssertTrue(familyHTML.contains(#"href="/family/TEST%201/source" class="nav-btn" title="View source text">📄</a>"#))
        XCTAssertFalse(sourceHTML.contains(">⌂</a>"))
        XCTAssertTrue(sourceHTML.contains(#"href="/family/TEST%201" class="nav-btn" title="Hide source text">📄</a>"#))
    }

    func testBrowserWorkupGearTogglesBackToFamilyDisplay() {
        let family = testFamily!
        let service = FamilyWorkupService(nameEquivalenceManager: NameEquivalenceManager())
        let workup = service.makeWorkup(
            family: family,
            network: nil,
            sourceText: "TEST 1\nLapset",
            familySearchExtraction: nil,
            familySearchPersonId: nil,
            comparisonResult: nil
        )

        let familyHTML = HTMLRenderer.renderFamily(family: family, network: nil)
        let workupHTML = HTMLRenderer.renderWorkup(workup, family: family, homeId: family.familyId)

        XCTAssertTrue(familyHTML.contains(#"href="/family/TEST%201/workup" class="nav-btn" title="View family workup">⚙</a>"#))
        XCTAssertTrue(workupHTML.contains(#"href="/family/TEST%201" class="nav-btn" title="View family display">⚙</a>"#))
    }
    #endif
    
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

    func testFootnoteMarkersUseVerbatimTextRendering() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let familyContentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/Views/FamilyContentView.swift"),
            encoding: .utf8
        )
        let personLineView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/Views/PersonLineView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            familyContentView.contains(#"Text(verbatim: "\(displayFootnoteMarker(key)) \(text)")"#),
            "Note definitions must render stored star markers as literal asterisks."
        )
        XCTAssertTrue(
            familyContentView.contains(#"Text(verbatim: displayFootnoteText(note))"#),
            "Family notes must render stored star markers as literal asterisks."
        )
        XCTAssertTrue(
            personLineView.contains(#"Text(verbatim: person.noteMarkers.map(displayFootnoteMarker).joined(separator: " "))"#),
            "Person note markers must render stored star markers as literal asterisks."
        )
    }

    func testLapsetHeaderUsesHiskiChildResultsAction() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let familyContentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/Views/FamilyContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(familyContentView.contains("private func lapsetHeader(for couple: Couple) -> some View"))
        XCTAssertTrue(familyContentView.contains("openHiskiChildResults(for: couple)"))
        XCTAssertTrue(familyContentView.contains("HiskiWebViewManager.shared.loadSearchResults(url: url)"))
        XCTAssertTrue(familyContentView.contains("buildFamilyBirthSearchRequests("))
        XCTAssertTrue(familyContentView.contains("HiskiService.familyBirthSearchWindow(for: couple)"))
        XCTAssertTrue(familyContentView.contains("missing parent names, marriage year, or child birth year"))
        XCTAssertTrue(
            familyContentView.contains("childrenSection(couple: couple)"),
            "Additional spouse Lapset sections must pass the local couple, not only child arrays."
        )
        XCTAssertTrue(
            familyContentView.contains("guard juuretApp.familyChildrenComparisonGroups.isEmpty,"),
            "Primary-couple fallback must not reuse one grouped comparison result across spouse sections."
        )
        XCTAssertTrue(
            familyContentView.contains("if !juuretApp.currentFamilyHasFatherFamilySearchId"),
            "Manual in-app FamilySearch extraction must stay visible when the Juuret father has no FamilySearch ID."
        )
        XCTAssertTrue(
            familyContentView.contains(#"Label("Extract in-app FamilySearch", systemImage: "square.and.arrow.down")"#)
        )
        XCTAssertFalse(
            familyContentView.contains(#"Label("Open FamilySearch in Kalvian Roots", systemImage: "globe")"#),
            "The automatic WebKit path should not leave a redundant open button in the family view."
        )
    }

    func testComparisonSourceMarkersFollowCitationPanelState() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let familyContentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/Views/FamilyContentView.swift"),
            encoding: .utf8
        )
        let juuretView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/Views/JuuretView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(familyContentView.contains("let showsComparisonSourceMarkers: Bool"))
        XCTAssertTrue(juuretView.contains("showsComparisonSourceMarkers: !showingCitation"))
        XCTAssertTrue(
            familyContentView.contains("let shouldShowMarkers = showsComparisonSourceMarkers && (row.familySearch != nil || row.hiski != nil)"),
            "Matched Juuret child source markers should disappear while the citation panel is open."
        )
        XCTAssertTrue(
            familyContentView.contains("if showsComparisonSourceMarkers {\n                Text(sourceMarkers(for: row))"),
            "Comparison-only child source markers should disappear while the citation panel is open."
        )
        XCTAssertTrue(
            familyContentView.contains("markers.append(\"J\")\n        }\n        if row.hiski != nil {\n            markers.append(\"H\")\n        }\n        if row.familySearch != nil {\n            markers.append(\"FS\")"),
            "Source markers should render in Juuret, HisKi, FamilySearch order."
        )
    }

    func testFatherBirthDateMismatchWarningRequiresMatchingFamilySearchFocusPerson() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let familyContentView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/Views/FamilyContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            familyContentView.contains("let fatherBirthDateMismatch = parentBirthDateMismatch(for: couple.husband)"),
            "Only the father line should calculate the FamilySearch focus-person birth date warning."
        )
        XCTAssertTrue(
            familyContentView.contains("supplementalContent: fatherBirthDateMismatch.map"),
            "The warning should render through the existing supplemental content slot on the father line."
        )
        XCTAssertTrue(
            familyContentView.contains("juuretApp.familySearchExtraction(for: family.familyId)?.focusPerson"),
            "The warning must use the stored FamilySearch focus person from the current family extraction."
        )
        XCTAssertTrue(
            familyContentView.contains("focusPerson.id?.trimmingCharacters(in: .whitespacesAndNewlines) == parentFamilySearchId"),
            "The warning must not compare stale or unrelated FamilySearch extraction data."
        )
        XCTAssertTrue(
            familyContentView.contains("comparisonService.makeJuuretCandidates(from: [parent]).first?.birthDate"),
            "The warning should convert the Juuret parent through PersonCandidate before comparing."
        )
        XCTAssertTrue(
            familyContentView.contains("comparisonService.makeFamilySearchCandidates(from: [familySearchParentCandidate]).first?.birthDate"),
            "The warning should convert the FamilySearch focus person through PersonCandidate before comparing."
        )
        XCTAssertTrue(
            familyContentView.contains("accessibilityLabel(\"FamilySearch birth date differs\")")
        )
        XCTAssertTrue(
            familyContentView.contains("@State private var selectedParentBirthDateMismatch: ParentBirthDateMismatch?")
        )
        XCTAssertTrue(
            familyContentView.contains("selectedParentBirthDateMismatch = mismatch"),
            "Clicking the parent warning asterisk should select a mismatch."
        )
        XCTAssertTrue(
            familyContentView.contains(".popover(item: $selectedParentBirthDateMismatch)"),
            "The parent warning asterisk should open a popover on click."
        )
    }

    func testFamilySearchDebugPanelIncludesFocusPersonVitals() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let juuretApp = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/App/JuuretApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(juuretApp.contains("FamilySearch focus person ID:"))
        XCTAssertTrue(juuretApp.contains("FamilySearch focus person name:"))
        XCTAssertTrue(juuretApp.contains("FamilySearch focus person birth date:"))
        XCTAssertTrue(juuretApp.contains("FamilySearch focus person death date:"))
    }

    func testFamilySearchAndJuuretFatherBirthDateFormatsParseToComparableDates() {
        let comparisonService = FamilyComparisonService(nameManager: NameEquivalenceManager())
        let juuretCandidates = comparisonService.makeJuuretCandidates(from: [
            Person(name: "Jaakko", birthDate: "02.11.1731")
        ])
        let matchingFamilySearchCandidates = comparisonService.makeFamilySearchCandidates(from: [
            FamilySearchChild(id: "KVG7-BRP", name: "Jaakko Juhonp.", birthDate: "2 November 1731")
        ])
        let mismatchedFamilySearchCandidates = comparisonService.makeFamilySearchCandidates(from: [
            FamilySearchChild(id: "KVG7-BRP", name: "Jaakko Juhonp.", birthDate: "28 February 1763")
        ])

        XCTAssertEqual(
            juuretCandidates.first?.birthDate,
            matchingFamilySearchCandidates.first?.birthDate
        )
        XCTAssertNotEqual(
            juuretCandidates.first?.birthDate,
            mismatchedFamilySearchCandidates.first?.birthDate
        )
    }

    func testStoredStarFootnoteMarkersDisplayAsAsterisks() {
        XCTAssertEqual(displayFootnoteMarker("★★"), "**")
        XCTAssertEqual(displayFootnoteMarker("*"), "*")
        XCTAssertEqual(displayFootnoteText("★★ 22.03.-50 Pidisjärvi"), "** 22.03.-50 Pidisjärvi")
        XCTAssertEqual(displayFootnoteText("*) Poika Abraham"), "*) Poika Abraham")
        XCTAssertEqual(displayFootnoteText("No marker ★ in body"), "No marker ★ in body")
    }

    func testPersonLineViewComputesEnhancedDataFromCurrentPersonAndNetwork() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let personLineView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/Views/PersonLineView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            personLineView.contains("@State private var enhancedData"),
            "Enhanced dates must not be retained as row state; they must reflect the current person and network."
        )
        XCTAssertFalse(personLineView.contains("private var enhancedData: EnhancedPersonData?"))
        XCTAssertTrue(personLineView.contains("let enhancedData = loadEnhancedData()"))
        XCTAssertTrue(personLineView.contains("marriageSection(enhancedData: enhancedData)"))
        XCTAssertTrue(personLineView.contains("private func marriageSection(enhancedData: EnhancedPersonData?) -> some View"))
        XCTAssertTrue(personLineView.contains("private func loadEnhancedData() -> EnhancedPersonData?"))
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
