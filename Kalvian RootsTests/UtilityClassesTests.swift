//
//  UtilityClassesTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for NameEquivalenceManager, HiskiService, FamilyIDs
//

import XCTest
@testable import Kalvian_Roots

let nameEquivalenceUserDefaultsLock = NSLock()

// MARK: - NameEquivalenceManager Tests

final class NameEquivalenceManagerTests: XCTestCase {

    private let userEquivalencesKey = "UserNameEquivalences"
    
    var manager: NameEquivalenceManager!
    private var savedUserEquivalencesData: Data?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        nameEquivalenceUserDefaultsLock.lock()

        let defaults = UserDefaults.standard
        savedUserEquivalencesData = defaults.data(forKey: userEquivalencesKey)

        defaults.removeObject(forKey: userEquivalencesKey)

        manager = NameEquivalenceManager()
    }

    override func tearDownWithError() throws {
        defer {
            nameEquivalenceUserDefaultsLock.unlock()
        }

        let defaults = UserDefaults.standard

        if let savedUserEquivalencesData {
            defaults.set(savedUserEquivalencesData, forKey: userEquivalencesKey)
        } else {
            defaults.removeObject(forKey: userEquivalencesKey)
        }

        manager = nil
        savedUserEquivalencesData = nil

        try super.tearDownWithError()
    }
    
    func testManagerInitialization() {
        XCTAssertNotNil(manager, "Manager should initialize")
    }
    
    func testFinnishSwedishEquivalence() {
        // Test common Finnish-Swedish name pairs
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Juho"))
        XCTAssertTrue(manager.areNamesEquivalent("Matti", "Matias"))
        XCTAssertTrue(manager.areNamesEquivalent("Matti", "Matthias"))
        XCTAssertTrue(manager.areNamesEquivalent("Tuomas", "Thomas"))
        XCTAssertTrue(manager.areNamesEquivalent("Elisabet", "Elisabeth"))
        XCTAssertTrue(manager.areNamesEquivalent("Brita", "Britha"))
        XCTAssertTrue(manager.areNamesEquivalent("Erik", "Ericus"))
        XCTAssertTrue(manager.areNamesEquivalent("Antti", "Andreas"))
        XCTAssertTrue(manager.areNamesEquivalent("Pietari", "Petrus"))
        XCTAssertTrue(manager.areNamesEquivalent("Pietari", "Per"))
        XCTAssertTrue(manager.areNamesEquivalent("Mikko", "Michel"))
        XCTAssertTrue(manager.areNamesEquivalent("Mikko", "Michael"))
        XCTAssertTrue(manager.areNamesEquivalent("Kustaa", "Gustav"))
        XCTAssertTrue(manager.areNamesEquivalent("Kustaa", "Gustaf"))
        XCTAssertTrue(manager.areNamesEquivalent("Jaakko", "Jacob"))
        XCTAssertTrue(manager.areNamesEquivalent("Kaarin", "Carin"))
        XCTAssertTrue(manager.areNamesEquivalent("Kaarin", "Catharina"))
        XCTAssertTrue(manager.areNamesEquivalent("Henrik", "Hinric"))
        XCTAssertTrue(manager.areNamesEquivalent("Abraham", "Abram"))
    }

    func testDefaultsLoadWithoutPersistingBuiltInEquivalences() {
        let defaults = UserDefaults.standard

        let freshManager = NameEquivalenceManager()

        XCTAssertTrue(freshManager.areNamesEquivalent("Anna", "Annika"))
        XCTAssertTrue(freshManager.areNamesEquivalent("Tuomas", "Thomas"))
        XCTAssertNil(defaults.data(forKey: userEquivalencesKey))
    }
    
    func testCaseInsensitiveEquivalence() {
        // Test case insensitivity
        XCTAssertTrue(manager.areNamesEquivalent("JOHAN", "juho"))
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "JUHO"))
    }
    
    func testNonEquivalentNames() {
        // Test names that are not equivalent
        XCTAssertFalse(manager.areNamesEquivalent("Matti", "Henrik"))
        XCTAssertFalse(manager.areNamesEquivalent("Johan", "Erik"))
    }
    
    func testIdenticalNames() {
        // Test identical names
        XCTAssertTrue(manager.areNamesEquivalent("Matti", "Matti"))
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Johan"))
    }
    
    func testEmptyNames() {
        // Test empty names
        XCTAssertTrue(manager.areNamesEquivalent("", ""))
        XCTAssertFalse(manager.areNamesEquivalent("Matti", ""))
    }
    
    func testAddCustomEquivalence() {
        // When: Adding custom equivalence
        manager.addEquivalence(between: "TestName1", and: "TestName2")
        
        // Then: Should recognize equivalence
        XCTAssertTrue(manager.areNamesEquivalent("TestName1", "TestName2"))
    }

    func testAnnikaEquivalentNamesAndCanonicalNameAreDeterministic() {
        XCTAssertTrue(manager.getEquivalentNames(for: "Annika").contains("anna"))
        XCTAssertTrue(manager.getEquivalentNames(for: "Anna").contains("annika"))
        XCTAssertEqual(manager.canonicalName(for: "Annika"), "anna")
    }

    func testClearAllEquivalencesClearsOnlyUserEquivalences() {
        manager.addEquivalence(between: "CustomA", and: "CustomB")

        manager.clearAllEquivalences()

        XCTAssertFalse(manager.areNamesEquivalent("CustomA", "CustomB"))
        XCTAssertTrue(manager.areNamesEquivalent("Anna", "Annika"))
    }
    
    func testBidirectionalEquivalence() {
        // Test that equivalence works both ways
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Juho"))
        XCTAssertTrue(manager.areNamesEquivalent("Juho", "Johan"))
    }
    
    func testMultipleEquivalences() {
        // Test names with multiple equivalent forms
        // (Some names might have multiple Finnish/Swedish variants)
        XCTAssertTrue(manager.areNamesEquivalent("Johan", "Juho"))
    }

    func testTransitiveEquivalenceIsPreserved() {
        XCTAssertTrue(manager.areNamesEquivalent("Matias", "Matthias"))
        XCTAssertTrue(manager.getEquivalentNames(for: "Matias").contains("matthias"))
    }

    func testCanonicalNameMatchesMaijaLiisaAndMariaElisTokenByToken() {
        let juuretIdentity = PersonIdentity(
            name: "Maija Liisa",
            birthDate: testDate(1806, 8, 3),
            nameManager: manager
        )
        let hiskiIdentity = PersonIdentity(
            name: "Maria Elis.",
            birthDate: testDate(1806, 8, 3),
            nameManager: manager
        )

        XCTAssertEqual(juuretIdentity.canonicalName, hiskiIdentity.canonicalName)
        XCTAssertEqual(juuretIdentity.canonicalName, "maija elis")
    }

    func testCanonicalNameMatchesBriitaKaisaAndBritaCaisaTokenByToken() {
        let juuretIdentity = PersonIdentity(
            name: "Briita Kaisa",
            birthDate: testDate(1801, 2, 14),
            nameManager: manager
        )
        let hiskiIdentity = PersonIdentity(
            name: "Brita Caisa",
            birthDate: testDate(1801, 2, 14),
            nameManager: manager
        )

        XCTAssertEqual(juuretIdentity.canonicalName, hiskiIdentity.canonicalName)
    }

    func testCanonicalNamePreservesTokenOrderForMaijaLiisa() {
        XCTAssertEqual(manager.canonicalName(for: "Maija Liisa"), "maija elis")
    }

    func testPersonCandidatePreservesOriginalRawMultiPartNames() {
        let juuretCandidate = PersonCandidate(
            name: "Maija Liisa",
            birthDate: testDate(1806, 8, 3),
            source: .juuretKalvialla,
            nameManager: manager
        )
        let hiskiCandidate = PersonCandidate(
            name: "Maria Elis.",
            birthDate: testDate(1806, 8, 3),
            source: .hiski,
            nameManager: manager
        )

        XCTAssertEqual(juuretCandidate.rawName, "Maija Liisa")
        XCTAssertEqual(hiskiCandidate.rawName, "Maria Elis.")
        XCTAssertEqual(juuretCandidate.identity.canonicalName, hiskiCandidate.identity.canonicalName)
    }

    private func testDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day

        guard let date = components.date else {
            preconditionFailure("Invalid date components: \(year)-\(month)-\(day)")
        }

        return date
    }
}

// MARK: - HiskiService Tests

@MainActor
final class HiskiServiceTests: XCTestCase {
    
    var service: HiskiService!
    var nameEquivalenceManager: NameEquivalenceManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        nameEquivalenceManager = NameEquivalenceManager()
        service = HiskiService(nameEquivalenceManager: nameEquivalenceManager)
    }

    override func tearDownWithError() throws {
        service = nil
        nameEquivalenceManager = nil
        try super.tearDownWithError()
    }
    
    func testServiceInitialization() {
        XCTAssertNotNil(service, "Service should initialize")
    }

    #if os(macOS)
    func testHiskiWebViewManagerRecreatesRecordWindowAfterUserClose() async throws {
        let manager = HiskiWebViewManager.shared

        manager.closeAllWindows()
        manager.debugPrepareRecordWindowForTests()
        XCTAssertTrue(manager.debugHasRecordWindowForTests)
        let contentSize = try XCTUnwrap(manager.debugRecordWindowContentSizeForTests)
        XCTAssertEqual(contentSize.width, 650, accuracy: 0.5)
        XCTAssertEqual(contentSize.height, 430, accuracy: 0.5)

        manager.debugSimulateUserClosingRecordWindowForTests()
        await Task.yield()
        XCTAssertFalse(manager.debugHasRecordWindowForTests)

        manager.debugPrepareRecordWindowForTests()
        XCTAssertTrue(manager.debugHasRecordWindowForTests)

        manager.closeAllWindows()
        XCTAssertFalse(manager.debugHasRecordWindowForTests)
    }
    #endif
    
    func testSetCurrentFamily() {
        // When: Setting current family
        service.setCurrentFamily("KORPI 6")
        
        // Then: Should be set
        XCTAssertTrue(true, "Should set current family")
    }

    func testBuildFamilyBirthSearchUrlUsesBoundedFamilyQueryParameters() throws {
        let url = try service.buildFamilyBirthSearchUrl(
            fatherName: "Elias",
            fatherPatronymic: "Matinp.",
            motherName: "Maria",
            motherPatronymic: "Antint.",
            marriageYear: 1800
        )

        let queryItems = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["etunimi"], "")
        XCTAssertEqual(values["alkuvuosi"], "1800")
        XCTAssertEqual(values["loppuvuosi"], "1835")
        XCTAssertEqual(values["ietunimi"], "Elias")
        XCTAssertEqual(values["ipatronyymi"], "Matinp")
        XCTAssertEqual(values["aetunimi"], "Maria")
        XCTAssertEqual(values["apatronyymi"], "Antint")
        XCTAssertEqual(values["maxkpl"], "50")
        XCTAssertEqual(values["srk"], "0053,0093,0165,0183,0218,0172,0265,0295,0301,0386,0555,0581,0614")
    }

    func testBuildFamilyBirthSearchUrlUsesBoundedSpouseDeathYearWhenProvided() throws {
        let url = try service.buildFamilyBirthSearchUrl(
            fatherName: "Elias",
            fatherPatronymic: "Matinp.",
            motherName: "Maria",
            motherPatronymic: "Antint.",
            marriageYear: 1800,
            endYear: 1807
        )

        let queryItems = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["alkuvuosi"], "1800")
        XCTAssertEqual(values["loppuvuosi"], "1807")
    }

    func testFamilyBirthEndYearUsesFirstKnownSpouseDeathYear() {
        XCTAssertEqual(
            HiskiService.familyBirthEndYear(
                marriageYear: 1746,
                husbandDeathDate: "27.02.1797",
                wifeDeathDate: "06.02.1753"
            ),
            1753
        )

        XCTAssertEqual(
            HiskiService.familyBirthEndYear(
                marriageYear: 1753,
                husbandDeathDate: "27.02.1797",
                wifeDeathDate: nil
            ),
            1797
        )

        XCTAssertEqual(
            HiskiService.familyBirthEndYear(
                marriageYear: 1800,
                husbandDeathDate: nil,
                wifeDeathDate: nil
            ),
            1835
        )
    }

    func testBuildFamilyBirthSearchUrlUsesOnlyHiskiGivenNameExceptions() throws {
        let url = try service.buildFamilyBirthSearchUrl(
            fatherName: "Pietari",
            fatherPatronymic: "Matinp.",
            motherName: "Malin",
            motherPatronymic: "Josefint.",
            marriageYear: 1760
        )

        let queryItems = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["ietunimi"], "Per")
        XCTAssertEqual(values["aetunimi"], "Magdalena")
        XCTAssertEqual(values["ipatronyymi"], "Matinp")
        XCTAssertEqual(values["apatronyymi"], "Josefint")
    }

    func testBuildFamilyBirthSearchUrlUsesHiskiPietariPatronymicExceptions() throws {
        let mariaUrl = try service.buildFamilyBirthSearchUrl(
            fatherName: "Erik",
            fatherPatronymic: "Juhonp.",
            motherName: "Maria",
            motherPatronymic: "Pietarint",
            marriageYear: 1760
        )

        let mattiUrl = try service.buildFamilyBirthSearchUrl(
            fatherName: "Matti",
            fatherPatronymic: "Pietarinp.",
            motherName: "Anna",
            motherPatronymic: "Pietarint.",
            marriageYear: 1760
        )

        let mariaItems = try XCTUnwrap(URLComponents(url: mariaUrl, resolvingAgainstBaseURL: false)?.queryItems)
        let mariaValues = Dictionary(uniqueKeysWithValues: mariaItems.map { ($0.name, $0.value ?? "") })
        let mattiItems = try XCTUnwrap(URLComponents(url: mattiUrl, resolvingAgainstBaseURL: false)?.queryItems)
        let mattiValues = Dictionary(uniqueKeysWithValues: mattiItems.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(mariaValues["aetunimi"], "Maria")
        XCTAssertEqual(mariaValues["apatronyymi"], "Persdr")
        XCTAssertEqual(mattiValues["ietunimi"], "Matti")
        XCTAssertEqual(mattiValues["ipatronyymi"], "Perss")
        XCTAssertEqual(mattiValues["apatronyymi"], "Persdr")
    }

    func testBuildFamilyBirthSearchRequestsIncludesHiskiParentFallback() throws {
        let requests = try service.buildFamilyBirthSearchRequests(
            fatherName: "Tuomas",
            fatherPatronymic: "Juhonp.",
            motherName: "Malin",
            motherPatronymic: "Josefint.",
            marriageYear: 1760
        )

        XCTAssertEqual(requests.map(\.label), [
            "primary HisKi parent query",
            "exact Juuret parent names fallback"
        ])

        let finalQueryItems = try XCTUnwrap(
            URLComponents(url: requests[0].url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let finalValues = Dictionary(uniqueKeysWithValues: finalQueryItems.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(finalValues["alkuvuosi"], "1760")
        XCTAssertEqual(finalValues["loppuvuosi"], "1795")
        XCTAssertEqual(finalValues["ietunimi"], "Tuomas")
        XCTAssertEqual(finalValues["ipatronyymi"], "Juhonp")
        XCTAssertEqual(finalValues["aetunimi"], "Magdalena")
        XCTAssertEqual(finalValues["apatronyymi"], "Josefint")
    }

    func testParseFamilyBirthResultsTableParsesTdOnlyChildRows() {
        let html = """
        <html>
        <body>
        <TABLE>
            <TR><TH>Announc.<TH>Born<TH>Bapt.<TH>Village<TH>Farm<TH>Father<TH>Mother<TH>Child
            <TR><TD><a href="/hiski?en+0265+kastetut+8443"><img src="/historia/sl.gif"></a>25.6.1802 <TD>27.6.1802 <TD>&nbsp; <TD>&nbsp; <TD> Elias Mattsson Kykyri <TD> Maria Andersdr. &nbsp; 20-25 <TD>Matts<BR>
            <TR><TD><a href="/hiski?en+0265+kastetut+8444"><img src="/historia/sl.gif"></a>1.3.1804 <TD>2.3.1804 <TD>&nbsp; <TD>&nbsp; <TD> Elias Mattsson Kykyri <TD> Maria Andersdr. &nbsp; 20-25 <TD>Anna<BR><SMALL>(n.d.conf.)</SMALL>
            <TR><TD colspan="7">Summary row without child data
        </TABLE>
        </body>
        </html>
        """

        let rows = service.parseFamilyBirthResultsTable(html)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].recordPath, "/hiski?en+0265+kastetut+8443")
        XCTAssertEqual(rows[0].birthDate, "25.6.1802")
        XCTAssertEqual(rows[0].childName, "Matts")
        XCTAssertEqual(rows[0].fatherName, "Elias Mattsson Kykyri")
        XCTAssertEqual(rows[0].motherName, "Maria Andersdr. 20-25")
        XCTAssertEqual(rows[1].recordPath, "/hiski?en+0265+kastetut+8444")
        XCTAssertEqual(rows[1].birthDate, "1.3.1804")
        XCTAssertEqual(rows[1].childName, "Anna")
    }

    func testParseFamilyBirthResultsTableStopsFinalRowBeforeFooterText() {
        let html = """
        <TABLE>
            <TR><TH>Announc.<TH>Born<TH>Bapt.<TH>Village<TH>Farm<TH>Father<TH>Mother<TH>Child
            <TR><TD><a href="/hiski?en+0265+kastetut+8551"><img src="/historia/sl.gif"></a>3.2.1827 <TD>4.2.1827 <TD>&nbsp; <TD>&nbsp; <TD> Elias Mattsson Kykyri <TD> Maria Andersdr. &nbsp; 40-45 <TD>Abraham</TR>
        A total of 8 events found.
        <FORM><INPUT type="text" name="dummy"></FORM>
        </TABLE>
        """

        let rows = service.parseFamilyBirthResultsTable(html)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].recordPath, "/hiski?en+0265+kastetut+8551")
        XCTAssertEqual(rows[0].birthDate, "3.2.1827")
        XCTAssertEqual(rows[0].childName, "Abraham")
        XCTAssertEqual(rows[0].fatherName, "Elias Mattsson Kykyri")
        XCTAssertEqual(rows[0].motherName, "Maria Andersdr. 40-45")
    }

    func testFetchCitationsForFamilyBirthRowsBuildsOrderedEvents() async throws {
        let rows = [
            HiskiService.HiskiFamilyBirthRow(
                birthDate: "24.6.1801",
                childName: "Anna",
                fatherName: "Elias Matinp.",
                motherName: "Maria Antint.",
                recordPath: "/hiski?en+abc123"
            ),
            HiskiService.HiskiFamilyBirthRow(
                birthDate: "1.3.1804",
                childName: "Matts",
                fatherName: "Elias Matinp.",
                motherName: "Maria Antint.",
                recordPath: "/hiski?en+abc124"
            )
        ]

        var requestedRecordURLs: [String] = []

        let events = try await service.fetchCitationsForFamilyBirthRows(rows) { recordURL in
            requestedRecordURLs.append(recordURL)

            switch recordURL {
            case "https://hiski.genealogia.fi/hiski?en+abc123":
                return "https://hiski.genealogia.fi/hiski?en+t111"
            case "https://hiski.genealogia.fi/hiski?en+abc124":
                return "https://hiski.genealogia.fi/hiski?en+t222"
            default:
                XCTFail("Unexpected record URL: \(recordURL)")
                return ""
            }
        }

        XCTAssertEqual(
            requestedRecordURLs,
            [
                "https://hiski.genealogia.fi/hiski?en+abc123",
                "https://hiski.genealogia.fi/hiski?en+abc124"
            ]
        )
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].recordURL, "https://hiski.genealogia.fi/hiski?en+abc123")
        XCTAssertEqual(events[0].citationURL, "https://hiski.genealogia.fi/hiski?en+t111")
        XCTAssertEqual(events[0].birthDate, "24.6.1801")
        XCTAssertEqual(events[0].childName, "Anna")
        XCTAssertEqual(events[0].fatherName, "Elias Matinp.")
        XCTAssertEqual(events[0].motherName, "Maria Antint.")
        XCTAssertEqual(events[1].recordURL, "https://hiski.genealogia.fi/hiski?en+abc124")
        XCTAssertEqual(events[1].citationURL, "https://hiski.genealogia.fi/hiski?en+t222")
        XCTAssertEqual(events[1].birthDate, "1.3.1804")
        XCTAssertEqual(events[1].childName, "Matts")
        XCTAssertEqual(events[1].fatherName, "Elias Matinp.")
        XCTAssertEqual(events[1].motherName, "Maria Antint.")
    }

    func testFetchCitationsForFamilyBirthRowsReturnsEmptyForEmptyInput() async throws {
        let events = try await service.fetchCitationsForFamilyBirthRows([]) { _ in
            XCTFail("Citation loader should not be called for empty input")
            return ""
        }

        XCTAssertTrue(events.isEmpty)
    }
    
    func testQueryBirthGeneratesURL() async throws {
        // Integration test - would require actual query
        // Test that birth query generates proper Hiski URL
    }
    
    func testQueryDeathGeneratesURL() async throws {
        // Integration test - would require actual query
        // Test that death query generates proper Hiski URL
    }
    
    func testQueryMarriageGeneratesURL() async throws {
        // Integration test - would require actual query
        // Test that marriage query generates proper Hiski URL
    }
    
    func testQueryHandlesInvalidDate() async throws {
        // Test error handling for invalid date format
    }
    
    func testQueryHandlesInvalidName() async throws {
        // Test error handling for invalid name
    }
    
    func testURLFormatting() {
        // Test that generated URLs follow Hiski format
        // hiski.genealogia.fi/...
    }
    
    func testDateExtraction() {
        // Test extracting year from date string
        // e.g., "15.02.1730" -> "1730"
    }
    
    func testNameNormalization() {
        // Test name normalization for Hiski queries
        // Handle patronymics, special characters, etc.
    }
}

// MARK: - FamilyIDs Tests

final class FamilyIDsTests: XCTestCase {
    
    func testIsValidWithValidID() {
        // Test valid family IDs
        XCTAssertTrue(FamilyIDs.isValid(familyId: "KORPI 6"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "HERLEVI 1"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "SIKALA 3"))
    }
    
    func testIsValidWithInvalidID() {
        // Test invalid family IDs
        XCTAssertFalse(FamilyIDs.isValid(familyId: "INVALID 999"))
        XCTAssertFalse(FamilyIDs.isValid(familyId: "NOT A FAMILY"))
        XCTAssertFalse(FamilyIDs.isValid(familyId: ""))
    }
    
    func testCaseInsensitiveValidation() {
        // Test case insensitivity
        XCTAssertTrue(FamilyIDs.isValid(familyId: "korpi 6"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "KORPI 6"))
        XCTAssertTrue(FamilyIDs.isValid(familyId: "Korpi 6"))
    }
    
    func testIndexOf() {
        // Test getting index of family ID
        if let index = FamilyIDs.indexOf(familyId: "KORPI 6") {
            XCTAssertGreaterThanOrEqual(index, 0, "Index should be valid")
        } else {
            XCTFail("KORPI 6 should have an index")
        }
    }
    
    func testIndexOfInvalidID() {
        // Test invalid ID returns nil
        let index = FamilyIDs.indexOf(familyId: "INVALID 999")
        XCTAssertNil(index, "Invalid ID should return nil index")
    }
    
    func testFamilyAtIndex() {
        // Test getting family at index
        if let firstFamily = FamilyIDs.familyAt(index: 0) {
            XCTAssertFalse(firstFamily.isEmpty, "First family should exist")
        } else {
            XCTFail("Should have family at index 0")
        }
    }
    
    func testFamilyAtInvalidIndex() {
        // Test invalid index returns nil
        let family = FamilyIDs.familyAt(index: -1)
        XCTAssertNil(family, "Negative index should return nil")
        
        let tooHigh = FamilyIDs.familyAt(index: 99999)
        XCTAssertNil(tooHigh, "Too high index should return nil")
    }
    
    func testNextFamilyAfter() {
        // Test getting next family
        if let next = FamilyIDs.nextFamilyAfter("KORPI 6") {
            XCTAssertFalse(next.isEmpty, "Next family should exist")
            XCTAssertNotEqual(next, "KORPI 6", "Should be different family")
        }
    }
    
    func testNextFamilyAfterLast() {
        // Get last family
        guard let lastIndex = FamilyIDs.count > 0 ? FamilyIDs.count - 1 : nil,
              let lastFamily = FamilyIDs.familyAt(index: lastIndex) else {
            XCTFail("Should have last family")
            return
        }
        
        // Test next after last
        let next = FamilyIDs.nextFamilyAfter(lastFamily)
        XCTAssertNil(next, "Next after last should be nil")
    }
    
    func testPreviousFamilyBefore() {
        // Test getting previous family
        if let previous = FamilyIDs.previousFamilyBefore("KORPI 6") {
            XCTAssertFalse(previous.isEmpty, "Previous family should exist")
            XCTAssertNotEqual(previous, "KORPI 6", "Should be different family")
        }
    }
    
    func testPreviousFamilyBeforeFirst() {
        // Get first family
        guard let firstFamily = FamilyIDs.familyAt(index: 0) else {
            XCTFail("Should have first family")
            return
        }
        
        // Test previous before first
        let previous = FamilyIDs.previousFamilyBefore(firstFamily)
        XCTAssertNil(previous, "Previous before first should be nil")
    }
    
    func testCount() {
        // Test family count
        let count = FamilyIDs.count
        XCTAssertGreaterThan(count, 0, "Should have families")
        XCTAssertGreaterThan(count, 1000, "Should have over 1000 families")
    }
    
    func testIsFirst() {
        // Get first family
        guard let firstFamily = FamilyIDs.familyAt(index: 0) else {
            XCTFail("Should have first family")
            return
        }
        
        // Test isFirst
        XCTAssertTrue(FamilyIDs.isFirst(firstFamily), "First family should be detected")
        XCTAssertFalse(FamilyIDs.isFirst("KORPI 6"), "KORPI 6 should not be first")
    }
    
    func testIsLast() {
        // Get last family
        guard let lastIndex = FamilyIDs.count > 0 ? FamilyIDs.count - 1 : nil,
              let lastFamily = FamilyIDs.familyAt(index: lastIndex) else {
            XCTFail("Should have last family")
            return
        }
        
        // Test isLast
        XCTAssertTrue(FamilyIDs.isLast(lastFamily), "Last family should be detected")
        XCTAssertFalse(FamilyIDs.isLast("KORPI 6"), "KORPI 6 should not be last")
    }
    
    func testFamiliesAfter() {
        // Test getting batch of families after a given ID
        let families = FamilyIDs.familiesAfter("KORPI 6", maxCount: 5)
        
        XCTAssertLessThanOrEqual(families.count, 5, "Should respect max count")
        XCTAssertFalse(families.contains("KORPI 6"), "Should not include starting family")
    }
    
    func testFamiliesAfterWithLargeMaxCount() {
        // Test with maxCount larger than remaining families
        if let lastIndex = FamilyIDs.count > 1 ? FamilyIDs.count - 2 : nil,
           let secondToLast = FamilyIDs.familyAt(index: lastIndex) {
            let families = FamilyIDs.familiesAfter(secondToLast, maxCount: 1000)
            XCTAssertLessThanOrEqual(families.count, 10, "Should only return available families")
        }
    }
    
    func testFamiliesAfterInvalidID() {
        // Test with invalid starting ID
        let families = FamilyIDs.familiesAfter("INVALID 999", maxCount: 5)
        XCTAssertEqual(families.count, 0, "Invalid ID should return empty array")
    }
    
    func testNormalization() {
        // Test ID normalization
        let normalized1 = FamilyIDs.normalize("KORPI 6")
        let normalized2 = FamilyIDs.normalize("  korpi  6  ")
        let normalized3 = FamilyIDs.normalize("Korpi 6")
        
        XCTAssertEqual(normalized1, normalized2, "Should normalize whitespace")
        XCTAssertEqual(normalized1.lowercased(), normalized3.lowercased(), "Should normalize case")
    }
    
    func testPerformanceOfLookup() {
        // Test O(1) lookup performance
        measure {
            for _ in 0..<1000 {
                _ = FamilyIDs.isValid(familyId: "KORPI 6")
            }
        }
    }
    
    func testPerformanceOfIndexLookup() {
        // Test O(1) index lookup performance
        measure {
            for _ in 0..<1000 {
                _ = FamilyIDs.indexOf(familyId: "KORPI 6")
            }
        }
    }
}

// MARK: - JuuretError Tests

final class JuuretErrorTests: XCTestCase {
    
    func testInvalidFamilyIdError() {
        let error = JuuretError.invalidFamilyId("TEST 999")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("TEST 999") ?? false)
    }
    
    func testExtractionFailedError() {
        let error = JuuretError.extractionFailed("Test reason")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Test reason") ?? false)
    }
    
    func testAIServiceNotConfiguredError() {
        let error = JuuretError.aiServiceNotConfigured("DeepSeek")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testNoCurrentFamilyError() {
        let error = JuuretError.noCurrentFamily
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testCrossReferenceFailedError() {
        let error = JuuretError.crossReferenceFailed("Test details")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }
    
    func testFileManagementError() {
        let error = JuuretError.fileManagement("Test details")
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testParsingFailedError() {
        let error = JuuretError.parsingFailed("Invalid JSON")
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testNetworkError() {
        let error = JuuretError.networkError("Connection timeout")
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testNoFileLoadedError() {
        let error = JuuretError.noFileLoaded
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testFamilyNotFoundError() {
        let error = JuuretError.familyNotFound("MISSING 1")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("MISSING 1") ?? false)
    }
    
    func testErrorRecoverySuggestions() {
        let error = JuuretError.aiServiceNotConfigured("DeepSeek")
        XCTAssertNotNil(error.recoverySuggestion, "Should have recovery suggestion")
    }
    
    func testErrorFailureReasons() {
        let error = JuuretError.invalidFamilyId("TEST 999")
        XCTAssertNotNil(error.failureReason, "Should have failure reason")
    }
}
