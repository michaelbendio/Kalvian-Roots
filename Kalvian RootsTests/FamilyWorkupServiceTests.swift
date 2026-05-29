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

    func testWorkupProposesApprovedFamilySearchIdSourceUpdateForMatchedChild() throws {
        let nameManager = NameEquivalenceManager()
        let service = FamilyWorkupService(nameEquivalenceManager: nameManager)
        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let family = Family(
            familyId: "TEST 2",
            pageReferences: ["2"],
            husband: Person(name: "Matti"),
            wife: Person(name: "Maria"),
            children: [
                Person(name: "Liisa", birthDate: "12.06.1760")
            ]
        )
        let familySearchChildren = [
            FamilySearchChild(id: "AB12-CD", name: "Liisa Mattsdotter", birthDate: "12 June 1760")
        ]
        let result = comparisonService.compare(
            juuretCandidates: comparisonService.makeJuuretCandidates(from: family.allChildren),
            hiskiCandidates: [],
            familySearchCandidates: comparisonService.makeFamilySearchCandidates(from: familySearchChildren)
        )

        let workup = service.makeWorkup(
            family: family,
            network: nil,
            sourceText: "TEST 2\nLiisa",
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "TEST-FS",
                children: familySearchChildren
            ),
            familySearchPersonId: "TEST-FS",
            comparisonResult: result
        )

        XCTAssertTrue(workup.actions.contains {
            $0.type == "source.update.familysearch-id" &&
            $0.personName == "Liisa" &&
            $0.personId == "AB12-CD" &&
            $0.requiresApproval
        })
    }

    func testWorkupMergesNearbySameNameDateDiscrepancyIntoReviewAction() throws {
        let nameManager = NameEquivalenceManager()
        let service = FamilyWorkupService(nameEquivalenceManager: nameManager)
        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let family = Family(
            familyId: "SAKERI 1",
            pageReferences: ["264"],
            husband: Person(name: "Matti", familySearchId: "K8JR-2W8"),
            wife: Person(name: "Kaarin"),
            children: [
                Person(name: "Malin", birthDate: "26.07.1707")
            ]
        )
        let hiskiRows = [
            HiskiService.HiskiFamilyBirthRow(
                birthDate: "26.05.1707",
                childName: "Malin",
                fatherName: "Matti",
                motherName: "Kaarin",
                recordPath: "/hiski/test"
            )
        ]
        let familySearchChildren = [
            FamilySearchChild(id: "M8ZN-MBH", name: "Malin Mattsson", birthDate: "26 May 1707")
        ]
        let result = comparisonService.compare(
            juuretCandidates: comparisonService.makeJuuretCandidates(from: family.allChildren),
            hiskiCandidates: comparisonService.makeHiskiCandidates(from: hiskiRows),
            familySearchCandidates: comparisonService.makeFamilySearchCandidates(from: familySearchChildren)
        )

        let workup = service.makeWorkup(
            family: family,
            network: FamilyNetwork(mainFamily: family),
            sourceText: "SAKERI 1\nMalin",
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "K8JR-2W8",
                children: familySearchChildren
            ),
            familySearchPersonId: "K8JR-2W8",
            comparisonResult: result
        )

        XCTAssertEqual(workup.comparison?.rowCount, 1)
        XCTAssertEqual(workup.comparison?.rows.first?.status, "Review date discrepancy")
        XCTAssertTrue(workup.comparison?.rows.first?.reviewNote?.contains("Possible same child with date discrepancy") == true)
        XCTAssertTrue(workup.actions.contains { $0.type == "review.comparison" && $0.personName == "Malin" })
        XCTAssertFalse(workup.actions.contains { $0.type == "citation.juuret" && $0.personName == "Malin" })
    }

    func testWorkupRendererShowsFamilySearchExtractionButtonWhenNeeded() throws {
        let service = FamilyWorkupService(nameEquivalenceManager: NameEquivalenceManager())
        let family = Family(
            familyId: "SAKERI 1",
            pageReferences: ["264"],
            husband: Person(name: "Matti", familySearchId: "K8JR-2W8"),
            wife: Person(name: "Kaarin"),
            children: [
                Person(name: "Maria", birthDate: "05.03.1697")
            ]
        )
        let workup = service.makeWorkup(
            family: family,
            network: FamilyNetwork(mainFamily: family),
            sourceText: "SAKERI 1\nMaria",
            familySearchExtraction: nil,
            familySearchPersonId: "K8JR-2W8",
            comparisonResult: nil
        )

        let html = HTMLRenderer.renderWorkup(workup, family: family, homeId: family.familyId)

        XCTAssertTrue(html.contains(#"<form method="post" action="/family/SAKERI%201/familysearch-extract""#))
        XCTAssertTrue(html.contains("Run FamilySearch Extraction"))
    }

    func testWorkupRendererHidesFamilySearchExtractionButtonAfterExtraction() throws {
        let service = FamilyWorkupService(nameEquivalenceManager: NameEquivalenceManager())
        let family = Family(
            familyId: "SAKERI 1",
            pageReferences: ["264"],
            husband: Person(name: "Matti", familySearchId: "K8JR-2W8"),
            wife: Person(name: "Kaarin"),
            children: [
                Person(name: "Maria", birthDate: "05.03.1697")
            ]
        )
        let workup = service.makeWorkup(
            family: family,
            network: FamilyNetwork(mainFamily: family),
            sourceText: "SAKERI 1\nMaria",
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "K8JR-2W8",
                children: [
                    FamilySearchChild(id: "TEST-123", name: "Maria", birthDate: "5 March 1697")
                ]
            ),
            familySearchPersonId: "K8JR-2W8",
            comparisonResult: nil
        )

        let html = HTMLRenderer.renderWorkup(workup, family: family, homeId: family.familyId)

        XCTAssertFalse(html.contains("familysearch-extract"))
        XCTAssertFalse(html.contains("Run FamilySearch Extraction"))
    }
}
