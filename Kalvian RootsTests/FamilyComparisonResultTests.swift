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

    func testCandidatesWithoutBirthDatesDoNotMatchByNameAlone() {
        let result = FamilyComparisonResult(
            familySearch: [
                PersonCandidate(
                    name: "Maria",
                    birthDate: nil,
                    source: .familySearch,
                    nameManager: nameManager,
                    familySearchId: "MARIA-FS-UNKNOWN"
                )
            ],
            juuretKalvialla: [
                PersonCandidate(
                    name: "Maria",
                    birthDate: nil,
                    source: .juuretKalvialla,
                    nameManager: nameManager
                )
            ],
            hiski: []
        )

        XCTAssertEqual(result.matches.count, 0)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.familySearchOnly.count, 1)
        XCTAssertEqual(result.juuretOnly.count, 1)
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
        let events: [HiskiService.HiskiFamilyBirthEvent] = []
        let candidates = service.makeHiskiCandidates(from: events)

        XCTAssertTrue(candidates.isEmpty)
    }

    func testMakeHiskiCandidatesFromRowsDoesNotRequireCitationUrl() throws {
        let row = HiskiService.HiskiFamilyBirthRow(
            birthDate: "25.6.1802",
            childName: "Matti",
            fatherName: "Elias Matinp.",
            motherName: "Maria Antint.",
            recordPath: "/hiski?en+4092193"
        )

        let candidates = service.makeHiskiCandidates(from: [row])

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.rawName, "Matti")
        XCTAssertEqual(candidate.source, .hiski)
        XCTAssertEqual(candidate.birthDate, date(1802, 6, 25))
        XCTAssertNil(candidate.hiskiCitation)
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

    func testMakeFamilySearchCandidatesRetainsIdAndDeathDate() throws {
        nameManager.addEquivalence(between: "Matti", and: "Matthias")

        let children = [
            FamilySearchChild(
                id: "K1AB-CDE",
                name: "Matthias Thomasson Ahokangas",
                birthDate: "25 June 1802",
                birthPlace: "Kalvia, Vaasa, Finland",
                deathDate: "14 March 1861",
                deathPlace: "Kalvia, Vaasa, Finland",
                lifeSpan: "1802-1861"
            )
        ]

        let candidates = service.makeFamilySearchCandidates(from: children)

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.rawName, "Matthias Thomasson Ahokangas")
        XCTAssertEqual(candidate.identity.canonicalName, "matti")
        XCTAssertEqual(candidate.source, .familySearch)
        XCTAssertEqual(candidate.familySearchId, "K1AB-CDE")
        XCTAssertEqual(candidate.birthDate, date(1802, 6, 25))
        XCTAssertEqual(candidate.deathDate, date(1861, 3, 14))
    }

    func testMakeFamilySearchCandidatesUsesStructuredVitalDateWhenLegacyDateIsBlank() throws {
        nameManager.addEquivalence(between: "Matti", and: "Matthias")

        let children = [
            FamilySearchChild(
                id: "LK4Q-YSX",
                name: "Matthias Thomasson Ahokangas",
                birthDate: " ",
                birthPlace: nil,
                deathDate: nil,
                deathPlace: nil,
                birth: FamilySearchVitalSummary(date: "14 March 1761", place: "Kälviä, Vaasa, Finland"),
                lifeSpan: "1761-1842"
            )
        ]

        let candidate = try XCTUnwrap(service.makeFamilySearchCandidates(from: children).first)

        XCTAssertEqual(candidate.rawName, "Matthias Thomasson Ahokangas")
        XCTAssertEqual(candidate.identity.canonicalName, "matti")
        XCTAssertEqual(candidate.birthDate, date(1761, 3, 14))
        XCTAssertEqual(candidate.familySearchId, "LK4Q-YSX")
    }

    func testCompareChildrenIncludesFamilySearchCandidates() throws {
        nameManager.addEquivalence(between: "Matti", and: "Matthias")

        let hiskiEvent = HiskiService.HiskiFamilyBirthEvent(
            birthDate: "25.6.1802",
            childName: "Matti",
            fatherName: "Elias Matinp.",
            motherName: "Maria Antint.",
            recordURL: "https://hiski.genealogia.fi/hiski?en+4092193",
            citationURL: "https://hiski.genealogia.fi/hiski?en+t4092193"
        )
        let familySearchChild = FamilySearchChild(
            id: "K1AB-CDE",
            name: "Matthias Thomasson Ahokangas",
            birthDate: "25 June 1802",
            birthPlace: nil,
            deathDate: nil,
            deathPlace: nil,
            lifeSpan: "1802-"
        )

        let result = service.compareChildren(
            juuretChildren: [
                Person(name: "Matti", birthDate: "25.6.1802", noteMarkers: [])
            ],
            hiskiChildren: [hiskiEvent],
            familySearchChildren: [familySearchChild]
        )

        XCTAssertEqual(result.matches.count, 1)
        let match = try XCTUnwrap(result.matches.first)
        XCTAssertEqual(match.juuretKalvialla?.rawName, "Matti")
        XCTAssertEqual(match.hiski?.rawName, "Matti")
        XCTAssertEqual(match.familySearch?.rawName, "Matthias Thomasson Ahokangas")
        XCTAssertEqual(match.familySearch?.familySearchId, "K1AB-CDE")
        XCTAssertEqual(service.status(for: match), "Present in all three")
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
            proposal.shortCitationString(from: proposal.citationURL),
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
}

final class FamilySearchDOMServiceTests: XCTestCase {

    func testAtlasExtractorIncludesCallbackAndCardLineParser() {
        let script = FamilySearchDOMService.makeAtlasExtractorScript(
            callbackURL: "http://127.0.0.1:8081/family/AHOKANGAS%202/familysearch?session=test"
        )

        XCTAssertTrue(script.contains("KALVIAN_ROOTS_CALLBACK_URL = 'http://127.0.0.1:8081/family/AHOKANGAS%202/familysearch?session=test'"))
        XCTAssertTrue(script.contains("await postResult(result);"))
        XCTAssertTrue(script.contains("window.extractFamilySearchChildren"))
        XCTAssertTrue(script.contains("function extractSpouseGroups()"))
        XCTAssertTrue(script.contains("function cleanPersonName(name)"))
        XCTAssertTrue(script.contains("function personEntryParseAt(lines, index)"))
        XCTAssertTrue(script.contains("index = parsed.nextIndex"))
        XCTAssertTrue(script.contains("function vitalLabelsFor(label)"))
        XCTAssertTrue(script.contains("function dateLikeFromText(text)"))
        XCTAssertTrue(script.contains("function vitalFromTextBlock(panel, label)"))
        XCTAssertTrue(script.contains("Birth|Born|Christening|Christened|Baptism|Baptized|Death|Died|Burial|Buried"))
        XCTAssertTrue(script.contains("const existingPanels = new Set(panelCandidatesFor(summary.id))"))
        XCTAssertTrue(script.contains("familySection.contains(element) && !isOverlayLike"))
        XCTAssertTrue(script.contains("Spouses and Children section not found"))
        XCTAssertTrue(script.contains("spouse groups not found"))
        XCTAssertTrue(script.contains("failureStatusForError"))
        XCTAssertFalse(script.contains("window.open"))
        XCTAssertFalse(script.contains("popupBlocked"))
        XCTAssertTrue(script.contains("notOnFamilySearch"))
        XCTAssertTrue(script.contains("familySearchDetailUnavailable"))
        XCTAssertTrue(script.contains("wrongHost"))
        XCTAssertTrue(script.contains("wrongPageType"))
        XCTAssertTrue(script.contains("not on FamilySearch person details page"))
        XCTAssertTrue(script.contains("kalvian-roots-familysearch-detail-frame"))
        XCTAssertTrue(script.contains("diagnosticContext"))
        XCTAssertTrue(script.contains("childrenMarkerCount"))
        XCTAssertTrue(script.contains("rawCandidateChildCount"))
        XCTAssertTrue(script.contains("callback POST failed"))
        XCTAssertTrue(script.contains("found zero children"))
        XCTAssertTrue(script.contains("Kalvian Roots FamilySearch extraction succeeded"))
        XCTAssertTrue(script.contains("Kalvian Roots received FamilySearch extraction"))
        XCTAssertTrue(script.contains("FamilySearch extraction finished, but Kalvian Roots did not receive it"))
        XCTAssertTrue(script.contains("preferred group children"))
        XCTAssertTrue(script.contains("\\b[A-Z0-9]{4}-[A-Z0-9]{3,}\\b"))
    }

    func testServerRenderedFamilyProvidesReusableFamilySearchBookmarklet() {
        let family = Family(
            familyId: "AHOKANGAS 2",
            pageReferences: ["1"],
            husband: Person(name: "Thomas", familySearchId: "KJJH-2QK"),
            wife: Person(name: "Magdalena"),
            marriageDate: "15.05.1760",
            children: []
        )

        let html = HTMLRenderer.renderFamily(
            family: family,
            network: nil,
            comparisonResult: nil,
            familySearchExtraction: nil,
            familySearchPersonId: "KJJH-2QK",
            familySearchCallbackURL: "http://127.0.0.1:8081/family/AHOKANGAS%202/familysearch?session=test",
            autoExtractFamilySearch: true
        )

        XCTAssertTrue(html.contains("familySearchAutoStatus"))
        XCTAssertTrue(html.contains("Use the same Kalvian Roots FamilySearch Extractor bookmarklet for every family"))
        XCTAssertTrue(html.contains("Open FamilySearch extractor page"))
        XCTAssertTrue(html.contains("Copy bookmarklet"))
        XCTAssertTrue(html.contains("href=\"https://www.familysearch.org/en/tree/person/details/KJJH-2QK\""))
        XCTAssertTrue(html.contains("familySearchBookmarkletStatus"))
        XCTAssertTrue(html.contains("Drag this reusable bookmarklet to your Atlas bookmarks bar"))
        XCTAssertTrue(html.contains("Kalvian Roots FamilySearch Extractor"))
        XCTAssertTrue(html.contains("FamilySearch extractor invocation status: waiting for user-opened FamilySearch page"))
        XCTAssertFalse(html.contains("window.addEventListener('load'"))
        XCTAssertFalse(html.contains("Run FamilySearch Extractor"))
        XCTAssertFalse(html.contains("run extractFamilySearchChildren"))
        XCTAssertFalse(html.contains("const personId = 'KJJH-2QK'"))
    }

    func testBookmarkletInjectsExtractorAndDetectsPersonIdFromURL() {
        let bookmarklet = FamilySearchDOMService.makeBookmarklet()

        XCTAssertTrue(bookmarklet.hasPrefix("javascript:"))
        XCTAssertTrue(bookmarklet.contains("extractFamilySearchChildren"))
        XCTAssertTrue(bookmarklet.contains("location.pathname.match"))
        XCTAssertTrue(bookmarklet.contains("familysearch"))
        XCTAssertTrue(bookmarklet.contains("extraction-result"))
        XCTAssertTrue(bookmarklet.contains("Open%20a%20FamilySearch%20person%20Details%20page"))
        XCTAssertTrue(bookmarklet.contains("Not%20on%20FamilySearch%20person%20details%20page"))
        XCTAssertFalse(bookmarklet.contains("KJJH-2QK"))
    }

    func testGenericBookmarkletPayloadDecodesRichChildVitals() throws {
        let json = """
        {
          "sourcePersonId": "KJJH-2QK",
          "parentFamilySearchId": "KJJH-2QK",
          "extractedAt": "2026-04-24T10:00:00Z",
          "sourceUrl": "https://www.familysearch.org/en/tree/person/details/KJJH-2QK",
          "children": [
            {
              "id": "LK4Q-YSX",
              "name": "Lisa Ahokangas",
              "sex": "Female",
              "summaryYears": "1761-1830",
              "birth": { "date": "4 May 1761", "place": "Kälviä, Finland" },
              "christening": { "date": "5 May 1761", "place": "Kälviä, Finland" },
              "death": { "date": "10 June 1830", "place": "Kälviä, Finland" },
              "burial": { "date": "15 June 1830", "place": "Kälviä, Finland" },
              "extractionStatus": "success",
              "extractionNotes": []
            }
          ],
          "status": "success"
        }
        """

        let extraction = try JSONDecoder().decode(
            FamilySearchFamilyExtraction.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(extraction.isSuccessful)
        XCTAssertEqual(extraction.parentFamilySearchId, "KJJH-2QK")
        XCTAssertEqual(extraction.sourceUrl, "https://www.familysearch.org/en/tree/person/details/KJJH-2QK")
        XCTAssertEqual(extraction.children.first?.sex, "Female")
        XCTAssertEqual(extraction.children.first?.birth?.date, "4 May 1761")
        XCTAssertEqual(extraction.children.first?.christening?.place, "Kälviä, Finland")
        XCTAssertEqual(extraction.children.first?.burial?.date, "15 June 1830")
        XCTAssertEqual(extraction.children.first?.extractionStatus, "success")
    }

    func testKJJH2QKExtractionPayloadCanRepresentPreferredAndSecondSpouseGroups() throws {
        let json = """
        {
          "sourcePersonId": "KJJH-2QK",
          "focusPerson": {
            "id": "KJJH-2QK",
            "name": "Thomas Johansson Ahokangas",
            "birthDate": "16 December 1738",
            "deathDate": "14 August 1808",
            "lifeSpan": "1738-1808"
          },
          "spouse": {
            "id": "KJJH-2ZN",
            "name": "Magdalena Klapuri",
            "birthDate": "1741",
            "deathDate": "1794",
            "lifeSpan": "1741-1794"
          },
          "marriage": {
            "date": "15 May 1760",
            "place": "Kälviä, Vaasa, Finland"
          },
          "children": [
            { "id": "LK4Q-YSX", "name": "Matthias Thomasson Ahokangas", "lifeSpan": "1761-1842" },
            { "id": "KJJH-2GP", "name": "Andreas Thomasson Klapuri", "lifeSpan": "1763-1763" },
            { "id": "KJJH-2G5", "name": "Joseph Thomasson Klapuri", "lifeSpan": "1764-1764" },
            { "id": "KJJH-2GJ", "name": "Maria Thomasdr Klapuri", "lifeSpan": "1765-1797" },
            { "id": "KJJH-2GK", "name": "Elisabeth Klapuri", "lifeSpan": "1768-1838" },
            { "id": "M83R-9V3", "name": "Britha Thomasdotter", "lifeSpan": "1769-1813" },
            { "id": "LXDW-P12", "name": "Johannes Klapuri", "lifeSpan": "1771-Deceased" },
            { "id": "KJJH-2GT", "name": "Anna Ahokangas", "lifeSpan": "1773-1773" },
            { "id": "KJJH-2GL", "name": "Ericus Thomasson Ahokangas", "lifeSpan": "1775-Deceased" },
            { "id": "KJJH-2GR", "name": "Henric Ahokangas", "lifeSpan": "1778-1778" },
            { "id": "KJJH-2GG", "name": "Antti Tuomaanpoika Lehtimäki", "lifeSpan": "1779-1837" },
            { "id": "KJJH-2PM", "name": "Thomas Thomasson Ahokangas", "lifeSpan": "1780-1780" },
            { "id": "L4HD-545", "name": "Elias Thomasson Ahokangas", "lifeSpan": "1782-1845" }
          ],
          "spouseGroups": [
            {
              "spouses": [
                { "id": "KJJH-2QK", "name": "Thomas Johansson Ahokangas", "lifeSpan": "1738-1808" },
                { "id": "KJJH-2ZN", "name": "Magdalena Klapuri", "lifeSpan": "1741-1794" }
              ],
              "marriage": { "date": "15 May 1760", "place": "Kälviä, Vaasa, Finland" },
              "declaredChildCount": 13,
              "children": [
                { "id": "LK4Q-YSX", "name": "Matthias Thomasson Ahokangas", "lifeSpan": "1761-1842" },
                { "id": "KJJH-2GP", "name": "Andreas Thomasson Klapuri", "lifeSpan": "1763-1763" },
                { "id": "KJJH-2G5", "name": "Joseph Thomasson Klapuri", "lifeSpan": "1764-1764" },
                { "id": "KJJH-2GJ", "name": "Maria Thomasdr Klapuri", "lifeSpan": "1765-1797" },
                { "id": "KJJH-2GK", "name": "Elisabeth Klapuri", "lifeSpan": "1768-1838" },
                { "id": "M83R-9V3", "name": "Britha Thomasdotter", "lifeSpan": "1769-1813" },
                { "id": "LXDW-P12", "name": "Johannes Klapuri", "lifeSpan": "1771-Deceased" },
                { "id": "KJJH-2GT", "name": "Anna Ahokangas", "lifeSpan": "1773-1773" },
                { "id": "KJJH-2GL", "name": "Ericus Thomasson Ahokangas", "lifeSpan": "1775-Deceased" },
                { "id": "KJJH-2GR", "name": "Henric Ahokangas", "lifeSpan": "1778-1778" },
                { "id": "KJJH-2GG", "name": "Antti Tuomaanpoika Lehtimäki", "lifeSpan": "1779-1837" },
                { "id": "KJJH-2PM", "name": "Thomas Thomasson Ahokangas", "lifeSpan": "1780-1780" },
                { "id": "L4HD-545", "name": "Elias Thomasson Ahokangas", "lifeSpan": "1782-1845" }
              ],
              "isPreferred": true
            },
            {
              "spouses": [
                { "id": "LHZY-M43", "name": "Catharina Carin Mattsdr Norppa", "lifeSpan": "1747-1830" }
              ],
              "marriage": null,
              "declaredChildCount": 0,
              "children": [],
              "isPreferred": false
            }
          ],
          "status": "success",
          "url": "https://www.familysearch.org/en/tree/person/details/KJJH-2QK",
          "pageTitle": "Thomas Johansson Ahokangas | Person | Family Tree",
          "detectedHost": "www.familysearch.org",
          "detectedPersonId": "KJJH-2QK",
          "expectedPersonId": "KJJH-2QK",
          "isFamilySearchPage": true,
          "isPersonDetailsPage": true,
          "familyMembersSectionFound": true,
          "spousesAndChildrenSectionFound": true,
          "childrenMarkerCount": 2,
          "rawCandidateChildCount": 13,
          "spouseGroupCount": 2,
          "childCount": 13,
          "preferredChildCount": 13,
          "debugNotes": ["FamilySearch extraction finished: spouse groups 2, preferred group children 13"]
        }
        """

        let extraction = try JSONDecoder().decode(
            FamilySearchFamilyExtraction.self,
            from: Data(json.utf8)
        )

        XCTAssertTrue(extraction.isSuccessful)
        XCTAssertEqual(extraction.children.count, 13)
        XCTAssertEqual(extraction.spouseGroups?.count, 2)
        XCTAssertEqual(extraction.spouseGroups?.first?.declaredChildCount, 13)
        XCTAssertEqual(extraction.spouseGroups?.last?.declaredChildCount, 0)
        XCTAssertEqual(extraction.spouseGroups?.last?.children.count, 0)
        XCTAssertEqual(extraction.childrenMarkerCount, 2)
        XCTAssertEqual(extraction.rawCandidateChildCount, 13)
        XCTAssertEqual(extraction.pageTitle, "Thomas Johansson Ahokangas | Person | Family Tree")
        XCTAssertEqual(extraction.detectedHost, "www.familysearch.org")
        XCTAssertEqual(extraction.children.first?.id, "LK4Q-YSX")
        XCTAssertEqual(extraction.children.last?.id, "L4HD-545")
    }

    func testFailedExtractionPayloadDistinguishesWrongPageTypeFromZeroChildren() throws {
        let json = """
        {
          "sourcePersonId": "KJJH-2QK",
          "children": [],
          "spouseGroups": [],
          "status": "wrongPageType",
          "failureReason": "wrong page type for FamilySearch extraction: https://www.familysearch.org/en/tree/person/sources/KJJH-2QK",
          "url": "https://www.familysearch.org/en/tree/person/sources/KJJH-2QK",
          "pageTitle": "Sources | FamilySearch",
          "detectedHost": "www.familysearch.org",
          "detectedPersonId": null,
          "expectedPersonId": "KJJH-2QK",
          "isFamilySearchPage": true,
          "isPersonDetailsPage": false,
          "familyMembersSectionFound": false,
          "spousesAndChildrenSectionFound": false,
          "childrenMarkerCount": 0,
          "rawCandidateChildCount": 0,
          "spouseGroupCount": 0,
          "childCount": 0,
          "preferredChildCount": 0
        }
        """

        let extraction = try JSONDecoder().decode(
            FamilySearchFamilyExtraction.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(extraction.isSuccessful)
        XCTAssertEqual(extraction.children.count, 0)
        XCTAssertEqual(extraction.status, "wrongPageType")
        XCTAssertEqual(extraction.pageTitle, "Sources | FamilySearch")
        XCTAssertEqual(extraction.detectedHost, "www.familysearch.org")
        XCTAssertEqual(extraction.isPersonDetailsPage, false)
        XCTAssertEqual(extraction.failureReason, "wrong page type for FamilySearch extraction: https://www.familysearch.org/en/tree/person/sources/KJJH-2QK")
    }

    func testFailedExtractionPayloadDistinguishesNotOnFamilySearchFromZeroChildren() throws {
        let json = """
        {
          "sourcePersonId": "KJJH-2QK",
          "children": [],
          "spouseGroups": [],
          "status": "notOnFamilySearch",
          "failureReason": "not on FamilySearch person details page: http://127.0.0.1:8081/family/AHOKANGAS%202",
          "url": "http://127.0.0.1:8081/family/AHOKANGAS%202",
          "pageTitle": "AHOKANGAS 2 - Kalvian Roots",
          "detectedHost": "127.0.0.1",
          "detectedPersonId": null,
          "expectedPersonId": "KJJH-2QK",
          "isFamilySearchPage": false,
          "isPersonDetailsPage": false,
          "familyMembersSectionFound": false,
          "spousesAndChildrenSectionFound": false,
          "childrenMarkerCount": 0,
          "rawCandidateChildCount": 0,
          "spouseGroupCount": 0,
          "childCount": 0,
          "preferredChildCount": 0
        }
        """

        let extraction = try JSONDecoder().decode(
            FamilySearchFamilyExtraction.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(extraction.isSuccessful)
        XCTAssertEqual(extraction.status, "notOnFamilySearch")
        XCTAssertEqual(extraction.detectedHost, "127.0.0.1")
        XCTAssertEqual(extraction.isFamilySearchPage, false)
        XCTAssertEqual(extraction.children.count, 0)
    }
}

final class FamilySearchComparisonClipboardFormatterTests: XCTestCase {

    func testClipboardTextIncludesDebugAndTabSeparatedRows() {
        let nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        nameManager.addEquivalence(between: "Matti", and: "Matthias")

        let result = FamilyComparisonResult(
            familySearch: [
                PersonCandidate(
                    name: "Matthias",
                    birthDate: date(1761, 3, 14),
                    source: .familySearch,
                    nameManager: nameManager,
                    familySearchId: "LK4Q-YSX"
                )
            ],
            juuretKalvialla: [
                PersonCandidate(
                    name: "Matti",
                    birthDate: date(1761, 3, 14),
                    source: .juuretKalvialla,
                    nameManager: nameManager
                )
            ],
            hiski: []
        )

        let text = FamilySearchComparisonClipboardFormatter.text(
            debugMessage: "FamilySearch comparison ready",
            debugLines: [
                "Family selected: AHOKANGAS 2",
                "FamilySearch extraction context URL: https://www.familysearch.org/en/tree/person/details/KJJH-2QK",
                "FamilySearch extraction status: success",
                "FamilySearch children handed to comparison: 1"
            ],
            rows: result.rows,
            status: { _ in "Missing in HisKi" }
        )

        XCTAssertTrue(text.contains("Family selected: AHOKANGAS 2"))
        XCTAssertTrue(text.contains("FamilySearch extraction context URL: https://www.familysearch.org/en/tree/person/details/KJJH-2QK"))
        XCTAssertTrue(text.contains("FamilySearch children handed to comparison: 1"))
        XCTAssertTrue(text.contains("Child name\tJuuret\tHisKi\tFamilySearch\tStatus"))
        XCTAssertTrue(text.contains("Matti\tYes | 14 Mar 1761\tNo\tYes | <LK4Q-YSX> | 14 Mar 1761\tMissing in HisKi"))
    }
}

final class TikkanenSixDevelopmentDataTests: XCTestCase {

    private let equivalencesKey = "NameEquivalences"
    private let equivalenceVersionKey = "NameEquivalencesVersion"
    private var savedEquivalencesData: Data?
    private var savedVersionValue: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()

        let defaults = UserDefaults.standard
        savedEquivalencesData = defaults.data(forKey: equivalencesKey)
        savedVersionValue = defaults.object(forKey: equivalenceVersionKey)
        defaults.removeObject(forKey: equivalencesKey)
        defaults.removeObject(forKey: equivalenceVersionKey)
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

        try super.tearDownWithError()
    }

    func testTikkanenSixDevelopmentGroupsAreBuiltPerCouple() throws {
        let groups = TikkanenSixDevelopmentData.makeComparisonGroups(
            for: makeTikkanenSixFamily(),
            nameManager: NameEquivalenceManager()
        )

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map { $0.result.rows.count }, [2, 5, 18])
        XCTAssertEqual(groups.map { $0.hiskiSearchRequests.count }, [1, 1, 1])

        XCTAssertEqual(queryValue("alkuvuosi", in: groups[0].hiskiSearchRequests[0].url), "1737")
        XCTAssertEqual(queryValue("loppuvuosi", in: groups[0].hiskiSearchRequests[0].url), "1774")
        XCTAssertEqual(queryValue("alkuvuosi", in: groups[1].hiskiSearchRequests[0].url), "1745")
        XCTAssertEqual(queryValue("loppuvuosi", in: groups[1].hiskiSearchRequests[0].url), "1782")
        XCTAssertEqual(queryValue("alkuvuosi", in: groups[2].hiskiSearchRequests[0].url), "1752")
        XCTAssertEqual(queryValue("loppuvuosi", in: groups[2].hiskiSearchRequests[0].url), "1789")
    }

    func testTikkanenSixDevelopmentDisplayFavorsJuuretNames() throws {
        let family = makeTikkanenSixFamily()
        let mariaGroup = try XCTUnwrap(
            TikkanenSixDevelopmentData.makeComparisonGroups(
                for: family,
                nameManager: NameEquivalenceManager(),
                hiskiRowsByCouple: [
                    2: makeMariaHiskiRows(couple: family.couples[2])
                ]
            ).last
        )

        let mikkoRow = try XCTUnwrap(mariaGroup.result.rows.first {
            $0.juuretKalvialla?.rawName == "Mikko"
        })
        XCTAssertEqual(mikkoRow.familySearch?.rawName, "Michel Tikkanen")
        XCTAssertEqual(mikkoRow.hiski?.rawName, "Michel")

        let abrahamRow = try XCTUnwrap(mariaGroup.result.rows.first {
            $0.juuretKalvialla?.rawName == "Abraham"
        })
        XCTAssertEqual(abrahamRow.familySearch?.rawName, "Abram Eriksson")
        XCTAssertEqual(abrahamRow.hiski?.rawName, "Abram")
    }

    private func makeMariaHiskiRows(couple: Couple) -> [HiskiService.HiskiFamilyBirthRow] {
        [
            hiskiRow("05.03.1757", "Michel", couple),
            hiskiRow("25.11.1774", "Abram", couple)
        ]
    }

    private func hiskiRow(
        _ birthDate: String,
        _ childName: String,
        _ couple: Couple
    ) -> HiskiService.HiskiFamilyBirthRow {
        HiskiService.HiskiFamilyBirthRow(
            birthDate: birthDate,
            childName: childName,
            fatherName: couple.husband.displayName,
            motherName: couple.wife.displayName,
            recordPath: "/hiski?en+test"
        )
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func makeTikkanenSixFamily() -> Family {
        let husband = Person(
            name: "Erik",
            patronymic: "Juhonp.",
            birthDate: "1716",
            deathDate: "27.02.1797",
            familySearchId: "K2YQ-1ZY"
        )

        return Family(
            familyId: "TIKKANEN 6",
            pageReferences: ["240", "241"],
            couples: [
                Couple(
                    husband: husband,
                    wife: Person(
                        name: "Annika",
                        patronymic: "Matint.",
                        birthDate: "1721",
                        deathDate: "20.01.1740",
                        familySearchId: "K2YQ-18B"
                    ),
                    fullMarriageDate: "29.10.1738"
                ),
                Couple(
                    husband: husband,
                    wife: Person(
                        name: "Anna",
                        patronymic: "Pietarint.",
                        birthDate: "1721",
                        deathDate: "06.02.1753",
                        familySearchId: "GMQH-8GF"
                    ),
                    fullMarriageDate: "24.06.1746",
                    children: [
                        Person(name: "Brita", birthDate: "20.05.1750", familySearchId: "M8ZP-9VD"),
                        Person(name: "Johannes", birthDate: "27.11.1751", familySearchId: "M88M-KZZ"),
                        Person(name: "Erik", birthDate: "06.02.1753", deathDate: "03.06.1785", familySearchId: "M8ZL-2C1")
                    ]
                ),
                Couple(
                    husband: husband,
                    wife: Person(
                        name: "Maria",
                        patronymic: "Martint.",
                        birthDate: "02.06.1735",
                        familySearchId: "K8CD-718"
                    ),
                    fullMarriageDate: "27.11.1753",
                    children: [
                        Person(name: "Matti", birthDate: "14.03.1756", familySearchId: "LHH6-W2P"),
                        Person(name: "Mikko", birthDate: "05.03.1757", familySearchId: "M8ZB-PGR"),
                        Person(name: "Kustaa", birthDate: "13.09.1759", familySearchId: "K2TZ-DY4"),
                        Person(name: "Elias", birthDate: "14.12.1760", familySearchId: "KHM5-VHL"),
                        Person(name: "Brita", birthDate: "04.12.1763", familySearchId: "M8Z5-CXJ"),
                        Person(name: "Antti", birthDate: "07.03.1765", familySearchId: "M887-WG3"),
                        Person(name: "Liisa", birthDate: "28.11.1767", familySearchId: "M88H-SZ7"),
                        Person(name: "Jaakko", birthDate: "24.03.1769", familySearchId: "M88Z-4SX"),
                        Person(name: "Maria", birthDate: "31.05.1770", familySearchId: "M8ZK-MCM"),
                        Person(name: "Kaarin", birthDate: "16.06.1773", familySearchId: "KZXH-GLC"),
                        Person(name: "Abraham", birthDate: "25.11.1774", familySearchId: "M887-1Q4")
                    ]
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )
    }
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
