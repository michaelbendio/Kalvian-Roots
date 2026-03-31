import Foundation
import XCTest
@testable import Kalvian_Roots

final class FamilyComparisonResultTests: XCTestCase {

    private let equivalencesKey = "NameEquivalences"
    private let equivalenceVersionKey = "NameEquivalencesVersion"

    private var nameManager: NameEquivalenceManager!
    private var savedEquivalencesData: Data?
    private var savedVersionValue: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()

        let defaults = UserDefaults.standard
        savedEquivalencesData = defaults.data(forKey: equivalencesKey)
        savedVersionValue = defaults.object(forKey: equivalenceVersionKey)

        defaults.removeObject(forKey: equivalencesKey)
        defaults.removeObject(forKey: equivalenceVersionKey)

        nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        nameManager.addEquivalence(between: "Liisa", and: "Elisabeta")
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard

        if let savedEquivalencesData {
            defaults.set(savedEquivalencesData, forKey: equivalencesKey)
        } else {
            defaults.removeObject(forKey: equivalencesKey)
        }

        if let savedVersionValue {
            defaults.set(savedVersionValue, forKey: equivalenceVersionKey)
        } else {
            defaults.removeObject(forKey: equivalenceVersionKey)
        }

        nameManager = nil
        savedEquivalencesData = nil
        savedVersionValue = nil

        try super.tearDownWithError()
    }

    func testThreeSourceMatchForLiisaAcrossFamilySearchJuuretAndHiski() throws {
        let familySearchCandidate = candidate(
            name: "Liisa",
            birth: date(1797, 10, 12),
            source: .familySearch,
            familySearchId: "LIIISA-FS-1797"
        )
        let juuretCandidate = candidate(
            name: "Liisa",
            birth: date(1797, 10, 12),
            source: .juuretKalvialla
        )
        let hiskiCandidate = candidate(
            name: "Elisabeta",
            birth: date(1797, 10, 12),
            source: .hiski,
            hiskiCitation: hiskiCitation("liisa-1797")
        )

        XCTAssertTrue(nameManager.areNamesEquivalent("Liisa", "Elisabeta"))
        XCTAssertEqual(familySearchCandidate.identity.canonicalName, hiskiCandidate.identity.canonicalName)
        XCTAssertEqual(familySearchCandidate.identity.birthDate, hiskiCandidate.identity.birthDate)
        XCTAssertTrue(familySearchCandidate.identity.matches(hiskiCandidate.identity))
        XCTAssertTrue(familySearchCandidate.isFromFamilySearch)
        XCTAssertTrue(juuretCandidate.isFromJuuret)
        XCTAssertTrue(hiskiCandidate.isFromHiski)

        let result = FamilyComparisonResult(
            familySearch: [familySearchCandidate],
            juuretKalvialla: [juuretCandidate],
            hiski: [hiskiCandidate]
        )

        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.familySearchOnly.count, 0)
        XCTAssertEqual(result.juuretOnly.count, 0)
        XCTAssertEqual(result.hiskiOnly.count, 0)

        let match = try XCTUnwrap(result.matches.first)
        XCTAssertNotNil(match.familySearch)
        XCTAssertNotNil(match.juuretKalvialla)
        XCTAssertNotNil(match.hiski)
        XCTAssertEqual(match.familySearch?.rawName, "Liisa")
        XCTAssertEqual(match.juuretKalvialla?.rawName, "Liisa")
        XCTAssertEqual(match.hiski?.rawName, "Elisabeta")
    }

    func testFamilySearchAndHiskiMatchWhenJuuretEntryIsMissingForElias() throws {
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Elias",
                    birth: date(1803, 8, 10),
                    source: .familySearch,
                    familySearchId: "ELIAS-FS-1803"
                )
            ],
            juuretKalvialla: [],
            hiski: [
                candidate(
                    name: "Elias",
                    birth: date(1803, 8, 10),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("elias-1803")
                )
            ]
        )

        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.familySearchOnly.count, 0)
        XCTAssertEqual(result.juuretOnly.count, 0)
        XCTAssertEqual(result.hiskiOnly.count, 0)

        let match = try XCTUnwrap(result.matches.first)
        XCTAssertNotNil(match.familySearch)
        XCTAssertNil(match.juuretKalvialla)
        XCTAssertNotNil(match.hiski)
    }

    func testHiskiTwinRecordSplitProducesTwoSeparateMatches() {
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Maria",
                    birth: date(1791, 11, 26),
                    source: .familySearch,
                    familySearchId: "MARIA-FS-1791"
                ),
                candidate(
                    name: "Catharina",
                    birth: date(1791, 11, 26),
                    source: .familySearch,
                    familySearchId: "CATHARINA-FS-1791"
                )
            ],
            juuretKalvialla: [],
            hiski: [
                candidate(
                    name: "Maria",
                    birth: date(1791, 11, 26),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("maria-1791")
                ),
                candidate(
                    name: "Catharina",
                    birth: date(1791, 11, 26),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("catharina-1791")
                )
            ]
        )

        XCTAssertEqual(result.matches.count, 2)
        XCTAssertEqual(Set(result.matches.map(\.identity.canonicalName)), ["catharina", "maria"])
        XCTAssertTrue(result.matches.allSatisfy { $0.familySearch != nil })
        XCTAssertTrue(result.matches.allSatisfy { $0.hiski != nil })
        XCTAssertTrue(result.matches.allSatisfy { $0.juuretKalvialla == nil })
    }

    func testHiskiOnlyChildIsReportedWhenNoFamilySearchOrJuuretEntryExists() {
        let result = FamilyComparisonResult(
            familySearch: [],
            juuretKalvialla: [],
            hiski: [
                candidate(
                    name: "(Son, dodf.)",
                    birth: date(1806, 11, 22),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("son-dodf-1806")
                )
            ]
        )

        XCTAssertEqual(result.hiskiOnly.count, 1)
        XCTAssertEqual(result.familySearchOnly.count, 0)
        XCTAssertEqual(result.juuretOnly.count, 0)
        XCTAssertEqual(result.hiskiOnly.first?.rawName, "(Son, dodf.)")
    }

    func testFamilySearchDuplicateLeavesOneUnmatchedDuplicateWhenHiskiHasSingleBaptism() {
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Catharina",
                    birth: date(1791, 11, 26),
                    source: .familySearch,
                    familySearchId: "CATHARINA-FS-1791-A"
                ),
                candidate(
                    name: "Catharina",
                    birth: date(1791, 11, 26),
                    source: .familySearch,
                    familySearchId: "CATHARINA-FS-1791-B"
                )
            ],
            juuretKalvialla: [],
            hiski: [
                candidate(
                    name: "Catharina",
                    birth: date(1791, 11, 26),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("catharina-single-baptism")
                )
            ]
        )

        XCTAssertEqual(result.familySearchOnly.count, 1)
    }

    private func candidate(
        name: String,
        birth: Date,
        source: PersonCandidate.SourceType,
        familySearchId: String? = nil,
        hiskiCitation: URL? = nil
    ) -> PersonCandidate {
        PersonCandidate(
            name: name,
            birthDate: birth,
            source: source,
            nameManager: nameManager,
            familySearchId: familySearchId,
            hiskiCitation: hiskiCitation
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
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

    private func hiskiCitation(_ slug: String) -> URL {
        guard let url = URL(string: "https://hiski.genealogia.fi/\(slug)") else {
            preconditionFailure("Invalid HisKi citation slug: \(slug)")
        }

        return url
    }
}

final class FamilyComparisonServiceTests: XCTestCase {

    private let equivalencesKey = "NameEquivalences"
    private let equivalenceVersionKey = "NameEquivalencesVersion"

    private var service: FamilyComparisonService!
    private var nameManager: NameEquivalenceManager!
    private var savedEquivalencesData: Data?
    private var savedVersionValue: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()

        let defaults = UserDefaults.standard
        savedEquivalencesData = defaults.data(forKey: equivalencesKey)
        savedVersionValue = defaults.object(forKey: equivalenceVersionKey)

        defaults.removeObject(forKey: equivalencesKey)
        defaults.removeObject(forKey: equivalenceVersionKey)

        nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        nameManager.addEquivalence(between: "Liisa", and: "Elisabeta")
        service = FamilyComparisonService(nameManager: nameManager)
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard

        if let savedEquivalencesData {
            defaults.set(savedEquivalencesData, forKey: equivalencesKey)
        } else {
            defaults.removeObject(forKey: equivalencesKey)
        }

        if let savedVersionValue {
            defaults.set(savedVersionValue, forKey: equivalenceVersionKey)
        } else {
            defaults.removeObject(forKey: equivalenceVersionKey)
        }

        service = nil
        nameManager = nil
        savedEquivalencesData = nil
        savedVersionValue = nil
        try super.tearDownWithError()
    }

    func testMakeHiskiCandidatesConvertsOneEventToOneCandidate() throws {
        let event = HiskiService.HiskiFamilyBirthEvent(
            birthDate: "25.6.1802",
            childName: "Matti",
            fatherName: "Elias Matinp.",
            motherName: "Maria Antint.",
            recordURL: "https://hiski.genealogia.fi/hiski?en+4092193",
            citationURL: "https://hiski.genealogia.fi/hiski?en+t4092193"
        )

        let candidates = service.makeHiskiCandidates(from: [event])

        XCTAssertEqual(candidates.count, 1)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.rawName, "Matti")
        XCTAssertEqual(candidate.source, .hiski)
        XCTAssertNil(candidate.familySearchId)
        XCTAssertEqual(candidate.hiskiCitation, URL(string: "https://hiski.genealogia.fi/hiski?en+t4092193"))
        XCTAssertEqual(candidate.birthDate, date(1802, 6, 25))
    }

    func testMakeHiskiCandidatesPreservesInputOrdering() {
        let events = [
            HiskiService.HiskiFamilyBirthEvent(
                birthDate: "25.6.1802",
                childName: "Matti",
                fatherName: "Elias Matinp.",
                motherName: "Maria Antint.",
                recordURL: "https://hiski.genealogia.fi/hiski?en+4092193",
                citationURL: "https://hiski.genealogia.fi/hiski?en+t4092193"
            ),
            HiskiService.HiskiFamilyBirthEvent(
                birthDate: "1.3.1804",
                childName: "Liisa",
                fatherName: "Elias Matinp.",
                motherName: "Maria Antint.",
                recordURL: "https://hiski.genealogia.fi/hiski?en+4092194",
                citationURL: "https://hiski.genealogia.fi/hiski?en+t4092194"
            )
        ]

        let candidates = service.makeHiskiCandidates(from: events)

        XCTAssertEqual(candidates.map(\.rawName), ["Matti", "Liisa"])
        XCTAssertEqual(
            candidates.map(\.hiskiCitation),
            [
                URL(string: "https://hiski.genealogia.fi/hiski?en+t4092193"),
                URL(string: "https://hiski.genealogia.fi/hiski?en+t4092194")
            ]
        )
    }

    func testMakeHiskiCandidatesReturnsEmptyForEmptyInput() {
        let candidates = service.makeHiskiCandidates(from: [])

        XCTAssertTrue(candidates.isEmpty)
    }

    func testMakeJuuretCandidatesConvertsChildrenToJuuretCandidates() throws {
        let children = [
            Person(name: "Liisa", birthDate: "12.10.1797", noteMarkers: []),
            Person(name: "Maija Liisa", birthDate: "03.08.1806", noteMarkers: [])
        ]

        let candidates = service.makeJuuretCandidates(from: children)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map(\.rawName), ["Liisa", "Maija Liisa"])
        XCTAssertEqual(candidates.map(\.source), [.juuretKalvialla, .juuretKalvialla])
        XCTAssertEqual(candidates.map(\.birthDate), [date(1797, 10, 12), date(1806, 8, 3)])
        XCTAssertTrue(candidates.allSatisfy { $0.familySearchId == nil })
        XCTAssertTrue(candidates.allSatisfy { $0.hiskiCitation == nil })
    }

    func testMakeJuuretCandidatesReturnsEmptyForEmptyInput() {
        let candidates = service.makeJuuretCandidates(from: [])

        XCTAssertTrue(candidates.isEmpty)
    }

    func testCompareJuuretAndHiskiCandidatesBuildsExactMatch() throws {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                )
            ]
        )

        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.juuretOnly.count, 0)
        XCTAssertEqual(result.hiskiOnly.count, 0)

        let match = try XCTUnwrap(result.matches.first)
        XCTAssertEqual(match.juuretKalvialla?.rawName, "Matti")
        XCTAssertEqual(match.hiski?.rawName, "Matti")
        XCTAssertNil(match.familySearch)
    }

    func testCompareJuuretAndHiskiCandidatesBuildsEquivalentNameMatch() throws {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Liisa",
                    birth: date(1797, 10, 12),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Elisabeta",
                    birth: date(1797, 10, 12),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("liisa-1797")
                )
            ]
        )

        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.juuretOnly.count, 0)
        XCTAssertEqual(result.hiskiOnly.count, 0)
        XCTAssertEqual(result.matches.first?.juuretKalvialla?.rawName, "Liisa")
        XCTAssertEqual(result.matches.first?.hiski?.rawName, "Elisabeta")
    }

    func testCompareJuuretAndHiskiCandidatesReportsSourceOnlyChildren() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Anders",
                    birth: date(1806, 11, 22),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("anders-1806")
                )
            ]
        )

        XCTAssertEqual(result.matches.count, 0)
        XCTAssertEqual(result.juuretOnly.count, 1)
        XCTAssertEqual(result.hiskiOnly.count, 1)
        XCTAssertEqual(result.juuretOnly.first?.rawName, "Maija Liisa")
        XCTAssertEqual(result.hiskiOnly.first?.rawName, "Anders")
    }

    func testCompareJuuretAndHiskiCandidatesKeepsMatchesOrderedByBirthDate() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Liisa",
                    birth: date(1797, 10, 12),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                ),
                candidate(
                    name: "Elisabeta",
                    birth: date(1797, 10, 12),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("liisa-1797")
                )
            ]
        )

        XCTAssertEqual(
            result.matches.compactMap(\.identity.birthDate),
            [date(1797, 10, 12), date(1802, 6, 25)]
        )
        XCTAssertEqual(result.matches.map { $0.juuretKalvialla?.rawName }, ["Liisa", "Matti"])
    }

    func testCompareJuuretAndHiskiCandidatesReturnsEmptyResultForEmptyInputs() {
        let result = service.compare(juuretCandidates: [], hiskiCandidates: [])

        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertTrue(result.juuretOnly.isEmpty)
        XCTAssertTrue(result.hiskiOnly.isEmpty)
        XCTAssertTrue(result.familySearchOnly.isEmpty)
    }

    func testCompareJuuretAndHiskiCandidatesKeepsJuuretOnlyEmptyWhenAllJuuretChildrenMatch() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Liisa",
                    birth: date(1797, 10, 12),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Elisabeta",
                    birth: date(1797, 10, 12),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("liisa-1797")
                ),
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                )
            ]
        )

        XCTAssertEqual(result.matches.count, 2)
        XCTAssertTrue(result.juuretOnly.isEmpty)
        XCTAssertTrue(result.hiskiOnly.isEmpty)
    }

    func testRenderJuuretHiskiReportIncludesAllSectionsInOrder() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Liisa",
                    birth: date(1797, 10, 12),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Elisabeta",
                    birth: date(1797, 10, 12),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("liisa-1797")
                ),
                candidate(
                    name: "Anders",
                    birth: date(1806, 11, 22),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("anders-1806")
                )
            ]
        )

        let report = service.renderJuuretHiskiReport(result)

        XCTAssertTrue(report.contains("Matches\n-------"))
        XCTAssertTrue(report.contains("Juuret only\n-----------"))
        XCTAssertTrue(report.contains("HisKi only\n----------"))

        let matchesRange = report.range(of: "Matches\n-------")
        let juuretOnlyRange = report.range(of: "Juuret only\n-----------")
        let hiskiOnlyRange = report.range(of: "HisKi only\n----------")

        XCTAssertNotNil(matchesRange)
        XCTAssertNotNil(juuretOnlyRange)
        XCTAssertNotNil(hiskiOnlyRange)
        XCTAssertLessThan(matchesRange!.lowerBound, juuretOnlyRange!.lowerBound)
        XCTAssertLessThan(juuretOnlyRange!.lowerBound, hiskiOnlyRange!.lowerBound)
    }

    func testRenderJuuretHiskiReportPlacesItemsUnderExpectedSections() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Liisa",
                    birth: date(1797, 10, 12),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Elisabeta",
                    birth: date(1797, 10, 12),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("liisa-1797")
                ),
                candidate(
                    name: "Anders",
                    birth: date(1806, 11, 22),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("anders-1806")
                )
            ]
        )

        let report = service.renderJuuretHiskiReport(result)

        XCTAssertEqual(
            report,
            """
            Matches
            -------
            Liisa / Elisabeta — 12 Oct 1797

            Juuret only
            -----------
            Maija Liisa — 03 Aug 1806

            HisKi only
            ----------
            Anders — 22 Nov 1806
            """
        )
    }

    func testRenderJuuretHiskiReportKeepsItemOrderingByBirthDate() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Liisa",
                    birth: date(1797, 10, 12),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                ),
                candidate(
                    name: "Elisabeta",
                    birth: date(1797, 10, 12),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("liisa-1797")
                ),
                candidate(
                    name: "Anders",
                    birth: date(1806, 11, 22),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("anders-1806")
                )
            ]
        )

        let report = service.renderJuuretHiskiReport(result)

        let liisaIndex = report.range(of: "Liisa / Elisabeta — 12 Oct 1797")!.lowerBound
        let mattiIndex = report.range(of: "Matti — 25 Jun 1802")!.lowerBound
        let maijaIndex = report.range(of: "Maija Liisa — 03 Aug 1806")!.lowerBound
        let andersIndex = report.range(of: "Anders — 22 Nov 1806")!.lowerBound

        XCTAssertLessThan(liisaIndex, mattiIndex)
        XCTAssertLessThan(maijaIndex, andersIndex)
    }

    func testRenderJuuretHiskiReportRendersEmptyResultStructure() {
        let report = service.renderJuuretHiskiReport(
            service.compare(juuretCandidates: [], hiskiCandidates: [])
        )

        XCTAssertEqual(
            report,
            """
            Matches
            -------
            (none)

            Juuret only
            -----------
            (none)

            HisKi only
            ----------
            (none)
            """
        )
    }

    func testRenderJuuretHiskiReportRendersMatchedChildUnderMatchesWhenPresentInBothSources() throws {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                )
            ]
        )

        let match = try XCTUnwrap(result.matches.first)
        XCTAssertNotNil(match.juuretKalvialla)
        XCTAssertNotNil(match.hiski)
        XCTAssertTrue(result.juuretOnly.isEmpty)
        XCTAssertTrue(result.hiskiOnly.isEmpty)

        let report = service.renderJuuretHiskiReport(result)

        XCTAssertEqual(
            report,
            """
            Matches
            -------
            Matti — 25 Jun 1802

            Juuret only
            -----------
            (none)

            HisKi only
            ----------
            (none)
            """
        )
    }

    func testRenderJuuretHiskiReportRendersNoneUnderJuuretAndHiskiOnlyWhenAllChildrenMatch() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Liisa",
                    birth: date(1797, 10, 12),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Elisabeta",
                    birth: date(1797, 10, 12),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("liisa-1797")
                ),
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                )
            ]
        )

        XCTAssertTrue(result.juuretOnly.isEmpty)
        XCTAssertTrue(result.hiskiOnly.isEmpty)

        let report = service.renderJuuretHiskiReport(result)

        XCTAssertEqual(
            report,
            """
            Matches
            -------
            Liisa / Elisabeta — 12 Oct 1797
            Matti — 25 Jun 1802

            Juuret only
            -----------
            (none)

            HisKi only
            ----------
            (none)
            """
        )
    }

    func testMakeHiskiCitationProposalsCreatesProposalForExactNameMatch() throws {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                )
            ]
        )

        let proposals = service.makeHiskiCitationProposals(from: result)

        XCTAssertEqual(proposals.count, 1)

        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal.identity, PersonIdentity(
            name: "Matti",
            birthDate: date(1802, 6, 25),
            nameManager: nameManager
        ))
        XCTAssertEqual(proposal.displayName, "Matti")
        XCTAssertEqual(proposal.birthDate, date(1802, 6, 25))
        XCTAssertEqual(proposal.juuretName, "Matti")
        XCTAssertEqual(proposal.hiskiName, "Matti")
        XCTAssertEqual(proposal.citationURL, hiskiCitation("matti-1802"))
    }

    func testMakeHiskiCitationProposalsUsesCombinedDisplayNameForEquivalentNames() throws {
        nameManager.addEquivalence(between: "Maija", and: "Maria")
        nameManager.addEquivalence(between: "Liisa", and: "Elis.")

        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Maria Elis.",
                    birth: date(1806, 8, 3),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("maija-liisa-1806")
                )
            ]
        )

        let proposals = service.makeHiskiCitationProposals(from: result)

        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.displayName, "Maija Liisa / Maria Elis.")
        XCTAssertEqual(proposals.first?.juuretName, "Maija Liisa")
        XCTAssertEqual(proposals.first?.hiskiName, "Maria Elis.")
    }

    func testMakeHiskiCitationProposalsIncludesHiskiOnlyChildAndExcludesJuuretOnlyChild() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: nil
                ),
                candidate(
                    name: "Anders",
                    birth: date(1806, 11, 22),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("anders-1806")
                )
            ]
        )

        let proposals = service.makeHiskiCitationProposals(from: result)

        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals.first?.displayName, "Anders")
        XCTAssertNil(proposals.first?.juuretName)
        XCTAssertEqual(proposals.first?.hiskiName, "Anders")
        XCTAssertEqual(proposals.first?.citationURL, hiskiCitation("anders-1806"))
    }

    func testMakeHiskiCitationProposalsSkipsMissingCitationURL() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: nil
                )
            ]
        )

        let proposals = service.makeHiskiCitationProposals(from: result)

        XCTAssertTrue(proposals.isEmpty)
    }

    func testMakeHiskiCitationProposalsPreservesMatchOrdering() {
        let result = service.compare(
            juuretCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .juuretKalvialla
                ),
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .juuretKalvialla
                )
            ],
            hiskiCandidates: [
                candidate(
                    name: "Matti",
                    birth: date(1802, 6, 25),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("matti-1802")
                ),
                candidate(
                    name: "Anders",
                    birth: date(1804, 11, 22),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("anders-1804")
                ),
                candidate(
                    name: "Maija Liisa",
                    birth: date(1806, 8, 3),
                    source: .hiski,
                    hiskiCitation: hiskiCitation("maija-liisa-1806")
                )
            ]
        )

        let proposals = service.makeHiskiCitationProposals(from: result)

        XCTAssertEqual(
            proposals.map(\.displayName),
            ["Matti", "Anders", "Maija Liisa"]
        )
        XCTAssertEqual(
            proposals.map(\.birthDate),
            [date(1802, 6, 25), date(1804, 11, 22), date(1806, 8, 3)]
        )
    }

    func testMakeHiskiCitationProposalsReturnsEmptyForEmptyResult() {
        let proposals = service.makeHiskiCitationProposals(
            from: service.compare(juuretCandidates: [], hiskiCandidates: [])
        )

        XCTAssertTrue(proposals.isEmpty)
    }

    func testHiskiCitationProposalShortCitationStringRemovesScheme() {
        let proposal = HiskiCitationProposal(
            identity: PersonIdentity(
                name: "Matti",
                birthDate: date(1802, 6, 25),
                nameManager: nameManager
            ),
            displayName: "Matti / Matts",
            birthDate: date(1802, 6, 25),
            juuretName: "Matti",
            hiskiName: "Matts",
            citationURL: hiskiCitation("hiski?en+t4092193")
        )

        XCTAssertEqual(
            proposal.shortCitationString,
            "hiski.genealogia.fi/hiski?en+t4092193"
        )
    }

    func testRenderHiskiCitationProposalsIncludesDisplayNameAndShortCitationOnOneLine() {
        let proposals = [
            HiskiCitationProposal(
                identity: PersonIdentity(
                    name: "Matti",
                    birthDate: date(1802, 6, 25),
                    nameManager: nameManager
                ),
                displayName: "Matti / Matts",
                birthDate: date(1802, 6, 25),
                juuretName: "Matti",
                hiskiName: "Matts",
                citationURL: hiskiCitation("t4092193")
            )
        ]

        let report = service.renderHiskiCitationProposals(proposals)

        XCTAssertEqual(
            report,
            """
            HisKi Citation Proposals
            ------------------------
            Matti / Matts — hiski.genealogia.fi/t4092193
            """
        )
    }

    func testRenderHiskiCitationProposalsPreservesProposalOrdering() {
        let proposals = [
            HiskiCitationProposal(
                identity: PersonIdentity(
                    name: "Matti",
                    birthDate: date(1802, 6, 25),
                    nameManager: nameManager
                ),
                displayName: "Matti",
                birthDate: date(1802, 6, 25),
                juuretName: "Matti",
                hiskiName: "Matti",
                citationURL: hiskiCitation("matti-1802")
            ),
            HiskiCitationProposal(
                identity: PersonIdentity(
                    name: "Maija Liisa",
                    birthDate: date(1806, 8, 3),
                    nameManager: nameManager
                ),
                displayName: "Maija Liisa / Maria Elis.",
                birthDate: date(1806, 8, 3),
                juuretName: "Maija Liisa",
                hiskiName: "Maria Elis.",
                citationURL: hiskiCitation("maija-liisa-1806")
            )
        ]

        let report = service.renderHiskiCitationProposals(proposals)

        let mattiIndex = report.range(of: "Matti — hiski.genealogia.fi/matti-1802")!.lowerBound
        let maijaIndex = report.range(of: "Maija Liisa / Maria Elis. — hiski.genealogia.fi/maija-liisa-1806")!.lowerBound

        XCTAssertLessThan(mattiIndex, maijaIndex)
    }

    func testRenderHiskiCitationProposalsRendersEmptyState() {
        let report = service.renderHiskiCitationProposals([])

        XCTAssertEqual(
            report,
            """
            HisKi Citation Proposals
            ------------------------
            (none)
            """
        )
    }

    private func candidate(
        name: String,
        birth: Date,
        source: PersonCandidate.SourceType,
        hiskiCitation: URL? = nil
    ) -> PersonCandidate {
        PersonCandidate(
            name: name,
            birthDate: birth,
            source: source,
            nameManager: nameManager,
            familySearchId: nil,
            hiskiCitation: hiskiCitation
        )
    }

    private func hiskiCitation(_ slug: String) -> URL {
        guard let url = URL(string: "https://hiski.genealogia.fi/\(slug)") else {
            preconditionFailure("Invalid HisKi citation slug: \(slug)")
        }

        return url
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
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
