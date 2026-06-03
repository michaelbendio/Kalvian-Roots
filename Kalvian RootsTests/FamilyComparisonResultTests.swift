import Foundation
import XCTest
@testable import Kalvian_Roots
#if os(macOS)
import NIOHTTP1
#endif

final class FamilyComparisonResultTests: XCTestCase {

    private let equivalencesKey = "UserNameEquivalences"

    private var nameManager: NameEquivalenceManager!
    private var savedEquivalencesData: Data?

    override func setUpWithError() throws {
        try super.setUpWithError()
        nameEquivalenceUserDefaultsLock.lock()

        let defaults = UserDefaults.standard
        savedEquivalencesData = defaults.data(forKey: equivalencesKey)

        defaults.removeObject(forKey: equivalencesKey)

        nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        nameManager.addEquivalence(between: "Liisa", and: "Elisabeta")
    }

    override func tearDownWithError() throws {
        defer {
            nameEquivalenceUserDefaultsLock.unlock()
        }

        let defaults = UserDefaults.standard

        if let savedEquivalencesData {
            defaults.set(savedEquivalencesData, forKey: equivalencesKey)
        } else {
            defaults.removeObject(forKey: equivalencesKey)
        }

        nameManager = nil
        savedEquivalencesData = nil

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
        XCTAssertEqual(
            FamilyComparisonService(nameManager: nameManager).status(for: match),
            "Present in all three"
        )
    }

    func testEquivalentSourceSpellingsDoNotReportNameMismatchStatus() throws {
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Anna Eriksson",
                    identityName: "Anna",
                    birth: date(1748, 5, 5),
                    source: .familySearch,
                    familySearchId: "ANNA-FS-1748"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Anna",
                    birth: date(1748, 5, 5),
                    source: .juuretKalvialla
                )
            ],
            hiski: [
                candidate(
                    name: "Anna",
                    birth: date(1748, 5, 5),
                    source: .hiski
                )
            ]
        )

        let match = try XCTUnwrap(result.matches.first)
        XCTAssertEqual(
            FamilyComparisonService(nameManager: nameManager).status(for: match),
            "Present in all three"
        )
    }

    func testFamilySearchUppercaseMonthDatesBecomeCandidateBirthDates() throws {
        let service = FamilyComparisonService(nameManager: nameManager)
        let candidates = service.makeFamilySearchCandidates(from: [
            FamilySearchChild(
                id: "M88Z-4SX",
                name: "Jacob Eriksson",
                birthDate: "24 MAR 1769"
            )
        ])

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.birthDate, date(1769, 3, 24))
    }

    func testFamilySearchSwedishMonthDatesBecomeCandidateBirthDates() throws {
        let service = FamilyComparisonService(nameManager: nameManager)
        let candidates = service.makeFamilySearchCandidates(from: [
            FamilySearchChild(
                id: "K2TT-JB4",
                name: "Helena Thomasdotter Riihimäki",
                birthDate: "18 maj 1777"
            ),
            FamilySearchChild(
                id: "LHGT-RNG",
                name: "Maria Karin Tomasdotter Riihimäki",
                birthDate: "28 februari 1759"
            ),
            FamilySearchChild(
                id: "M88M-B8N",
                name: "Johannes Thomasson Riihimäki",
                birthDate: "6 mars 1775"
            )
        ])

        XCTAssertEqual(candidates.map(\.birthDate), [
            date(1777, 5, 18),
            date(1759, 2, 28),
            date(1775, 3, 6)
        ])
    }

    func testFamilySearchFinnishMonthDatesBecomeCandidateBirthDates() throws {
        let service = FamilyComparisonService(nameManager: nameManager)
        let candidates = service.makeFamilySearchCandidates(from: [
            FamilySearchChild(
                id: "K2TT-JB4",
                name: "Helena Tuomaantytär Riihimäki",
                birthDate: "18 toukokuuta 1777"
            ),
            FamilySearchChild(
                id: "LHGT-RNG",
                name: "Maria Kaarin Tuomaantytär Riihimäki",
                birthDate: "28 helmikuuta 1759"
            ),
            FamilySearchChild(
                id: "M88M-B8N",
                name: "Juho Tuomaanpoika Riihimäki",
                birthDate: "6 maaliskuuta 1775"
            )
        ])

        XCTAssertEqual(candidates.map(\.birthDate), [
            date(1777, 5, 18),
            date(1759, 2, 28),
            date(1775, 3, 6)
        ])
    }

    func testFamilySearchDottedLocalizedMonthDatesBecomeCandidateBirthDates() throws {
        let service = FamilyComparisonService(nameManager: nameManager)
        let candidates = service.makeFamilySearchCandidates(from: [
            FamilySearchChild(
                id: "GZN2-8NQ",
                name: "Helena Andersdr.",
                birthDate: "20. elokuuta 1767"
            ),
            FamilySearchChild(
                id: "LHGT-RNG",
                name: "Maria Karin Tomasdotter Riihimäki",
                birthDate: "28. februari 1759"
            ),
            FamilySearchChild(
                id: "M88M-B8N",
                name: "Johannes Thomasson Riihimäki",
                birthDate: "6. mars 1775"
            )
        ])

        XCTAssertEqual(candidates.map(\.birthDate), [
            date(1767, 8, 20),
            date(1759, 2, 28),
            date(1775, 3, 6)
        ])
    }

    func testDottedFinnishFullDateDoesNotFallBackToMonthYear() throws {
        let service = FamilyComparisonService(nameManager: nameManager)
        let candidates = service.makeFamilySearchCandidates(from: [
            FamilySearchChild(
                id: "GZN2-8NQ",
                name: "Helena Andersdr.",
                birthDate: "20. elokuuta 1767"
            )
        ])

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.birthDate, date(1767, 8, 20))
        XCTAssertNotEqual(candidate.birthDate, date(1767, 8, 1))
    }

    func testMonthYearAndYearOnlyDatesStillParseWhenDayIsAbsent() throws {
        let service = FamilyComparisonService(nameManager: nameManager)
        let candidates = service.makeFamilySearchCandidates(from: [
            FamilySearchChild(
                id: "MONTH-YEAR",
                name: "Helena Andersdr.",
                birthDate: "elokuuta 1767"
            ),
            FamilySearchChild(
                id: "YEAR-ONLY",
                name: "Maria",
                birthDate: "1767"
            )
        ])

        XCTAssertEqual(candidates.map(\.birthDate), [
            date(1767, 8, 1),
            date(1767, 1, 1)
        ])
    }

    func testSameBirthDateWithMatchingNameTokenIsComparisonMatch() throws {
        let birthDate = date(1751, 11, 27)
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Johannes Eriksson",
                    identityName: "Johannes",
                    birth: birthDate,
                    source: .familySearch,
                    familySearchId: "FS-JOHANNES"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Johannes",
                    birth: birthDate,
                    source: .juuretKalvialla
                )
            ],
            hiski: [
                candidate(
                    name: "Johanna",
                    birth: birthDate,
                    source: .hiski
                )
            ]
        )

        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertTrue(FamilyComparisonReviewDetector.notes(for: result.rows).isEmpty)

        let displayRows = FamilyComparisonReviewDetector.displayRows(for: result.rows)
        XCTAssertEqual(displayRows.count, 1)

        let displayRow = try XCTUnwrap(displayRows.first)
        XCTAssertNil(displayRow.reviewNote)
        XCTAssertEqual(displayRow.match.juuretKalvialla?.rawName, "Johannes")
        XCTAssertEqual(displayRow.match.hiski?.rawName, "Johanna")
        XCTAssertEqual(displayRow.match.familySearch?.rawName, "Johannes Eriksson")
    }

    func testSameBirthDateWithSurnameOnlyDifferenceIsComparisonMatch() throws {
        let birthDate = date(1767, 8, 20)
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Helena Andersdr.",
                    birth: birthDate,
                    source: .familySearch,
                    familySearchId: "GZN2-8NQ"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Helena",
                    birth: birthDate,
                    source: .juuretKalvialla
                )
            ],
            hiski: [
                candidate(
                    name: "Helena",
                    birth: birthDate,
                    source: .hiski
                )
            ]
        )

        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.matches.count, 1)

        let row = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(row.juuretKalvialla?.rawName, "Helena")
        XCTAssertEqual(row.familySearch?.rawName, "Helena Andersdr.")
        XCTAssertEqual(row.hiski?.rawName, "Helena")
        XCTAssertTrue(FamilyComparisonReviewDetector.notes(for: result.rows).isEmpty)
    }

    func testMatchingNameOnDifferentBirthDatesStaysAmbiguousAndSeparate() {
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Helena Andersdr.",
                    birth: date(1767, 8, 20),
                    source: .familySearch,
                    familySearchId: "GZN2-8NQ"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Helena",
                    birth: date(1767, 8, 21),
                    source: .juuretKalvialla
                )
            ],
            hiski: []
        )

        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.matches.count, 0)
        XCTAssertEqual(result.familySearchOnly.count, 1)
        XCTAssertEqual(result.juuretOnly.count, 1)
    }

    func testSameBirthDateDoesNotMatchOnlyOnSharedPatronymic() {
        let birthDate = date(1767, 8, 20)
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Helena Andersdr.",
                    birth: birthDate,
                    source: .familySearch,
                    familySearchId: "FS-HELENA"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Anna Andersdr.",
                    birth: birthDate,
                    source: .juuretKalvialla
                )
            ],
            hiski: []
        )

        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.matches.count, 0)
        XCTAssertEqual(result.familySearchOnly.count, 1)
        XCTAssertEqual(result.juuretOnly.count, 1)
    }

    func testComparisonGroupDisplayRowsUsesSameBirthDateNameMatch() throws {
        let birthDate = date(1751, 11, 27)
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Johannes Eriksson",
                    identityName: "Johannes",
                    birth: birthDate,
                    source: .familySearch,
                    familySearchId: "FS-JOHANNES"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Johannes",
                    birth: birthDate,
                    source: .juuretKalvialla
                )
            ],
            hiski: [
                candidate(
                    name: "Johanna",
                    birth: birthDate,
                    source: .hiski
                )
            ]
        )
        let group = FamilyChildrenComparisonGroup(
            coupleIndex: 1,
            couple: Couple(husband: Person(name: "Erik"), wife: Person(name: "Anna")),
            hiskiSearchRequests: [],
            result: result
        )

        XCTAssertEqual(group.result.rows.count, 1)
        XCTAssertEqual(group.displayRows.count, 1)
        let displayRow = try XCTUnwrap(group.displayRows.first)
        XCTAssertEqual(displayRow.match.juuretKalvialla?.rawName, "Johannes")
        XCTAssertEqual(displayRow.match.hiski?.rawName, "Johanna")
        XCTAssertEqual(displayRow.match.familySearch?.rawName, "Johannes Eriksson")
        XCTAssertNil(displayRow.reviewNote)
    }

    func testReviewNotesDoNotFlagUnrelatedNamesWithExactSharedBirthDate() {
        let birthDate = date(1755, 2, 9)
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Elias Tikkanen",
                    identityName: "Elias",
                    birth: birthDate,
                    source: .familySearch,
                    familySearchId: "FS-ELIAS"
                )
            ],
            juuretKalvialla: [],
            hiski: [
                candidate(
                    name: "Matthias",
                    birth: birthDate,
                    source: .hiski
                )
            ]
        )

        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(FamilyComparisonReviewDetector.notes(for: result.rows).isEmpty)
        XCTAssertEqual(FamilyComparisonReviewDetector.displayRows(for: result.rows).count, 2)
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

    func testUndatedFamilySearchOnlyRowReportsDateNeededStatus() throws {
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
            juuretKalvialla: [],
            hiski: []
        )

        let row = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(
            FamilyComparisonService(nameManager: nameManager).status(for: row),
            "FamilySearch date needed"
        )
    }

    func testSakeriOneVariantNamesMatchAcrossSources() throws {
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Gustawus Mattsson",
                    identityName: "Gustawus",
                    birth: date(1701, 2, 23),
                    source: .familySearch,
                    familySearchId: "M883-J3T"
                ),
                candidate(
                    name: "Liisa Mattsson",
                    identityName: "Liisa",
                    birth: date(1704, 7, 6),
                    source: .familySearch,
                    familySearchId: "M88H-ZT9"
                ),
                candidate(
                    name: "Thomas Mattsson",
                    identityName: "Thomas",
                    birth: date(1708, 12, 5),
                    source: .familySearch,
                    familySearchId: "M8ZY-5TC"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Katariina",
                    birth: date(1697, 2, 18),
                    source: .juuretKalvialla
                )
            ],
            hiski: [
                candidate(
                    name: "Catharina",
                    birth: date(1697, 2, 18),
                    source: .hiski
                ),
                candidate(
                    name: "Gustawus",
                    birth: date(1701, 2, 23),
                    source: .hiski
                ),
                candidate(
                    name: "Lijsa",
                    birth: date(1704, 7, 6),
                    source: .hiski
                ),
                candidate(
                    name: "Thomas",
                    birth: date(1708, 12, 5),
                    source: .hiski
                )
            ]
        )

        XCTAssertEqual(result.matches.count, 4)

        let katariina = try XCTUnwrap(result.matches.first { $0.juuretKalvialla?.rawName == "Katariina" })
        XCTAssertEqual(katariina.hiski?.rawName, "Catharina")

        let gustawus = try XCTUnwrap(result.matches.first { $0.familySearch?.rawName == "Gustawus Mattsson" })
        XCTAssertEqual(gustawus.hiski?.rawName, "Gustawus")

        let liisa = try XCTUnwrap(result.matches.first { $0.familySearch?.rawName == "Liisa Mattsson" })
        XCTAssertEqual(liisa.hiski?.rawName, "Lijsa")

        let thomas = try XCTUnwrap(result.matches.first { $0.familySearch?.rawName == "Thomas Mattsson" })
        XCTAssertEqual(thomas.hiski?.rawName, "Thomas")
    }

    func testDisplayRowsCoalesceSameCanonicalNameWithNearbyBirthDateDiscrepancy() throws {
        let result = FamilyComparisonResult(
            familySearch: [
                candidate(
                    name: "Malin",
                    birth: date(1707, 5, 26),
                    source: .familySearch,
                    familySearchId: "M8ZN-MBH"
                )
            ],
            juuretKalvialla: [
                candidate(
                    name: "Malin",
                    birth: date(1707, 7, 26),
                    source: .juuretKalvialla
                )
            ],
            hiski: [
                candidate(
                    name: "Malin",
                    birth: date(1707, 5, 26),
                    source: .hiski
                )
            ]
        )

        XCTAssertEqual(result.rows.count, 2)

        let displayRows = FamilyComparisonReviewDetector.displayRows(for: result.rows)
        XCTAssertEqual(displayRows.count, 1)

        let displayRow = try XCTUnwrap(displayRows.first)
        XCTAssertEqual(displayRow.match.juuretKalvialla?.rawName, "Malin")
        XCTAssertEqual(displayRow.match.familySearch?.rawName, "Malin")
        XCTAssertEqual(displayRow.match.hiski?.rawName, "Malin")
        XCTAssertEqual(
            displayRow.reviewNote?.message,
            "Possible same child with date discrepancy: Juuret has Malin (26 Jul 1707); FamilySearch has Malin (26 May 1707); HisKi has Malin (26 May 1707)."
        )
    }

    private func candidate(
        name: String,
        identityName: String? = nil,
        birth: Date,
        source: PersonCandidate.SourceType,
        familySearchId: String? = nil,
        hiskiCitation: URL? = nil
    ) -> PersonCandidate {
        PersonCandidate(
            name: name,
            identityName: identityName,
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

    private let equivalencesKey = "UserNameEquivalences"

    private var service: FamilyComparisonService!
    private var nameManager: NameEquivalenceManager!
    private var savedEquivalencesData: Data?

    override func setUpWithError() throws {
        try super.setUpWithError()
        nameEquivalenceUserDefaultsLock.lock()

        let defaults = UserDefaults.standard
        savedEquivalencesData = defaults.data(forKey: equivalencesKey)

        defaults.removeObject(forKey: equivalencesKey)

        nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        nameManager.addEquivalence(between: "Liisa", and: "Elisabeta")
        service = FamilyComparisonService(nameManager: nameManager)
    }

    override func tearDownWithError() throws {
        defer {
            nameEquivalenceUserDefaultsLock.unlock()
        }

        let defaults = UserDefaults.standard

        if let savedEquivalencesData {
            defaults.set(savedEquivalencesData, forKey: equivalencesKey)
        } else {
            defaults.removeObject(forKey: equivalencesKey)
        }

        service = nil
        nameManager = nil
        savedEquivalencesData = nil
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

    func testMakeFamilySearchCandidatesUsesHiskiFullBirthDateForYearOnlyMatch() throws {
        let candidates = service.makeFamilySearchCandidates(
            from: [
                FamilySearchChild(
                    id: "M8ZY-5TC",
                    name: "Thomas Mattsson",
                    birthDate: "1708"
                )
            ],
            matchingHiskiRows: [
                HiskiService.HiskiFamilyBirthRow(
                    birthDate: "5.12.1708",
                    childName: "Thomas",
                    fatherName: "Matt Johansson",
                    motherName: "Carin Gustafsdr.",
                    recordPath: "/hiski?en+0265+kastetut+1708"
                )
            ]
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.rawName, "Thomas Mattsson")
        XCTAssertEqual(candidate.birthDate, date(1708, 12, 5))
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

    func testMakeJuuretCandidatesPreservesFamilySearchIds() throws {
        let candidates = service.makeJuuretCandidates(from: [
            Person(name: "Maria", birthDate: "12.02.1696", familySearchId: "PD55-86C")
        ])

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.rawName, "Maria")
        XCTAssertEqual(candidate.familySearchId, "PD55-86C")
    }

    func testHelenaDateFormatsAcrossSourcesCollapseIntoOneComparisonRow() throws {
        let familySearchCandidates = service.makeFamilySearchCandidates(from: [
            FamilySearchChild(
                id: "GZN2-8NQ",
                name: "Helena Andersdr.",
                birthDate: "20. elokuuta 1767"
            )
        ])
        let juuretCandidates = service.makeJuuretCandidates(from: [
            Person(name: "Helena", birthDate: "20.08.1767", noteMarkers: [])
        ])
        let hiskiCandidates = service.makeHiskiCandidates(from: [
            HiskiService.HiskiFamilyBirthRow(
                birthDate: "20.8.1767",
                childName: "Helena",
                fatherName: "Anders",
                motherName: "Maria",
                recordPath: "/hiski?en+0265+kastetut+1767"
            )
        ])

        XCTAssertEqual(familySearchCandidates.first?.birthDate, date(1767, 8, 20))
        XCTAssertEqual(juuretCandidates.first?.birthDate, date(1767, 8, 20))
        XCTAssertEqual(hiskiCandidates.first?.birthDate, date(1767, 8, 20))

        let result = service.compare(
            juuretCandidates: juuretCandidates,
            hiskiCandidates: hiskiCandidates,
            familySearchCandidates: familySearchCandidates
        )

        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertTrue(FamilyComparisonReviewDetector.displayRows(for: result.rows).allSatisfy { $0.reviewNote == nil })

        let row = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(row.juuretKalvialla?.rawName, "Helena")
        XCTAssertEqual(row.hiski?.rawName, "Helena")
        XCTAssertEqual(row.familySearch?.rawName, "Helena Andersdr.")
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

#if os(macOS)
@MainActor
final class BrowserSessionManagerTests: XCTestCase {

    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        try super.tearDownWithError()
    }

    func testLoadedSessionCanBeMatchedByFamilySearchParentIdWithoutCookie() async throws {
        let cache = makeTestCache()
        let family = Family(
            familyId: "KYKYRI II 8",
            pageReferences: ["264"],
            husband: Person(name: "Elias", familySearchId: "K1K9-QMK"),
            wife: Person(name: "Maria", familySearchId: "LHH6-WMZ"),
            marriageDate: "27.05.1800",
            children: [
                Person(name: "Elias", birthDate: "01.11.1815")
            ]
        )
        cache.storeNetwork(FamilyNetwork(mainFamily: family))

        let fileManager = RootsFileManager()
        let aiParsingService = AIParsingService()
        let nameEquivalenceManager = NameEquivalenceManager()
        let familyResolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager,
            fileManager: fileManager,
            familyNetworkCache: cache
        )
        let manager = BrowserSessionManager(
            cache: cache,
            fileManager: fileManager,
            aiParsingService: aiParsingService,
            familyResolver: familyResolver,
            nameEquivalenceManager: nameEquivalenceManager
        )

        let sessionResult = manager.session(for: HTTPHeaders())
        _ = try await sessionResult.session.loadFamily(familyId: "KYKYRI II 8")

        let match = manager.loadedSession(matchingFamilySearchParentId: "k1k9-qmk")
        XCTAssertEqual(match?.familyId, "KYKYRI II 8")
        XCTAssertTrue(match?.session === sessionResult.session)
    }

    func testCachedFamilyCanBeMatchedByPrimaryFamilySearchParentId() {
        let cache = makeTestCache()
        let family = Family(
            familyId: "KYKYRI II 18",
            pageReferences: ["266"],
            husband: Person(name: "Johan", familySearchId: "M8ZJ-HR6"),
            wife: Person(name: "Brita", familySearchId: "G19D-7W7"),
            marriageDate: "01.01.1804",
            children: [
                Person(name: "Matti", birthDate: "07.07.1805")
            ]
        )
        cache.storeNetwork(FamilyNetwork(mainFamily: family))

        XCTAssertEqual(cache.uniqueFamilyId(matchingFamilySearchParentId: "m8zj-hr6"), "KYKYRI II 18")
        XCTAssertNil(cache.uniqueFamilyId(matchingFamilySearchParentId: "G19D-7W7"))
    }

    func testGenericFamilySearchExtractionAssociationDoesNotScanSourceTextAfterAppMatch() {
        var matchedSessionEvaluated = false
        var cachedFamilyEvaluated = false
        var sourceTextEvaluated = false

        let familyId = BrowserSessionManager.resolveGenericFamilySearchExtractionFamilyId(
            appFamilyId: "KYKYRI II 9",
            matchedSessionFamilyId: {
                matchedSessionEvaluated = true
                return "KYKYRI II 8"
            },
            cachedFamilyId: {
                cachedFamilyEvaluated = true
                return "KYKYRI II 7"
            },
            sourceTextFamilyId: {
                sourceTextEvaluated = true
                return "KYKYRI II 6"
            }
        )

        XCTAssertEqual(familyId, "KYKYRI II 9")
        XCTAssertFalse(matchedSessionEvaluated)
        XCTAssertFalse(cachedFamilyEvaluated)
        XCTAssertFalse(sourceTextEvaluated)
    }

    private func makeTestCache() -> FamilyNetworkCache {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KalvianRootsTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(temporaryDirectory)
        let cacheFileURL = temporaryDirectory.appendingPathComponent("families.json")
        let store = PersistentFamilyNetworkStore(cacheFileURL: cacheFileURL)
        return FamilyNetworkCache(persistenceStore: store)
    }
}
#endif

final class FamilySearchDOMServiceTests: XCTestCase {

    func testFamilySearchExtractorIncludesCardLineParserWithoutBookmarkletCallback() {
        let script = FamilySearchDOMService.makeFamilySearchExtractorScript()

        XCTAssertTrue(script.contains("window.extractFamilySearchChildren"))
        XCTAssertFalse(script.contains("KALVIAN_ROOTS_CALLBACK_URL"))
        XCTAssertFalse(script.contains("fetch("))
        XCTAssertFalse(script.contains("callback POST failed"))
        XCTAssertFalse(script.contains("function updateExtractionProgress(message)"))
        XCTAssertFalse(script.contains("function clearExtractionProgress()"))
        XCTAssertFalse(script.contains("Kalvian Roots is extracting FamilySearch child"))
        XCTAssertTrue(script.contains("function extractSpouseGroups()"))
        XCTAssertTrue(script.contains("function cleanPersonName(name)"))
        XCTAssertTrue(script.contains("function personEntryParseAt(lines, index)"))
        XCTAssertTrue(script.contains("index = parsed.nextIndex"))
        XCTAssertTrue(script.contains("function vitalLabelsFor(label)"))
        XCTAssertTrue(script.contains("function dateLikeFromText(text)"))
        XCTAssertTrue(script.contains("\\\\b\\\\d{1,2}\\\\.?\\\\s+[A-Za-zÅÄÖåäö.]+\\\\s+\\\\d{3,4}\\\\b"))
        XCTAssertTrue(script.contains("function vitalFromTextBlock(panel, label)"))
        XCTAssertTrue(script.contains("function setExtractionStage(stage)"))
        XCTAssertTrue(script.contains("window.__kalvianRootsFamilySearchStage"))
        XCTAssertTrue(script.contains("const textBlockVital = vitalFromTextBlock(extractionDocument(), label);"))
        XCTAssertTrue(script.contains("Birth|Born|Christening|Christened|Baptism|Baptized|Death|Died|Burial|Buried"))
        XCTAssertTrue(script.contains("sourceCountSuffix"))
        XCTAssertTrue(script.contains("\\\\s*[•·]\\\\s*\\\\d+\\\\s+Sources?"))
        XCTAssertTrue(script.contains("function datesFromHeadingText(text)"))
        XCTAssertTrue(script.contains("function personNameFromHeadingText(text)"))
        XCTAssertTrue(script.contains("birthDate: birth.date || headingDates[0] || null"))
        XCTAssertTrue(script.contains("deathDate: death.date || headingDates[1] || null"))
        XCTAssertTrue(script.contains("function extractPersonSummaryFromDocument(doc, fallbackId)"))
        XCTAssertFalse(script.contains("function extractChildDetailsFromPersonPage(summary)"))
        XCTAssertFalse(script.contains("function extractChildDetailsFromFetchedHTML(summary, notes)"))
        XCTAssertFalse(script.contains("function extractChildDetailsFromRenderedDetailsPage(summary, notes)"))
        XCTAssertFalse(script.contains("new DOMParser().parseFromString(html, 'text/html')"))
        XCTAssertFalse(script.contains("extractionSource: 'detailsHTML'"))
        XCTAssertFalse(script.contains("extractionSource: 'detailsPage'"))
        XCTAssertFalse(script.contains("details HTML fetched"))
        XCTAssertTrue(script.contains("function withBlockedChildNavigation(summary, action)"))
        XCTAssertTrue(script.contains("window.history.pushState = function"))
        XCTAssertTrue(script.contains("event.preventDefault()"))
        XCTAssertTrue(script.contains("function childCardById(id)"))
        XCTAssertTrue(script.contains("function openChildQuickCard(summary, control, ignoredPanels)"))
        XCTAssertTrue(script.contains("new PointerEvent('pointerover'"))
        XCTAssertTrue(script.contains("control.dispatchEvent(new MouseEvent('mouseenter'"))
        XCTAssertTrue(script.contains("control.dispatchEvent(new MouseEvent('mousedown'"))
        XCTAssertTrue(script.contains("control.click();"))
        XCTAssertTrue(script.contains("async function closeChildPanel(panel, control, childId)"))
        XCTAssertTrue(script.contains("attempt < 8"))
        XCTAssertTrue(script.contains("function currentPanel()"))
        XCTAssertTrue(script.contains("panelCandidatesFor(childId)"))
        XCTAssertTrue(script.contains("function panelStillVisible()"))
        XCTAssertTrue(script.contains("async function clickCloseControl()"))
        XCTAssertTrue(script.contains("close|dismiss"))
        XCTAssertTrue(script.contains("const active = localDocument.activeElement;"))
        XCTAssertTrue(script.contains("if (await clickCloseControl()) return;"))
        XCTAssertTrue(script.contains("attempt < 2 && panelStillVisible()"))
        XCTAssertTrue(script.contains("follows the visible card instead of a stale element"))
        XCTAssertTrue(script.contains("for (const element of [control, activePanel])"))
        XCTAssertTrue(script.contains("for (const type of ['pointerout', 'pointerleave', 'mouseout', 'mouseleave'])"))
        XCTAssertTrue(script.contains("window.dispatchEvent(event);"))
        XCTAssertTrue(script.contains("localDocument.elementFromPoint(outsideX, outsideY)"))
        XCTAssertTrue(script.contains("new PointerEvent(type, { bubbles: true, cancelable: true, view: window, clientX: outsideX, clientY: outsideY, pointerType: 'mouse' })"))
        XCTAssertTrue(script.contains("new MouseEvent(type, { bubbles: true, cancelable: true, view: window, clientX: outsideX, clientY: outsideY })"))
        XCTAssertFalse(script.contains("remainingPanel.remove();"))
        XCTAssertTrue(script.contains("await closeChildPanel(panel, control, summary.id);"))
        XCTAssertTrue(script.contains("return await extractChildDetailsFromPanel(summary, notes);"))
        XCTAssertTrue(script.contains("const date = dateLikeFromText(values[0]);"))
        XCTAssertTrue(script.contains("return { date: null, place: null };"))
        XCTAssertTrue(script.contains("notes.push('using child quick-card click extraction')"))
        XCTAssertTrue(script.contains("blocked child detail navigation"))
        XCTAssertFalse(script.contains("notes.push('using child details HTML extraction')"))
        XCTAssertTrue(script.contains("parent page as partial context only"))
        XCTAssertTrue(script.contains("often year-only"))
        XCTAssertTrue(script.contains("birth: { date: null, place: null }"))
        XCTAssertTrue(script.contains("death: { date: null, place: null }"))
        XCTAssertTrue(script.contains("function clickableNameControl(summary)"))
        XCTAssertTrue(script.contains("return best;"))
        XCTAssertFalse(script.contains("a[href*=\"/tree/person/details/"))
        XCTAssertTrue(script.contains("function isEditControl(element)"))
        XCTAssertTrue(script.contains("Edit|Pencil"))
        XCTAssertTrue(script.contains("const enrichedSpouseGroups = [];"))
        XCTAssertTrue(script.contains("for (let groupIndex = 0; groupIndex < spouseGroups.length; groupIndex += 1)"))
        XCTAssertTrue(script.contains("for (let childIndex = 0; childIndex < group.children.length; childIndex += 1)"))
        XCTAssertTrue(script.contains("spouseGroups: enrichedSpouseGroups"))
        XCTAssertTrue(script.contains("selected group child birth dates extracted"))
        XCTAssertTrue(script.contains("all spouse group child birth dates extracted"))
        XCTAssertTrue(script.contains("child detail sources"))
        XCTAssertTrue(script.contains("quick-card"))
        XCTAssertFalse(script.contains("details HTML fetch diagnostics"))
        XCTAssertTrue(script.contains("FamilySearch child extraction note"))
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
        XCTAssertTrue(script.contains("function cleanupDetailFrame()"))
        XCTAssertTrue(script.contains("frame.src = 'about:blank';"))
        XCTAssertTrue(script.contains("frame.remove();"))
        XCTAssertTrue(script.contains("diagnosticContext"))
        XCTAssertTrue(script.contains("childrenMarkerCount"))
        XCTAssertTrue(script.contains("rawCandidateChildCount"))
        XCTAssertTrue(script.contains("found zero children"))
        XCTAssertTrue(script.contains("Kalvian Roots FamilySearch extraction succeeded"))
        XCTAssertTrue(script.contains("function showExtractionSuccessMessage(message)"))
        XCTAssertTrue(script.contains("Dismiss Kalvian Roots extraction message"))
        XCTAssertTrue(script.contains("closeButton.addEventListener('click'"))
        XCTAssertTrue(script.contains("window.setTimeout(function ()"))
        XCTAssertTrue(script.contains("}, 5000);"))
        XCTAssertTrue(script.contains("await closeChildPanel();"))
        XCTAssertTrue(script.contains("Kalvian Roots extracted FamilySearch children"))
        XCTAssertFalse(script.contains("alert('Kalvian Roots received FamilySearch extraction"))
        XCTAssertFalse(script.localizedCaseInsensitiveContains("do not show"))
        XCTAssertTrue(script.contains("finally {"))
        XCTAssertTrue(script.contains("cleanupDetailFrame();"))
        XCTAssertTrue(script.contains("preferred group children"))
        XCTAssertTrue(script.contains("FamilySearch extraction final stage"))
        XCTAssertTrue(script.contains("FamilySearch extraction stage at failure"))
        XCTAssertTrue(script.contains("\\b[A-Z0-9]{4}-[A-Z0-9]{3,}\\b"))
    }

    func testServerRenderedFamilyShowsFamilyFirstWithoutBookmarkletControls() {
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
            familySearchPersonId: "KJJH-2QK"
        )

        XCTAssertTrue(html.contains("class=\"family-content\""))
        XCTAssertTrue(html.contains("class=\"family-title\""))
        XCTAssertTrue(html.contains(">AHOKANGAS 2</a>"))
        XCTAssertTrue(html.contains("Pages: 1"))
        XCTAssertTrue(html.contains("Thomas"))
        XCTAssertTrue(html.contains("&lt;KJJH-2QK&gt;"))
        XCTAssertTrue(html.contains("Magdalena"))
        XCTAssertTrue(html.contains("15.05.1760"))
        XCTAssertTrue(html.contains("href=\"/family/AHOKANGAS%202/source\""))
        XCTAssertTrue(html.contains("href=\"/family/AHOKANGAS%202/workup\""))
        XCTAssertFalse(html.contains("class=\"family-workspace\""))
        XCTAssertFalse(html.contains("aria-label=\"Family review status\""))
        XCTAssertFalse(html.contains("id=\"children-comparison\""))
        XCTAssertFalse(html.contains("Copy comparison text"))
        XCTAssertFalse(html.contains("Open FamilySearch Details page"))
        XCTAssertFalse(html.localizedCaseInsensitiveContains("bookmarklet"))
        XCTAssertFalse(html.contains("Copy bookmarklet"))
        XCTAssertFalse(html.localizedCaseInsensitiveContains("Atlas"))
        XCTAssertFalse(html.contains("fs-script"))
    }

    func testServerRenderedFamilyLabelsChildrenBySource() {
        let nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        let family = Family(
            familyId: "SAKERI 1",
            pageReferences: ["264", "265"],
            husband: Person(name: "Matti", patronymic: "Juhonp.", familySearchId: "K8JR-2W8"),
            wife: Person(name: "Kaarin", patronymic: "Kustaant.", familySearchId: "M8ZF-GMC"),
            children: [
                Person(name: "Maria", birthDate: "12.02.1696")
            ]
        )
        let result = FamilyComparisonResult(
            familySearch: [
                PersonCandidate(
                    name: "Maria Mattsson",
                    identityName: "Maria",
                    birthDate: date(1696, 2, 12),
                    source: .familySearch,
                    nameManager: nameManager,
                    familySearchId: "M8ZK-DQP"
                )
            ],
            juuretKalvialla: [
                PersonCandidate(
                    name: "Maria",
                    birthDate: date(1696, 2, 12),
                    source: .juuretKalvialla,
                    nameManager: nameManager
                )
            ],
            hiski: [
                PersonCandidate(
                    name: "Maria",
                    birthDate: date(1696, 2, 12),
                    source: .hiski,
                    nameManager: nameManager
                )
            ]
        )

        let html = HTMLRenderer.renderFamily(
            family: family,
            network: nil,
            comparisonResult: result
        )

        XCTAssertTrue(html.contains("Lapset"))
        XCTAssertTrue(html.contains(">Maria</a>"))
        XCTAssertTrue(html.contains("&lt;M8ZK-DQP&gt;"))
        XCTAssertTrue(html.contains("<span class=\"source-markers\">FS, J, H</span>"))
        XCTAssertFalse(html.contains("id=\"children-comparison\""))
    }

    func testServerRenderedLapsetOpensHiskiChildResultsPopup() throws {
        let family = Family(
            familyId: "KYKYRI II 7",
            pageReferences: ["263", "264"],
            husband: Person(name: "Matti", patronymic: "Erikinp."),
            wife: Person(name: "Kaarin", patronymic: "Matint."),
            marriageDate: "12.11.1779",
            children: [
                Person(name: "Elias", birthDate: "07.12.1781")
            ]
        )
        let requestURL = try XCTUnwrap(URL(string: "https://hiski.genealogia.fi/hiski?en&alkuvuosi=1778&loppuvuosi=1814"))

        let html = HTMLRenderer.renderFamily(
            family: family,
            network: nil,
            hiskiChildSearchRequestsByCouple: [
                0: HiskiService.FamilyBirthSearchRequest(
                    label: "primary HisKi parent query",
                    url: requestURL
                )
            ]
        )

        XCTAssertTrue(html.contains("hiski-child-results-link"))
        XCTAssertTrue(html.contains("lapset-header"))
        XCTAssertTrue(html.contains("target=\"hiskiChildResults\""))
        XCTAssertTrue(html.contains("onclick=\"return openHiskiChildResults(this.href)\""))
        XCTAssertTrue(html.contains("https://hiski.genealogia.fi/hiski?en&amp;alkuvuosi=1778&amp;loppuvuosi=1814"))
        XCTAssertTrue(html.contains("function openHiskiChildResults(url)"))
    }

    func testServerRenderedLapsetLinksArePerCoupleForAdditionalSpouses() throws {
        let firstCouple = Couple(
            husband: Person(name: "Matti", patronymic: "Erikinp."),
            wife: Person(name: "Kaarin", patronymic: "Matint.", deathDate: "28.08.1785"),
            marriageDate: "12.11.1779",
            children: [
                Person(name: "Elias", birthDate: "07.12.1781")
            ]
        )
        let secondCouple = Couple(
            husband: Person(name: "Matti", patronymic: "Erikinp."),
            wife: Person(name: "Anna", patronymic: "Johant."),
            marriageDate: "04.06.1786",
            children: [
                Person(name: "Maria", birthDate: "01.05.1788")
            ]
        )
        let family = Family(
            familyId: "REMARRIED 1",
            pageReferences: ["1"],
            couples: [firstCouple, secondCouple]
        )
        let firstURL = try XCTUnwrap(URL(string: "https://hiski.genealogia.fi/hiski?en&alkuvuosi=1778&loppuvuosi=1785"))
        let secondURL = try XCTUnwrap(URL(string: "https://hiski.genealogia.fi/hiski?en&alkuvuosi=1785&loppuvuosi=1821"))

        let html = HTMLRenderer.renderFamily(
            family: family,
            network: nil,
            hiskiChildSearchRequestsByCouple: [
                0: HiskiService.FamilyBirthSearchRequest(label: "first spouse", url: firstURL),
                1: HiskiService.FamilyBirthSearchRequest(label: "second spouse", url: secondURL)
            ]
        )

        XCTAssertTrue(html.contains("https://hiski.genealogia.fi/hiski?en&amp;alkuvuosi=1778&amp;loppuvuosi=1785"))
        XCTAssertTrue(html.contains("https://hiski.genealogia.fi/hiski?en&amp;alkuvuosi=1785&amp;loppuvuosi=1821"))
        XCTAssertEqual(html.components(separatedBy: "target=\"hiskiChildResults\"").count - 1, 2)
    }

    func testHiskiSearchRequestUsesFirstChildWhenMarriageIsMissing() throws {
        let couple = Couple(
            husband: Person(name: "Matti", patronymic: "Juhonp."),
            wife: Person(name: "Kaarin", patronymic: "Kustaant.", deathDate: "26.05.1707"),
            marriageDate: nil,
            children: [
                Person(name: "Maria", birthDate: "12.02.1696"),
                Person(name: "Katarijna", birthDate: "18.02.1697")
            ]
        )

        let service = HiskiService(nameEquivalenceManager: NameEquivalenceManager())
        let window = try XCTUnwrap(HiskiService.familyBirthSearchWindow(for: couple))
        let request = try XCTUnwrap(
            service.buildFamilyBirthSearchRequests(
                fatherName: couple.husband.name,
                fatherPatronymic: couple.husband.patronymic,
                motherName: couple.wife.name,
                motherPatronymic: couple.wife.patronymic,
                startYear: window.startYear,
                endYear: window.endYear
            ).first
        )
        let values = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
            .reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value ?? ""
            }

        XCTAssertEqual(values["alkuvuosi"], "1691")
        XCTAssertEqual(values["loppuvuosi"], "1707")
        XCTAssertEqual(values["ietunimi"], "Matti")
        XCTAssertEqual(values["aetunimi"], "Kaarin")
    }

    func testWebKitExtractionScriptPostsResultToMessageHandler() {
        let script = FamilySearchDOMService.makeWebKitExtractionScript(for: " kjjh-2qk ")

        XCTAssertTrue(script.contains(FamilySearchDOMService.webKitExtractionMessageHandler))
        XCTAssertTrue(script.contains("window.webkit.messageHandlers"))
        XCTAssertTrue(script.contains("extractFamilySearchChildren"))
        XCTAssertTrue(script.contains("KJJH-2QK"))
        XCTAssertTrue(script.contains("KALVIAN_ROOTS_WEBKIT_TIMEOUT_MS = 85000"))
        XCTAssertTrue(script.contains("didPostKalvianRootsExtractionResult"))
        XCTAssertTrue(script.contains("extractorTimeout"))
        XCTAssertTrue(script.contains("FamilySearch extraction stage at timeout"))
        XCTAssertTrue(script.contains("function setWebKitExtractionStage(stage)"))
        XCTAssertTrue(script.contains("function postWebKitProgress(stage, message)"))
        XCTAssertTrue(script.contains("messageType: 'progress'"))
        XCTAssertTrue(script.contains("window.__kalvianRootsFamilySearchProgress = postWebKitProgress"))
        XCTAssertTrue(script.contains("WebKit wrapper entered extraction script"))
        XCTAssertTrue(script.contains("WebKit wrapper installed extractor"))
        XCTAssertTrue(script.contains("WebKit wrapper calling extractor"))
        XCTAssertTrue(script.contains("extractorUnavailable"))
        XCTAssertTrue(script.contains("const diagnostics = typeof diagnosticContext === 'function' ? diagnosticContext() : {};"))
        XCTAssertTrue(script.contains("familyMembersSectionFound: diagnostics.familyMembersSectionFound"))
        XCTAssertTrue(script.contains("spousesAndChildrenSectionFound: diagnostics.spousesAndChildrenSectionFound"))
        XCTAssertTrue(script.contains("childrenMarkerCount: diagnostics.childrenMarkerCount"))
        XCTAssertFalse(script.contains("KALVIAN_ROOTS_CALLBACK_URL"))
        XCTAssertFalse(script.contains("http://127.0.0.1:8081/familysearch/extraction-result"))
    }

    func testWebKitExtractionScriptCanUseCurrentDetailsPageWhenExpectedIdIsMissing() {
        let script = FamilySearchDOMService.makeWebKitExtractionScriptForCurrentPage()

        XCTAssertTrue(script.contains("KALVIAN_ROOTS_WEBKIT_EXPECTED_PERSON_ID = '';"))
        XCTAssertTrue(script.contains("window.location.pathname.match"))
        XCTAssertTrue(script.contains("Open a FamilySearch person Details page before extracting."))
        XCTAssertTrue(script.contains("extractFamilySearchChildren(KALVIAN_ROOTS_WEBKIT_PERSON_ID)"))
        XCTAssertFalse(script.contains("KJJH-2QK"))
    }

    func testFamilySearchExtractorWaitsForFamilyMembersSectionsBeforeReadingChildren() {
        let script = FamilySearchDOMService.makeFamilySearchExtractorScript()

        XCTAssertTrue(script.contains("window.__kalvianRootsFamilySearchProgress(window.__kalvianRootsFamilySearchStage)"))
        XCTAssertTrue(script.contains("async function waitForFamilyMembersSection(expectedId)"))
        XCTAssertTrue(script.contains("function visibleDocumentLines()"))
        XCTAssertTrue(script.contains(".split('\\n')"))
        XCTAssertTrue(script.contains(": visibleDocumentLines();"))
        XCTAssertTrue(script.contains("familyMembersSectionFound: !!section || familyIndex >= 0 || spousesIndex >= 0"))
        XCTAssertTrue(script.contains("waiting for Family Members section attempt "))
        XCTAssertTrue(script.contains("lastDiagnostics.familyMembersSectionFound && lastDiagnostics.spousesAndChildrenSectionFound"))
        XCTAssertTrue(script.contains("await waitForFamilyMembersSection(normalizedPersonId);"))
        XCTAssertLessThan(
            try XCTUnwrap(script.range(of: "await waitForFamilyMembersSection(normalizedPersonId);")?.lowerBound),
            try XCTUnwrap(script.range(of: "const spouseGroups = extractSpouseGroups();")?.lowerBound)
        )
    }

    #if os(macOS)
    func testWebKitDetailsPageDetectionWaitsPastLoginRedirect() {
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.isDetailsPageURL(
                "https://www.familysearch.org/en/auth/login",
                for: "K2YQ-1ZY"
            )
        )
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.isDetailsPageURL(
                "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
                for: "k2yq-1zy"
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.isDetailsPageURL(
                "https://ident.familysearch.org/en/identity/login/?state=https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
                for: "K2YQ-1ZY"
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.isDetailsPageDocumentReady(
                urlString: "https://ident.familysearch.org/en/identity/login/?state=https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
                pageTitle: "Sign-in to your account",
                readyState: "complete",
                for: "K2YQ-1ZY"
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.isDetailsPageDocumentReady(
                urlString: "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
                pageTitle: "Sign-in to your account",
                readyState: "complete",
                for: "K2YQ-1ZY"
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.isDetailsPageDocumentReady(
                urlString: "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
                pageTitle: "Erick Johansson Tikkanen (1716–1797) • Person • Family Tree",
                readyState: "loading",
                for: "K2YQ-1ZY"
            )
        )
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.isDetailsPageDocumentReady(
                urlString: "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
                pageTitle: "Erick Johansson Tikkanen (1716–1797) • Person • Family Tree",
                readyState: "complete",
                for: "k2yq-1zy"
            )
        )
    }

    func testWebKitFamilySearchLoginPageDetectionIsScopedToFamilySearchHosts() {
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.isFamilySearchLoginPage(
                URL(string: "https://ident.familysearch.org/en/identity/login/?state=https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY")
            )
        )
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.isFamilySearchLoginPage(
                URL(string: "https://ident.familysearch.org/cis-web/oauth2/v3/authorization?state=familysearch")
            )
        )
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.isFamilySearchLoginPage(
                URL(string: "https://www.familysearch.org/en/auth/login")
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.isFamilySearchLoginPage(
                URL(string: "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY")
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.isFamilySearchLoginPage(
                URL(string: "https://example.com/en/identity/login")
            )
        )
    }

    func testWebKitFamilySearchCredentialPromptOnlyAppliesToMissingCredentialsOnLoginPages() {
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.shouldPromptForFamilySearchCredential(
                on: URL(string: "https://ident.familysearch.org/cis-web/oauth2/v3/authorization"),
                storedCredentialAvailable: false,
                promptInProgress: false
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.shouldPromptForFamilySearchCredential(
                on: URL(string: "https://ident.familysearch.org/cis-web/oauth2/v3/authorization"),
                storedCredentialAvailable: true,
                promptInProgress: false
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.shouldPromptForFamilySearchCredential(
                on: URL(string: "https://ident.familysearch.org/cis-web/oauth2/v3/authorization"),
                storedCredentialAvailable: false,
                promptInProgress: true
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.shouldPromptForFamilySearchCredential(
                on: URL(string: "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY"),
                storedCredentialAvailable: false,
                promptInProgress: false
            )
        )
    }

    func testWebKitFamilySearchCredentialHostsPreferCurrentLoginHost() {
        XCTAssertEqual(
            FamilySearchWebViewExtractionManager.keychainCredentialHosts(
                for: URL(string: "https://ident.familysearch.org/en/identity/login/")
            ),
            [
                "ident.familysearch.org",
                "www.familysearch.org",
                "familysearch.org"
            ]
        )
        XCTAssertEqual(
            FamilySearchWebViewExtractionManager.keychainCredentialHosts(
                for: URL(string: "https://www.familysearch.org/en/auth/login")
            ),
            [
                "www.familysearch.org",
                "ident.familysearch.org",
                "familysearch.org"
            ]
        )
    }

    func testWebKitFamilySearchCredentialScriptFillsAndSubmitsVisibleLoginFields() throws {
        let script = try FamilySearchWebViewExtractionManager.makeCredentialSignInScript(
            username: "user@example.test",
            password: "secret-password"
        )

        XCTAssertTrue(script.contains(#""username":"user@example.test""#))
        XCTAssertTrue(script.contains(#""password":"secret-password""#))
        XCTAssertTrue(script.contains("document.querySelectorAll('input')"))
        XCTAssertTrue(script.contains("input.type || '').toLowerCase() === 'password'"))
        XCTAssertTrue(script.contains("const passwordPresent = !!passwordInput && passwordInput.value === credentials.password;"))
        XCTAssertTrue(script.contains("Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set"))
        XCTAssertTrue(script.contains("new KeyboardEvent(type"))
        XCTAssertTrue(script.contains("key === 'Enter' ? 13"))
        XCTAssertTrue(script.contains("dispatchKeyboardEvent(passwordInput, 'keydown', 'Enter')"))
        XCTAssertTrue(script.contains("new InputEvent('input'"))
        XCTAssertTrue(script.contains("preferredButton.click()"))
        XCTAssertTrue(script.contains("submitted-password"))
        XCTAssertTrue(script.contains("submitted-username"))
        XCTAssertTrue(script.contains("entered-password"))
        XCTAssertTrue(script.contains("entered-username"))
    }

    func testWebKitFamilyMembersSectionWaitProgressMessageReportsDiagnostics() {
        XCTAssertEqual(
            FamilySearchWebViewExtractionManager.familyMembersSectionWaitProgressMessage(
                attempt: 30,
                familyMembersSectionFound: true,
                spousesAndChildrenSectionFound: false,
                childrenMarkerCount: 3
            ),
            "FamilySearch WebKit waiting for Family Members section attempt 30: familyMembers=yes, spousesAndChildren=no, childMarkers=3"
        )
    }

    func testSwiftWebKitTimeoutPayloadReportsCurrentDetailsPage() {
        let extraction = FamilySearchWebViewExtractionManager.makeTimeoutExtractionPayload(
            expectedPersonId: " k2yq-1zy ",
            currentURL: "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
            pageTitle: "Erick Johansson Tikkanen (1716–1797) • Person • Family Tree",
            extractionStage: "extracting child 3/18 in spouse group 2/3: M8ZP-9VD Brita Eriksson",
            familyMembersSectionFound: true,
            spousesAndChildrenSectionFound: true,
            childrenMarkerCount: 3,
            blockedNavigationURL: "https://www.familysearch.org/en/tree/person/M8ZP-9VD"
        )

        XCTAssertFalse(extraction.isSuccessful)
        XCTAssertEqual(extraction.status, "extractorTimeout")
        XCTAssertEqual(extraction.sourcePersonId, "K2YQ-1ZY")
        XCTAssertEqual(extraction.parentFamilySearchId, "K2YQ-1ZY")
        XCTAssertEqual(extraction.detectedHost, "www.familysearch.org")
        XCTAssertEqual(extraction.detectedPersonId, "K2YQ-1ZY")
        XCTAssertEqual(extraction.expectedPersonId, "K2YQ-1ZY")
        XCTAssertEqual(extraction.isFamilySearchPage, true)
        XCTAssertEqual(extraction.isPersonDetailsPage, true)
        XCTAssertEqual(extraction.pageTitle, "Erick Johansson Tikkanen (1716–1797) • Person • Family Tree")
        XCTAssertEqual(extraction.familyMembersSectionFound, true)
        XCTAssertEqual(extraction.spousesAndChildrenSectionFound, true)
        XCTAssertEqual(extraction.childrenMarkerCount, 3)
        XCTAssertEqual(extraction.children.count, 0)
        XCTAssertTrue(extraction.failureReason?.contains("timed out after 90 seconds") == true)
        XCTAssertTrue(extraction.debugNotes?.contains("FamilySearch Swift WebKit timeout fired before the JavaScript message handler returned a result") == true)
        XCTAssertTrue(extraction.debugNotes?.contains("FamilySearch WebKit title at Swift timeout: Erick Johansson Tikkanen (1716–1797) • Person • Family Tree") == true)
        XCTAssertTrue(extraction.debugNotes?.contains("FamilySearch extraction stage at Swift timeout: extracting child 3/18 in spouse group 2/3: M8ZP-9VD Brita Eriksson") == true)
        XCTAssertTrue(extraction.debugNotes?.contains("FamilySearch WebKit blocked navigation during extraction: https://www.familysearch.org/en/tree/person/M8ZP-9VD") == true)
    }

    func testWebKitExtractionNavigationGuardAllowsOnlyExpectedPersonNavigation() throws {
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.shouldAllowNavigationDuringExtraction(
                to: URL(string: "https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY"),
                expectedPersonId: "k2yq-1zy"
            )
        )
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.shouldAllowNavigationDuringExtraction(
                to: URL(string: "https://ident.familysearch.org/en/identity/login/"),
                expectedPersonId: "K2YQ-1ZY"
            )
        )
        XCTAssertTrue(
            FamilySearchWebViewExtractionManager.shouldAllowNavigationDuringExtraction(
                to: URL(string: "https://www.familysearch.org/en/tree/"),
                expectedPersonId: nil
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.shouldAllowNavigationDuringExtraction(
                to: URL(string: "https://www.familysearch.org/en/tree/person/M8ZP-9VD"),
                expectedPersonId: "K2YQ-1ZY"
            )
        )
        XCTAssertFalse(
            FamilySearchWebViewExtractionManager.shouldAllowNavigationDuringExtraction(
                to: URL(string: "https://www.familysearch.org/en/tree/person/details/M8ZP-9VD"),
                expectedPersonId: "K2YQ-1ZY"
            )
        )
    }
    #endif

    func testFamilySearchSpouseGroupsRouteByBothParentIdsForRepeatedHusband() {
        let erik = Person(name: "Erik", familySearchId: "K2YQ-1ZY")
        let family = Family(
            familyId: "TIKKANEN 6",
            pageReferences: ["240", "241"],
            couples: [
                Couple(
                    husband: erik,
                    wife: Person(name: "Annika", familySearchId: "K2YQ-18B"),
                    children: []
                ),
                Couple(
                    husband: erik,
                    wife: Person(name: "Anna", familySearchId: "GMQH-8GF"),
                    children: [
                        Person(name: "Brita", birthDate: "20.05.1750", familySearchId: "M8ZP-9VD")
                    ]
                ),
                Couple(
                    husband: erik,
                    wife: Person(name: "Maria", familySearchId: "K8CD-718"),
                    children: [
                        Person(name: "Matti", birthDate: "14.03.1756", familySearchId: "LHH6-W2P")
                    ]
                )
            ],
            notes: [],
            noteDefinitions: [:]
        )

        let mappedChildren = FamilySearchSpouseGroupMatcher.childrenByCouple(
            family: family,
            spouseGroups: [
                FamilySearchSpouseGroup(
                    spouses: [
                        FamilySearchPersonSummary(id: "K2YQ-1ZY", name: "Erik Johansson Tikkanen"),
                        FamilySearchPersonSummary(id: "K2YQ-18B", name: "Annika Matintytar Riippa")
                    ],
                    marriage: nil,
                    declaredChildCount: 2,
                    children: [FamilySearchChild(id: "LXSP-RT8", name: "Tikkanen", birthDate: "1739")],
                    isPreferred: false
                ),
                FamilySearchSpouseGroup(
                    spouses: [
                        FamilySearchPersonSummary(id: "K2YQ-1ZY", name: "Erik Johansson Tikkanen"),
                        FamilySearchPersonSummary(id: "GMQH-8GF", name: "Anna Kaski")
                    ],
                    marriage: nil,
                    declaredChildCount: 5,
                    children: [FamilySearchChild(id: "M8ZP-9VD", name: "Brita Eriksson", birthDate: "20 May 1750")],
                    isPreferred: false
                ),
                FamilySearchSpouseGroup(
                    spouses: [
                        FamilySearchPersonSummary(id: "K2YQ-1ZY", name: "Erik Johansson Tikkanen"),
                        FamilySearchPersonSummary(id: "K8CD-718", name: "Maria Martensdotter Haak")
                    ],
                    marriage: nil,
                    declaredChildCount: 18,
                    children: [FamilySearchChild(id: "LHH6-W2P", name: "Matts Tikkanen", birthDate: "14 March 1756")],
                    isPreferred: true
                )
            ],
            fallbackChildren: []
        )

        XCTAssertEqual(mappedChildren[0]?.map(\.id), ["LXSP-RT8"])
        XCTAssertEqual(mappedChildren[1]?.map(\.id), ["M8ZP-9VD"])
        XCTAssertEqual(mappedChildren[2]?.map(\.id), ["LHH6-W2P"])
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

final class JuuretAppFamilySearchSourceTextTests: XCTestCase {

    func testPrimaryFamilySearchParentIdReadsFirstParentIdFromSourceText() {
        let familyText = """
        KYKYRI II 9, page 265
        ★ 31.07.1786 Juho Juhonp. <M8ZJ-HR6> {Vuolle II 3}
        ★ 08.05.1784 Maria Matint. <G19D-7W7> {Kykyri II 7} † 19.10.1810
        ∞ 08.06.1804
        Lapset
        ★ 07.07.1805 Matti <G6JH-PBW>
        """

        XCTAssertEqual(
            JuuretApp.primaryFamilySearchParentId(inFamilyText: familyText),
            "M8ZJ-HR6"
        )
    }

    func testPrimaryFamilySearchParentIdFallsBackToSecondParentOnlyWhenFirstHasNoId() {
        let familyText = """
        KYKYRI II 9, page 265
        ★ 31.07.1786 Juho Juhonp. {Vuolle II 3}
        ★ 08.05.1784 Maria Matint. <G19D-7W7> {Kykyri II 7} † 19.10.1810
        ∞ 08.06.1804
        Lapset
        ★ 07.07.1805 Matti <G6JH-PBW>
        """

        XCTAssertEqual(
            JuuretApp.primaryFamilySearchParentId(inFamilyText: familyText),
            "G19D-7W7"
        )
    }

    func testPrimaryFamilySearchParentIdDoesNotReadChildIds() {
        let familyText = """
        KYKYRI II 9, page 265
        ★ 31.07.1786 Juho Juhonp. {Vuolle II 3}
        ★ 08.05.1784 Maria Matint. {Kykyri II 7} † 19.10.1810
        ∞ 08.06.1804
        Lapset
        ★ 07.07.1805 Matti <M8ZJ-HR6>
        """

        XCTAssertNil(JuuretApp.primaryFamilySearchParentId(inFamilyText: familyText))
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
        XCTAssertTrue(text.contains("Matti\tYes, 14 Mar 1761\tNo\tYes, <LK4Q-YSX>, 14 Mar 1761\tMissing in HisKi"))
    }

    func testDebugTextIncludesFailureMessageWithoutComparisonRows() {
        let text = FamilySearchComparisonClipboardFormatter.debugText(
            debugMessage: "FamilySearch extraction failed (wrongPageType): wrong page type for FamilySearch extraction: https://ident.familysearch.org/en/identity/login/?state=https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY",
            debugLines: [
                "Family selected: TIKKANEN 6",
                "FamilySearch extraction status: wrongPageType",
                "FamilySearch extraction context URL: https://ident.familysearch.org/en/identity/login/?state=https://www.familysearch.org/en/tree/person/details/K2YQ-1ZY"
            ]
        )

        XCTAssertTrue(text.contains("FamilySearch extraction failed (wrongPageType)"))
        XCTAssertTrue(text.contains("FamilySearch extraction status: wrongPageType"))
        XCTAssertTrue(text.contains("FamilySearch extraction context URL: https://ident.familysearch.org"))
        XCTAssertFalse(text.contains("Child name\tJuuret\tHisKi\tFamilySearch\tStatus"))
        XCTAssertFalse(text.contains("Missing in FamilySearch"))
    }

    func testRowsFallBackToComparisonGroups() {
        let nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        nameManager.addEquivalence(between: "Mikko", and: "Michel")

        let groupedResult = FamilyComparisonResult(
            familySearch: [
                PersonCandidate(
                    name: "Michel Tikkanen",
                    identityName: "Michel",
                    birthDate: date(1757, 3, 5),
                    source: .familySearch,
                    nameManager: nameManager,
                    familySearchId: "FS-MICHEL"
                )
            ],
            juuretKalvialla: [
                PersonCandidate(
                    name: "Mikko",
                    birthDate: date(1757, 3, 5),
                    source: .juuretKalvialla,
                    nameManager: nameManager
                )
            ],
            hiski: []
        )
        let group = FamilyChildrenComparisonGroup(
            coupleIndex: 0,
            couple: Couple(husband: Person(name: "Erik"), wife: Person(name: "Maria")),
            hiskiSearchRequests: [],
            result: groupedResult
        )

        let rows = FamilySearchComparisonClipboardFormatter.rows(
            result: nil,
            groups: [group]
        )
        let text = FamilySearchComparisonClipboardFormatter.text(
            debugMessage: "FamilySearch comparison ready",
            debugLines: [],
            rows: rows,
            status: { _ in "Missing in HisKi" }
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(text.contains("(no rows)"))
        XCTAssertTrue(text.contains("Mikko\tYes, 05 Mar 1757\tNo\tYes, <FS-MICHEL>, 05 Mar 1757\tMissing in HisKi"))
    }

    func testPrimaryCoupleFallbackGroupWrapsSingleComparisonResult() throws {
        let nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()

        let result = FamilyComparisonResult(
            familySearch: [
                PersonCandidate(
                    name: "Matts Kykyri",
                    identityName: "Matti",
                    birthDate: date(1802, 6, 25),
                    source: .familySearch,
                    nameManager: nameManager,
                    familySearchId: "K1K9-QQW"
                )
            ],
            juuretKalvialla: [
                PersonCandidate(
                    name: "Matti",
                    birthDate: date(1802, 6, 25),
                    source: .juuretKalvialla,
                    nameManager: nameManager
                )
            ],
            hiski: []
        )
        let family = Family(
            familyId: "KYKYRI II 8",
            pageReferences: [],
            couples: [
                Couple(
                    husband: Person(name: "Elias", patronymic: "Matinp."),
                    wife: Person(name: "Brita", patronymic: "Jaakont."),
                    children: [
                        Person(name: "Matti", birthDate: "25.06.1802")
                    ]
                )
            ]
        )

        let group = try XCTUnwrap(FamilyChildrenComparisonGroup.primaryCoupleFallback(for: family, result: result))

        XCTAssertEqual(group.coupleIndex, 0)
        XCTAssertEqual(group.couple.children.map { $0.name }, ["Matti"])
        XCTAssertEqual(group.hiskiSearchRequests.count, 0)
        XCTAssertEqual(group.displayRows.count, 1)
        XCTAssertEqual(group.displayRows.first?.match.juuretKalvialla?.rawName, "Matti")
        XCTAssertEqual(group.displayRows.first?.match.familySearch?.familySearchId, "K1K9-QQW")
    }

    func testClipboardTextUsesGroupedSameDateNameMatch() {
        let nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()
        let service = FamilyComparisonService(nameManager: nameManager)

        let birthDate = date(1751, 11, 27)
        let result = FamilyComparisonResult(
            familySearch: [
                PersonCandidate(
                    name: "Johannes Eriksson",
                    identityName: "Johannes",
                    birthDate: birthDate,
                    source: .familySearch,
                    nameManager: nameManager,
                    familySearchId: "FS-JOHANNES"
                )
            ],
            juuretKalvialla: [
                PersonCandidate(
                    name: "Johannes",
                    birthDate: birthDate,
                    source: .juuretKalvialla,
                    nameManager: nameManager
                )
            ],
            hiski: [
                PersonCandidate(
                    name: "Johanna",
                    birthDate: birthDate,
                    source: .hiski,
                    nameManager: nameManager
                )
            ]
        )

        let text = FamilySearchComparisonClipboardFormatter.text(
            debugMessage: "FamilySearch comparison ready",
            debugLines: [],
            rows: result.rows,
            status: { service.status(for: $0) }
        )

        let johannesRows = text
            .split(separator: "\n")
            .filter { $0.contains("Johannes") || $0.contains("Johanna") }

        XCTAssertEqual(johannesRows.count, 1)
        XCTAssertTrue(text.contains("Johannes\tYes, 27 Nov 1751\tYes, 27 Nov 1751\tYes, <FS-JOHANNES>, 27 Nov 1751\tName mismatch"))
    }

    func testServerComparisonTableUsesGroupedSameDateNameMatch() {
        let nameManager = NameEquivalenceManager()
        nameManager.clearAllEquivalences()

        let birthDate = date(1751, 11, 27)
        let result = FamilyComparisonResult(
            familySearch: [
                PersonCandidate(
                    name: "Johannes Eriksson",
                    identityName: "Johannes",
                    birthDate: birthDate,
                    source: .familySearch,
                    nameManager: nameManager,
                    familySearchId: "FS-JOHANNES"
                )
            ],
            juuretKalvialla: [
                PersonCandidate(
                    name: "Johannes",
                    birthDate: birthDate,
                    source: .juuretKalvialla,
                    nameManager: nameManager
                )
            ],
            hiski: [
                PersonCandidate(
                    name: "Johanna",
                    birthDate: birthDate,
                    source: .hiski,
                    nameManager: nameManager
                )
            ]
        )
        let family = Family(
            familyId: "TIKKANEN 6",
            pageReferences: ["240"],
            husband: Person(name: "Erik"),
            wife: Person(name: "Anna"),
            children: []
        )

        let html = HTMLRenderer.renderFamily(
            family: family,
            network: nil,
            comparisonResult: result,
            familySearchExtraction: nil,
            familySearchPersonId: nil
        )

        let johannesLines = html
            .split(separator: "\n")
            .filter { $0.contains("Johannes") || $0.contains("Johanna") }

        XCTAssertEqual(johannesLines.filter { $0.contains("<td") }.count, 1)
        XCTAssertFalse(html.contains("<td class=\"comparison-review-name\""))
        XCTAssertTrue(html.contains("<td>Yes<br>27 Nov 1751</td>"))
        XCTAssertTrue(html.contains("<td>Yes<br>&lt;FS-JOHANNES&gt;<br>27 Nov 1751</td>"))
        XCTAssertTrue(html.contains("1 row, 0 needing review"))
        XCTAssertTrue(html.contains("class=\"comparison-table-wrap\""))
        XCTAssertTrue(html.contains("onclick=\"copyComparisonText()\""))
        XCTAssertTrue(html.contains("Johannes\tYes, 27 Nov 1751\tYes, 27 Nov 1751\tYes, &lt;FS-JOHANNES&gt;, 27 Nov 1751\tName mismatch"))
        XCTAssertTrue(html.contains("Name mismatch"))
        XCTAssertFalse(html.contains("HisKi-only"))
        XCTAssertFalse(html.contains("Missing in HisKi"))
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
