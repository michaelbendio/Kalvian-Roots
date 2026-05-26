import Foundation
import XCTest
@testable import Kalvian_Roots

final class FamilyWorkupServiceTests: XCTestCase {
    func testWorkupSummarizesFamilyHiskiQueriesAndFamilySearchAction() throws {
        let service = FamilyWorkupService(nameEquivalenceManager: NameEquivalenceManager())
        let family = Family(
            familyId: "SAKERI 1",
            pageReferences: ["264"],
            husband: Person(
                name: "Matti",
                patronymic: "Juhonp.",
                familySearchId: "K8JR-2W8"
            ),
            wife: Person(
                name: "Kaarin",
                patronymic: "Kustaant.",
                birthDate: "1680",
                familySearchId: "K87T-HMQ"
            ),
            marriageDate: "1697",
            children: [
                Person(name: "Maria", birthDate: "05.03.1697"),
                Person(name: "Matti", birthDate: "22.08.1698")
            ]
        )

        let workup = service.makeWorkup(
            family: family,
            network: FamilyNetwork(mainFamily: family),
            sourceText: "SAKERI 1\nLapset\nMaria\nMatti",
            familySearchExtraction: nil,
            familySearchPersonId: "K8JR-2W8",
            comparisonResult: nil
        )

        XCTAssertEqual(workup.familyId, "SAKERI 1")
        XCTAssertEqual(workup.couples.count, 1)
        XCTAssertEqual(workup.couples.first?.childCount, 2)
        XCTAssertTrue(workup.sourceTextAvailable)
        XCTAssertEqual(workup.familySearch.extractionStatus, "not-extracted")
        XCTAssertEqual(workup.familySearch.anchorPersonId, "K8JR-2W8")
        XCTAssertTrue(workup.familySearch.detailURL?.contains("K8JR-2W8") == true)
        XCTAssertFalse(workup.hiskiQueries.isEmpty)
        XCTAssertTrue(workup.hiskiQueries.contains { $0.label == "primary HisKi parent query" })
        XCTAssertTrue(workup.actions.contains { $0.type == "familysearch.extract" })
    }

    func testWorkupSummarizesComparisonRowsAndActions() throws {
        let nameManager = NameEquivalenceManager()
        let service = FamilyWorkupService(nameEquivalenceManager: nameManager)
        let family = Family(
            familyId: "TEST 1",
            pageReferences: ["1"],
            husband: Person(name: "Matti"),
            wife: Person(name: "Maria"),
            children: [
                Person(name: "Liisa", birthDate: "12.06.1760")
            ]
        )
        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let result = comparisonService.compare(
            juuretCandidates: comparisonService.makeJuuretCandidates(from: family.allChildren),
            hiskiCandidates: [],
            familySearchCandidates: []
        )

        let workup = service.makeWorkup(
            family: family,
            network: nil,
            sourceText: nil,
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "TEST-FS",
                children: []
            ),
            familySearchPersonId: nil,
            comparisonResult: result
        )

        XCTAssertEqual(workup.comparison?.rowCount, 1)
        XCTAssertEqual(workup.comparison?.juuretOnlyCount, 1)
        XCTAssertEqual(workup.comparison?.rows.first?.status, "Juuret-only")
        XCTAssertTrue(workup.actions.contains { $0.type == "citation.juuret" && $0.personName == "Liisa" })
    }
}
