import Foundation

struct FamilyWorkup: Codable, Equatable {
    struct PersonSummary: Codable, Equatable {
        let name: String
        let displayName: String
        let birthDate: String?
        let deathDate: String?
        let familySearchId: String?
    }

    struct CoupleSummary: Codable, Equatable {
        let index: Int
        let husband: PersonSummary
        let wife: PersonSummary
        let marriageDate: String?
        let fullMarriageDate: String?
        let childCount: Int
        let children: [PersonSummary]
    }

    struct NetworkSummary: Codable, Equatable {
        let asChildFamilyCount: Int
        let asParentFamilyCount: Int
        let spouseAsChildFamilyCount: Int
    }

    struct FamilySearchSummary: Codable, Equatable {
        let anchorPersonId: String?
        let extractionStatus: String
        let extractedChildCount: Int
        let detailURL: String?
        let note: String?
    }

    struct HiskiQuerySummary: Codable, Equatable {
        let coupleIndex: Int
        let label: String
        let url: String
        let startYear: Int
        let endYear: Int
        let sourceDescription: String
    }

    struct CandidateSummary: Codable, Equatable {
        let source: String
        let name: String
        let birthDate: String?
        let deathDate: String?
        let familySearchId: String?
        let hiskiCitation: String?
    }

    struct ComparisonRow: Codable, Equatable {
        let coupleIndex: Int?
        let identityName: String
        let birthDate: String?
        let status: String
        let familySearch: CandidateSummary?
        let juuret: CandidateSummary?
        let hiski: CandidateSummary?
        let reviewNote: String?
    }

    struct ComparisonSummary: Codable, Equatable {
        let rowCount: Int
        let matchCount: Int
        let familySearchOnlyCount: Int
        let juuretOnlyCount: Int
        let hiskiOnlyCount: Int
        let rows: [ComparisonRow]
    }

    struct ActionSummary: Codable, Equatable {
        let id: String
        let familyId: String
        let type: String
        let label: String
        let personName: String?
        let personId: String?
        let requiresApproval: Bool
        let approvalPrompt: String?
        let context: ActionContext?
    }

    struct ActionContext: Codable, Equatable {
        let coupleIndex: Int?
        let identityName: String?
        let birthDate: String?
        let status: String?
        let familySearch: CandidateSummary?
        let juuret: CandidateSummary?
        let hiski: CandidateSummary?
    }

    let familyId: String
    let pageReferences: [String]
    let sourceTextAvailable: Bool
    let sourceTextLineCount: Int
    let couples: [CoupleSummary]
    let network: NetworkSummary?
    let familySearch: FamilySearchSummary
    let hiskiQueries: [HiskiQuerySummary]
    let comparison: ComparisonSummary?
    let actions: [ActionSummary]
}

final class FamilyWorkupService {
    private let nameEquivalenceManager: NameEquivalenceManager
    private let comparisonService: FamilyComparisonService
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(nameEquivalenceManager: NameEquivalenceManager) {
        self.nameEquivalenceManager = nameEquivalenceManager
        self.comparisonService = FamilyComparisonService(nameManager: nameEquivalenceManager)
    }

    func makeWorkup(
        family: Family,
        network: FamilyNetwork?,
        sourceText: String?,
        familySearchExtraction: FamilySearchFamilyExtraction?,
        familySearchPersonId: String?,
        comparisonResult: FamilyComparisonResult?
    ) -> FamilyWorkup {
        let hiskiQueries = makeHiskiQueries(for: family)
        let comparison = comparisonResult.map { makeComparisonSummary($0, family: family) }
        let familySearchSummary = makeFamilySearchSummary(
            extraction: familySearchExtraction,
            familySearchPersonId: familySearchPersonId
        )

        return FamilyWorkup(
            familyId: family.familyId,
            pageReferences: family.pageReferences,
            sourceTextAvailable: sourceText != nil,
            sourceTextLineCount: sourceText?.components(separatedBy: .newlines).count ?? 0,
            couples: family.couples.enumerated().map { index, couple in
                FamilyWorkup.CoupleSummary(
                    index: index,
                    husband: makePersonSummary(couple.husband),
                    wife: makePersonSummary(couple.wife),
                    marriageDate: couple.marriageDate,
                    fullMarriageDate: couple.fullMarriageDate,
                    childCount: couple.children.count,
                    children: couple.children.map(makePersonSummary)
                )
            },
            network: network.map {
                FamilyWorkup.NetworkSummary(
                    asChildFamilyCount: $0.asChildFamilies.count,
                    asParentFamilyCount: $0.asParentFamilies.count,
                    spouseAsChildFamilyCount: $0.spouseAsChildFamilies.count
                )
            },
            familySearch: familySearchSummary,
            hiskiQueries: hiskiQueries,
            comparison: comparison,
            actions: makeActions(
                familyId: family.familyId,
                familySearch: familySearchSummary,
                comparison: comparison
            )
        )
    }

    private func makeHiskiQueries(for family: Family) -> [FamilyWorkup.HiskiQuerySummary] {
        let hiskiService = HiskiService(nameEquivalenceManager: nameEquivalenceManager)
        hiskiService.setCurrentFamily(family.familyId)
        var summaries: [FamilyWorkup.HiskiQuerySummary] = []

        for (index, couple) in family.couples.enumerated() where !couple.children.isEmpty {
            guard let window = HiskiService.familyBirthSearchWindow(for: couple) else {
                continue
            }

            guard let requests = try? hiskiService.buildFamilyBirthSearchRequests(
                fatherName: couple.husband.name,
                fatherPatronymic: couple.husband.patronymic,
                motherName: couple.wife.name,
                motherPatronymic: couple.wife.patronymic,
                startYear: window.startYear,
                endYear: window.endYear
            ) else {
                continue
            }

            summaries.append(contentsOf: requests.map { request in
                FamilyWorkup.HiskiQuerySummary(
                    coupleIndex: index,
                    label: request.label,
                    url: request.url.absoluteString,
                    startYear: window.startYear,
                    endYear: window.endYear,
                    sourceDescription: window.sourceDescription
                )
            })
        }

        return summaries
    }

    private func makeFamilySearchSummary(
        extraction: FamilySearchFamilyExtraction?,
        familySearchPersonId: String?
    ) -> FamilyWorkup.FamilySearchSummary {
        if let extraction {
            let status = extraction.isSuccessful
                ? "available"
                : "failed"
            return FamilyWorkup.FamilySearchSummary(
                anchorPersonId: extraction.parentFamilySearchId ?? extraction.sourcePersonId,
                extractionStatus: status,
                extractedChildCount: extraction.children.count,
                detailURL: familySearchPersonId.map(FamilySearchDOMService.detailsURL),
                note: extraction.failureReason
            )
        }

        return FamilyWorkup.FamilySearchSummary(
            anchorPersonId: familySearchPersonId,
            extractionStatus: familySearchPersonId == nil ? "no-anchor" : "not-extracted",
            extractedChildCount: 0,
            detailURL: familySearchPersonId.map(FamilySearchDOMService.detailsURL),
            note: familySearchPersonId == nil
                ? "No FamilySearch parent ID is available in this Juuret family."
                : "Run in-app FamilySearch WebKit extraction on the Mac running Kalvian Roots."
        )
    }

    private func makeComparisonSummary(
        _ result: FamilyComparisonResult,
        family: Family
    ) -> FamilyWorkup.ComparisonSummary {
        let coupleIndexByIdentity = makeCoupleIndexByJuuretIdentity(for: family)
        let displayRows = FamilyComparisonReviewDetector.displayRows(for: result.rows)
        let rows = displayRows.map { displayRow in
            let row = displayRow.match
            return FamilyWorkup.ComparisonRow(
                coupleIndex: coupleIndexByIdentity[comparisonIdentityKey(
                    identityName: row.identity.canonicalName,
                    birthDate: row.identity.birthDate
                )],
                identityName: row.identity.canonicalName,
                birthDate: formatDate(row.identity.birthDate),
                status: status(for: displayRow),
                familySearch: row.familySearch.map(makeCandidateSummary),
                juuret: row.juuretKalvialla.map(makeCandidateSummary),
                hiski: row.hiski.map(makeCandidateSummary),
                reviewNote: displayRow.reviewNote?.message
            )
        }

        return FamilyWorkup.ComparisonSummary(
            rowCount: rows.count,
            matchCount: result.matches.count,
            familySearchOnlyCount: result.familySearchOnly.count,
            juuretOnlyCount: result.juuretOnly.count,
            hiskiOnlyCount: result.hiskiOnly.count,
            rows: rows
        )
    }

    private func status(for row: FamilyComparisonDisplayRow) -> String {
        guard let reviewNote = row.reviewNote else {
            return comparisonService.status(for: row.match)
        }

        if reviewNote.message.localizedCaseInsensitiveContains("date discrepancy") {
            return "Review date discrepancy"
        }

        return "Review name discrepancy"
    }

    private func makeActions(
        familyId: String,
        familySearch: FamilyWorkup.FamilySearchSummary,
        comparison: FamilyWorkup.ComparisonSummary?
    ) -> [FamilyWorkup.ActionSummary] {
        var actions: [FamilyWorkup.ActionSummary] = []
        let hasFamilySearchExtraction = familySearch.extractionStatus == "available"

        if familySearch.extractionStatus == "not-extracted" || familySearch.extractionStatus == "failed" {
            actions.append(
                makeAction(
                    familyId: familyId,
                    type: "familysearch.extract",
                    label: "Run in-app FamilySearch WebKit extraction on the Mac.",
                    personName: nil,
                    personId: familySearch.anchorPersonId,
                    requiresApproval: false,
                    approvalPrompt: nil,
                    row: nil
                )
            )
        }

        for row in comparison?.rows ?? [] {
            if let juuret = row.juuret,
               let familySearchId = row.familySearch?.familySearchId {
                if let juuretFamilySearchId = juuret.familySearchId {
                    if juuretFamilySearchId != familySearchId {
                        actions.append(
                            makeAction(
                                familyId: familyId,
                                type: "review.familysearch-id-mismatch",
                                label: "Review conflicting FamilySearch IDs before changing source data.",
                                personName: juuret.name,
                                personId: familySearchId,
                                requiresApproval: true,
                                approvalPrompt: "Juuret has \(juuretFamilySearchId) for \(juuret.name), but FamilySearch extraction matched \(familySearchId). Which ID is correct?",
                                row: row
                            )
                        )
                    }
                } else {
                    actions.append(
                        makeAction(
                            familyId: familyId,
                            type: "source.update.familysearch-id",
                            label: "Propose adding this FamilySearch ID to the canonical Juuret source text.",
                            personName: juuret.name,
                            personId: familySearchId,
                            requiresApproval: true,
                            approvalPrompt: "Should I add \(familySearchId) to \(juuret.name) in the canonical Juuret source text?",
                            row: row
                        )
                    )
                }
            }

            switch row.status {
            case "Missing in FamilySearch":
                if hasFamilySearchExtraction {
                    actions.append(
                        makeAction(
                            familyId: familyId,
                            type: "familysearch.add-child",
                            label: "Review whether this Juuret/HisKi child should be added to FamilySearch.",
                            personName: row.juuret?.name ?? row.hiski?.name,
                            personId: nil,
                            requiresApproval: true,
                            approvalPrompt: nil,
                            row: row
                        )
                    )
                }
            case "Juuret-only":
                if hasFamilySearchExtraction {
                    actions.append(
                        makeAction(
                            familyId: familyId,
                            type: "citation.juuret",
                            label: "Prepare a Juuret citation for this person.",
                            personName: row.juuret?.name,
                            personId: row.juuret?.familySearchId,
                            requiresApproval: true,
                            approvalPrompt: nil,
                            row: row
                        )
                    )
                }
            case "HisKi-only":
                actions.append(
                    makeAction(
                        familyId: familyId,
                        type: "review.hiski-only",
                        label: "Review HisKi-only child before proposing FamilySearch changes.",
                        personName: row.hiski?.name,
                        personId: nil,
                        requiresApproval: true,
                        approvalPrompt: nil,
                        row: row
                    )
                )
            case "FamilySearch date needed":
                if hasFamilySearchExtraction {
                    actions.append(
                        makeAction(
                            familyId: familyId,
                            type: "familysearch.date-needed",
                            label: "Review FamilySearch date evidence for this child.",
                            personName: row.familySearch?.name,
                            personId: row.familySearch?.familySearchId,
                            requiresApproval: false,
                            approvalPrompt: nil,
                            row: row
                        )
                    )
                }
            default:
                if row.reviewNote != nil {
                    actions.append(
                        makeAction(
                            familyId: familyId,
                            type: "review.comparison",
                            label: "Review possible comparison discrepancy.",
                            personName: row.juuret?.name ?? row.familySearch?.name ?? row.hiski?.name,
                            personId: row.familySearch?.familySearchId,
                            requiresApproval: true,
                            approvalPrompt: nil,
                            row: row
                        )
                    )
                }
            }
        }

        return actions
    }

    private func makeAction(
        familyId: String,
        type: String,
        label: String,
        personName: String?,
        personId: String?,
        requiresApproval: Bool,
        approvalPrompt: String?,
        row: FamilyWorkup.ComparisonRow?
    ) -> FamilyWorkup.ActionSummary {
        FamilyWorkup.ActionSummary(
            id: actionId(
                familyId: familyId,
                type: type,
                row: row,
                personName: personName,
                personId: personId
            ),
            familyId: familyId,
            type: type,
            label: label,
            personName: personName,
            personId: personId,
            requiresApproval: requiresApproval,
            approvalPrompt: approvalPrompt,
            context: row.map {
                FamilyWorkup.ActionContext(
                    coupleIndex: $0.coupleIndex,
                    identityName: $0.identityName,
                    birthDate: $0.birthDate,
                    status: $0.status,
                    familySearch: $0.familySearch,
                    juuret: $0.juuret,
                    hiski: $0.hiski
                )
            }
        )
    }

    private func actionId(
        familyId: String,
        type: String,
        row: FamilyWorkup.ComparisonRow?,
        personName: String?,
        personId: String?
    ) -> String {
        [
            familyId,
            type,
            row?.coupleIndex.map(String.init),
            row?.identityName,
            row?.birthDate,
            personId,
            personName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: ":")
    }

    private func makePersonSummary(_ person: Person) -> FamilyWorkup.PersonSummary {
        FamilyWorkup.PersonSummary(
            name: person.name,
            displayName: person.displayName,
            birthDate: person.birthDate,
            deathDate: person.deathDate,
            familySearchId: person.familySearchId
        )
    }

    private func makeCandidateSummary(_ candidate: PersonCandidate) -> FamilyWorkup.CandidateSummary {
        FamilyWorkup.CandidateSummary(
            source: candidate.source.rawValue,
            name: candidate.rawName,
            birthDate: formatDate(candidate.birthDate),
            deathDate: formatDate(candidate.deathDate),
            familySearchId: candidate.familySearchId,
            hiskiCitation: candidate.hiskiCitation?.absoluteString
        )
    }

    private func formatDate(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        return displayDateFormatter.string(from: date)
    }

    private func makeCoupleIndexByJuuretIdentity(for family: Family) -> [String: Int] {
        var indexSetsByKey: [String: Set<Int>] = [:]

        for (index, couple) in family.couples.enumerated() {
            let candidates = comparisonService.makeJuuretCandidates(from: couple.children)
            for candidate in candidates {
                let key = comparisonIdentityKey(
                    identityName: candidate.identity.canonicalName,
                    birthDate: candidate.identity.birthDate
                )
                indexSetsByKey[key, default: []].insert(index)
            }
        }

        var result: [String: Int] = [:]
        for (key, indexes) in indexSetsByKey where indexes.count == 1 {
            result[key] = indexes.first
        }
        return result
    }

    private func comparisonIdentityKey(identityName: String, birthDate: Date?) -> String {
        [
            identityName,
            formatDate(birthDate) ?? ""
        ].joined(separator: "|")
    }
}
