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
        let extractionAction = try XCTUnwrap(workup.actions.first { $0.type == "familysearch.extract" })
        XCTAssertEqual(extractionAction.id, "SAKERI 1:familysearch.extract:K8JR-2W8")
        XCTAssertEqual(extractionAction.familyId, "SAKERI 1")
        XCTAssertNil(extractionAction.context)
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

        let sourceUpdateAction = try XCTUnwrap(workup.actions.first {
            $0.type == "source.update.familysearch-id" &&
            $0.personName == "Liisa" &&
            $0.personId == "AB12-CD"
        })
        XCTAssertTrue(sourceUpdateAction.requiresApproval)
        XCTAssertEqual(sourceUpdateAction.id, "TEST 2:source.update.familysearch-id:0:elis:1760-06-12:AB12-CD:Liisa")
        XCTAssertEqual(sourceUpdateAction.familyId, "TEST 2")
        XCTAssertEqual(
            sourceUpdateAction.approvalPrompt,
            "Should I add AB12-CD to Liisa in the canonical Juuret source text?"
        )
        XCTAssertEqual(sourceUpdateAction.context?.coupleIndex, 0)
        XCTAssertEqual(sourceUpdateAction.context?.identityName, "elis")
        XCTAssertEqual(sourceUpdateAction.context?.birthDate, "1760-06-12")
        XCTAssertEqual(sourceUpdateAction.context?.status, "Missing in HisKi")
        XCTAssertEqual(sourceUpdateAction.context?.juuret?.name, "Liisa")
        XCTAssertNil(sourceUpdateAction.context?.juuret?.familySearchId)
        XCTAssertEqual(sourceUpdateAction.context?.familySearch?.name, "Liisa Mattsdotter")
        XCTAssertEqual(sourceUpdateAction.context?.familySearch?.familySearchId, "AB12-CD")

        let html = HTMLRenderer.renderWorkup(workup, family: family, homeId: family.familyId)
        XCTAssertTrue(html.contains("TEST 2:source.update.familysearch-id:0:elis:1760-06-12:AB12-CD:Liisa"))
        XCTAssertTrue(html.contains("Should I add AB12-CD to Liisa in the canonical Juuret source text?"))
        XCTAssertTrue(html.contains("Couple 1"))
        XCTAssertTrue(html.contains("Juuret: Liisa, 1760-06-12"))
        XCTAssertTrue(html.contains("FamilySearch: Liisa Mattsdotter, 1760-06-12, AB12-CD"))
        XCTAssertTrue(html.contains(#"id="review-queue""#))
        XCTAssertTrue(html.contains("href=\"#source-updates\""))
        XCTAssertTrue(html.contains(#"id="source-updates""#))
        XCTAssertTrue(html.contains("Source Updates"))
        XCTAssertTrue(html.contains("Copy ID"))
        XCTAssertTrue(html.contains("Copy Dry Run"))
        XCTAssertTrue(html.contains("Copy Apply"))
        XCTAssertTrue(html.contains("Tools/juuret-project/juuret-project source-edit-dry-run"))
        XCTAssertTrue(html.contains("Tools/juuret-project/juuret-project source-edit-apply"))

        let familyHTML = HTMLRenderer.renderFamily(
            family: family,
            network: nil,
            comparisonResult: result,
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "TEST-FS",
                children: familySearchChildren
            ),
            familySearchPersonId: "TEST-FS",
            workup: workup
        )
        XCTAssertTrue(familyHTML.contains(#"id="family-review-queue""#))
        XCTAssertTrue(familyHTML.contains("1 queued action"))
        XCTAssertTrue(familyHTML.contains(##"href="#family-review-queue">Review</a>"##))
        XCTAssertTrue(familyHTML.contains("Review Queue"))
        XCTAssertTrue(familyHTML.contains("1 queued action for collaborative review."))
        XCTAssertTrue(familyHTML.contains("Copy review packet"))
        XCTAssertTrue(familyHTML.contains(#"id="familyReviewPacketText""#))
        XCTAssertTrue(familyHTML.contains("Kalvian Roots Review Queue"))
        XCTAssertTrue(familyHTML.contains("Family: TEST 2"))
        XCTAssertTrue(familyHTML.contains("Source updates: 1"))
        XCTAssertTrue(familyHTML.contains(#"href="/family/TEST%202/workup#review-queue""#))
        XCTAssertTrue(familyHTML.contains("TEST 2:source.update.familysearch-id:0:elis:1760-06-12:AB12-CD:Liisa"))
        XCTAssertTrue(familyHTML.contains("Dry run: Tools/juuret-project/juuret-project source-edit-dry-run"))
        XCTAssertTrue(familyHTML.contains("Apply: Tools/juuret-project/juuret-project source-edit-apply"))
        XCTAssertTrue(familyHTML.contains("Copy ID"))
        XCTAssertTrue(familyHTML.contains("Copy Dry Run"))
        XCTAssertTrue(familyHTML.contains("Copy Apply"))
        XCTAssertLessThan(
            familyHTML.range(of: "class=\"family-content\"")!.lowerBound,
            familyHTML.range(of: #"id="family-review-queue""#)!.lowerBound
        )
        XCTAssertLessThan(
            familyHTML.range(of: ##"href="#family-review-queue">Review</a>"##)!.lowerBound,
            familyHTML.range(of: #"id="family-review-queue""#)!.lowerBound
        )
        XCTAssertLessThan(
            familyHTML.range(of: #"id="family-review-queue""#)!.lowerBound,
            familyHTML.range(of: #"id="children-comparison""#)!.lowerBound
        )
    }

    func testWorkupDoesNotProposeSourceUpdateWhenJuuretAlreadyHasMatchingFamilySearchId() throws {
        let nameManager = NameEquivalenceManager()
        let service = FamilyWorkupService(nameEquivalenceManager: nameManager)
        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let family = Family(
            familyId: "TEST 2A",
            pageReferences: ["2"],
            husband: Person(name: "Matti"),
            wife: Person(name: "Maria"),
            children: [
                Person(name: "Liisa", birthDate: "12.06.1760", familySearchId: "AB12-CD")
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
            sourceText: "TEST 2A\nLiisa <AB12-CD>",
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "TEST-FS",
                children: familySearchChildren
            ),
            familySearchPersonId: "TEST-FS",
            comparisonResult: result
        )

        XCTAssertFalse(workup.actions.contains { $0.type == "source.update.familysearch-id" })
        XCTAssertFalse(workup.actions.contains { $0.type == "review.familysearch-id-mismatch" })
        XCTAssertEqual(workup.comparison?.rows.first?.juuret?.familySearchId, "AB12-CD")
    }

    func testWorkupProposesReviewWhenJuuretAndFamilySearchIdsDiffer() throws {
        let nameManager = NameEquivalenceManager()
        let service = FamilyWorkupService(nameEquivalenceManager: nameManager)
        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let family = Family(
            familyId: "TEST 2B",
            pageReferences: ["2"],
            husband: Person(name: "Matti"),
            wife: Person(name: "Maria"),
            children: [
                Person(name: "Maria", birthDate: "12.02.1696", familySearchId: "PD55-86C")
            ]
        )
        let familySearchChildren = [
            FamilySearchChild(id: "M8ZK-DQP", name: "Maria Mattsson", birthDate: "12 February 1696")
        ]
        let result = comparisonService.compare(
            juuretCandidates: comparisonService.makeJuuretCandidates(from: family.allChildren),
            hiskiCandidates: [],
            familySearchCandidates: comparisonService.makeFamilySearchCandidates(from: familySearchChildren)
        )

        let workup = service.makeWorkup(
            family: family,
            network: nil,
            sourceText: "TEST 2B\nMaria <PD55-86C>",
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "TEST-FS",
                children: familySearchChildren
            ),
            familySearchPersonId: "TEST-FS",
            comparisonResult: result
        )

        XCTAssertFalse(workup.actions.contains { $0.type == "source.update.familysearch-id" })
        let mismatchAction = try XCTUnwrap(workup.actions.first {
            $0.type == "review.familysearch-id-mismatch"
        })
        XCTAssertEqual(mismatchAction.personName, "Maria")
        XCTAssertEqual(mismatchAction.personId, "M8ZK-DQP")
        XCTAssertEqual(
            mismatchAction.approvalPrompt,
            "Juuret has PD55-86C for Maria, but FamilySearch extraction matched M8ZK-DQP. Which ID is correct?"
        )
        XCTAssertEqual(mismatchAction.context?.juuret?.familySearchId, "PD55-86C")
        XCTAssertEqual(mismatchAction.context?.familySearch?.familySearchId, "M8ZK-DQP")

        let html = HTMLRenderer.renderWorkup(workup, family: family, homeId: family.familyId)
        XCTAssertTrue(html.contains("review.familysearch-id-mismatch"))
        XCTAssertTrue(html.contains(#"id="review-queue""#))
        XCTAssertTrue(html.contains("href=\"#familysearch-id-mismatches\""))
        XCTAssertTrue(html.contains(#"id="familysearch-id-mismatches""#))
        XCTAssertTrue(html.contains("FamilySearch ID Mismatches"))
        XCTAssertTrue(html.contains("Copy Dry Run"))
        XCTAssertTrue(html.contains("Copy Apply"))
        XCTAssertTrue(html.contains("Tools/juuret-project/juuret-project source-edit-dry-run"))
        XCTAssertTrue(html.contains("Tools/juuret-project/juuret-project source-edit-apply"))
    }

    func testWorkupActionContextIncludesCoupleIndexForMatchedJuuretChild() throws {
        let nameManager = NameEquivalenceManager()
        let service = FamilyWorkupService(nameEquivalenceManager: nameManager)
        let comparisonService = FamilyComparisonService(nameManager: nameManager)
        let family = Family(
            familyId: "TEST 3",
            pageReferences: ["3"],
            couples: [
                Couple(
                    husband: Person(name: "Matti"),
                    wife: Person(name: "Maria"),
                    children: [
                        Person(name: "Liisa", birthDate: "12.06.1760")
                    ]
                ),
                Couple(
                    husband: Person(name: "Matti"),
                    wife: Person(name: "Kaisa"),
                    children: [
                        Person(name: "Anna", birthDate: "14.04.1764")
                    ]
                )
            ]
        )
        let familySearchChildren = [
            FamilySearchChild(id: "CD34-EF", name: "Anna Mattsdotter", birthDate: "14 April 1764")
        ]
        let result = comparisonService.compare(
            juuretCandidates: comparisonService.makeJuuretCandidates(from: family.allChildren),
            hiskiCandidates: [],
            familySearchCandidates: comparisonService.makeFamilySearchCandidates(from: familySearchChildren)
        )

        let workup = service.makeWorkup(
            family: family,
            network: nil,
            sourceText: "TEST 3\nAnna",
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "TEST-FS",
                children: familySearchChildren
            ),
            familySearchPersonId: "TEST-FS",
            comparisonResult: result
        )

        let sourceUpdateAction = try XCTUnwrap(workup.actions.first {
            $0.type == "source.update.familysearch-id" &&
            $0.personName == "Anna" &&
            $0.personId == "CD34-EF"
        })
        XCTAssertEqual(sourceUpdateAction.context?.coupleIndex, 1)
        XCTAssertEqual(sourceUpdateAction.id, "TEST 3:source.update.familysearch-id:1:anna:1764-04-14:CD34-EF:Anna")
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

    func testWorkupDoesNotProposeSourceUpdateWhenSourceTextAlreadyHasFamilySearchId() throws {
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
            sourceText: "SAKERI 1\n★ 26.07.1707\tMalin <M8ZN-MBH>",
            familySearchExtraction: FamilySearchFamilyExtraction(
                sourcePersonId: "K8JR-2W8",
                children: familySearchChildren
            ),
            familySearchPersonId: "K8JR-2W8",
            comparisonResult: result
        )

        XCTAssertFalse(workup.actions.contains {
            $0.type == "source.update.familysearch-id" &&
                $0.personName == "Malin" &&
                $0.personId == "M8ZN-MBH"
        })
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

        XCTAssertTrue(html.contains("Review Queue"))
        XCTAssertTrue(html.contains("Other Actions"))
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
