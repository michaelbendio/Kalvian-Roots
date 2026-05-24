import Foundation

struct FamilyChildrenComparisonBuildResult {
    let group: FamilyChildrenComparisonGroup
    let proposals: [HiskiCitationProposal]
}

@MainActor
final class FamilyChildrenComparisonBuilder {
    private let hiskiService: HiskiService
    private let comparisonService: FamilyComparisonService
    private let loadHiskiSearchHtml: (URL) async throws -> String
    private let log: (String) -> Void

    init(
        hiskiService: HiskiService,
        comparisonService: FamilyComparisonService,
        loadHiskiSearchHtml: @escaping (URL) async throws -> String,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.hiskiService = hiskiService
        self.comparisonService = comparisonService
        self.loadHiskiSearchHtml = loadHiskiSearchHtml
        self.log = log
    }

    func buildGroup(
        couple: Couple,
        coupleIndex: Int,
        familySearchChildren: [FamilySearchChild],
        loadCitationProposals: Bool
    ) async throws -> FamilyChildrenComparisonBuildResult? {
        guard let hiskiWindow = HiskiService.familyBirthSearchWindow(for: couple) else {
            log("HisKi family-child search skipped for couple \(coupleIndex + 1): missing search window")
            return nil
        }

        log(
            "HisKi family-child search window for couple \(coupleIndex + 1): \(hiskiWindow.startYear)-\(hiskiWindow.endYear) (\(hiskiWindow.sourceDescription))"
        )

        let searchRequests = try hiskiService.buildFamilyBirthSearchRequests(
            fatherName: couple.husband.name,
            fatherPatronymic: couple.husband.patronymic,
            motherName: couple.wife.name,
            motherPatronymic: couple.wife.patronymic,
            startYear: hiskiWindow.startYear,
            endYear: hiskiWindow.endYear
        )

        var rawRows: [HiskiService.HiskiFamilyBirthRow] = []
        for request in searchRequests {
            log("HisKi family-child search started: \(request.label)")
            let searchHtml = try await loadHiskiSearchHtml(request.url)
            rawRows = hiskiService.parseFamilyBirthResultsTable(searchHtml)
            log("HisKi raw family-child rows parsed: \(rawRows.count)")

            if !rawRows.isEmpty {
                log("HisKi family-child search matched: \(request.label)")
                break
            }
        }

        let structuredRowsResult = hiskiService.filterFamilyBirthRowsAnchoredToJuuretChildren(
            rawRows,
            juuretChildren: couple.children,
            additionalAnchorBirthDates: familySearchChildren.flatMap { child in
                [child.birthDate, child.birth?.date, child.christeningDate, child.christening?.date]
            }
        )
        let structuredRows = structuredRowsResult.rows
        log("HisKi raw family-child rows parsed: \(structuredRowsResult.originalRowCount)")
        log("HisKi structured family-child rows \(structuredRowsResult.confidenceLabel): \(structuredRows.count)")
        log("FamilyComparisonService invoked")

        let result = comparisonService.compare(
            juuretCandidates: comparisonService.makeJuuretCandidates(from: couple.children),
            hiskiCandidates: comparisonService.makeHiskiCandidates(from: structuredRows),
            familySearchCandidates: comparisonService.makeFamilySearchCandidates(
                from: familySearchChildren,
                matchingHiskiRows: structuredRows
            )
        )

        let proposals = try await makeCitationProposals(
            couple: couple,
            familySearchChildren: familySearchChildren,
            structuredRows: structuredRows,
            loadCitationProposals: loadCitationProposals
        )

        return FamilyChildrenComparisonBuildResult(
            group: FamilyChildrenComparisonGroup(
                coupleIndex: coupleIndex,
                couple: couple,
                hiskiSearchRequests: searchRequests,
                result: result
            ),
            proposals: proposals
        )
    }

    private func makeCitationProposals(
        couple: Couple,
        familySearchChildren: [FamilySearchChild],
        structuredRows: [HiskiService.HiskiFamilyBirthRow],
        loadCitationProposals: Bool
    ) async throws -> [HiskiCitationProposal] {
        guard loadCitationProposals else {
            return []
        }

        let citationLoad = await hiskiService.fetchCitationEventsForFamilyBirthRows(structuredRows)
        if citationLoad.failures.isEmpty {
            log("HisKi citation events loaded: \(citationLoad.events.count)")
        } else {
            log("HisKi citation events loaded: \(citationLoad.events.count); unavailable: \(citationLoad.failures.count)")
            for failure in citationLoad.failures {
                log("HisKi citation event unavailable for \(failure.logDescription)")
            }
        }

        let citationResult = comparisonService.compare(
            juuretCandidates: comparisonService.makeJuuretCandidates(from: couple.children),
            hiskiCandidates: comparisonService.makeHiskiCandidates(from: citationLoad.events),
            familySearchCandidates: comparisonService.makeFamilySearchCandidates(
                from: familySearchChildren,
                matchingHiskiRows: structuredRows
            )
        )
        return comparisonService.makeHiskiCitationProposals(from: citationResult)
    }
}

enum FamilySearchSpouseGroupMatcher {
    static func childrenByCouple(
        family: Family,
        spouseGroups: [FamilySearchSpouseGroup],
        fallbackChildren: [FamilySearchChild]
    ) -> [Int: [FamilySearchChild]] {
        var childrenByCouple: [Int: [FamilySearchChild]] = [:]

        for (coupleIndex, couple) in family.couples.enumerated() {
            let matchingGroups = spouseGroups.filter { spouseGroup($0, matches: couple) }
            guard matchingGroups.count == 1, let matchingGroup = matchingGroups.first else {
                continue
            }

            childrenByCouple[coupleIndex] = matchingGroup.children
        }

        if childrenByCouple.isEmpty, !fallbackChildren.isEmpty {
            childrenByCouple[0] = fallbackChildren
        }

        return childrenByCouple
    }

    private static func spouseGroup(_ group: FamilySearchSpouseGroup, matches couple: Couple) -> Bool {
        let coupleFamilySearchIds = Set(
            [couple.husband.familySearchId, couple.wife.familySearchId]
                .compactMap(normalizedFamilySearchId)
        )

        guard !coupleFamilySearchIds.isEmpty else {
            return false
        }

        let groupFamilySearchIds = Set(group.spouses.compactMap { normalizedFamilySearchId($0.id) })
        if coupleFamilySearchIds.count >= 2 {
            return groupFamilySearchIds.isSuperset(of: coupleFamilySearchIds)
        }

        return !coupleFamilySearchIds.isDisjoint(with: groupFamilySearchIds)
    }

    private static func normalizedFamilySearchId(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}
