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
        let type: String
        let label: String
        let personName: String?
        let personId: String?
        let requiresApproval: Bool
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
        let comparison = comparisonResult.map(makeComparisonSummary)
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

    private func makeComparisonSummary(_ result: FamilyComparisonResult) -> FamilyWorkup.ComparisonSummary {
        let reviewNotes = FamilyComparisonReviewDetector.notes(for: result.rows)
        let rows = result.rows.enumerated().map { index, row in
            FamilyWorkup.ComparisonRow(
                identityName: row.identity.canonicalName,
                birthDate: formatDate(row.identity.birthDate),
                status: comparisonService.status(for: row),
                familySearch: row.familySearch.map(makeCandidateSummary),
                juuret: row.juuretKalvialla.map(makeCandidateSummary),
                hiski: row.hiski.map(makeCandidateSummary),
                reviewNote: reviewNotes[index]?.message
            )
        }

        return FamilyWorkup.ComparisonSummary(
            rowCount: result.rows.count,
            matchCount: result.matches.count,
            familySearchOnlyCount: result.familySearchOnly.count,
            juuretOnlyCount: result.juuretOnly.count,
            hiskiOnlyCount: result.hiskiOnly.count,
            rows: rows
        )
    }

    private func makeActions(
        familySearch: FamilyWorkup.FamilySearchSummary,
        comparison: FamilyWorkup.ComparisonSummary?
    ) -> [FamilyWorkup.ActionSummary] {
        var actions: [FamilyWorkup.ActionSummary] = []
        let hasFamilySearchExtraction = familySearch.extractionStatus == "available"

        if familySearch.extractionStatus == "not-extracted" {
            actions.append(
                FamilyWorkup.ActionSummary(
                    type: "familysearch.extract",
                    label: "Run in-app FamilySearch WebKit extraction on the Mac.",
                    personName: nil,
                    personId: familySearch.anchorPersonId,
                    requiresApproval: false
                )
            )
        }

        for row in comparison?.rows ?? [] {
            switch row.status {
            case "Missing in FamilySearch":
                if hasFamilySearchExtraction {
                    actions.append(
                        FamilyWorkup.ActionSummary(
                            type: "familysearch.add-child",
                            label: "Review whether this Juuret/HisKi child should be added to FamilySearch.",
                            personName: row.juuret?.name ?? row.hiski?.name,
                            personId: nil,
                            requiresApproval: true
                        )
                    )
                }
            case "Juuret-only":
                if hasFamilySearchExtraction {
                    actions.append(
                        FamilyWorkup.ActionSummary(
                            type: "citation.juuret",
                            label: "Prepare a Juuret citation for this person.",
                            personName: row.juuret?.name,
                            personId: row.juuret?.familySearchId,
                            requiresApproval: true
                        )
                    )
                }
            case "HisKi-only":
                actions.append(
                    FamilyWorkup.ActionSummary(
                        type: "review.hiski-only",
                        label: "Review HisKi-only child before proposing FamilySearch changes.",
                        personName: row.hiski?.name,
                        personId: nil,
                        requiresApproval: true
                    )
                )
            case "FamilySearch date needed":
                if hasFamilySearchExtraction {
                    actions.append(
                        FamilyWorkup.ActionSummary(
                            type: "familysearch.date-needed",
                            label: "Review FamilySearch date evidence for this child.",
                            personName: row.familySearch?.name,
                            personId: row.familySearch?.familySearchId,
                            requiresApproval: false
                        )
                    )
                }
            default:
                if row.reviewNote != nil {
                    actions.append(
                        FamilyWorkup.ActionSummary(
                            type: "review.comparison",
                            label: "Review possible comparison discrepancy.",
                            personName: row.juuret?.name ?? row.familySearch?.name ?? row.hiski?.name,
                            personId: row.familySearch?.familySearchId,
                            requiresApproval: true
                        )
                    )
                }
            }
        }

        return actions
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
}
