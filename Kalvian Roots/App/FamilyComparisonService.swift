import Foundation

struct HiskiCitationProposal: Equatable {
    let identity: PersonIdentity
    let displayName: String
    let birthDate: Date?
    let juuretName: String?
    let hiskiName: String?
    let citationURL: URL

    func shortCitationString(from url: URL) -> String {
        url.absoluteString.replacingOccurrences(of: "https://", with: "")
    }
}

final class FamilyComparisonService {

    private let nameManager: NameEquivalenceManager
    private let genealogyCalendar = Calendar(identifier: .gregorian)
    private let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
    private let familySearchDateFormats = [
        "d.M.yyyy",
        "dd.MM.yyyy",
        "d MMM yyyy",
        "dd MMM yyyy",
        "d MMMM yyyy",
        "dd MMMM yyyy",
        "MMM yyyy",
        "MMMM yyyy",
        "yyyy"
    ]

    init(nameManager: NameEquivalenceManager) {
        self.nameManager = nameManager
    }

    // MARK: - Public API

    func compare(
        familySearchChildren: [Person],
        juuretChildren: [Person],
        hiskiCitations: [HiskiCitation]
    ) -> FamilyComparisonResult {

        let fsCandidates = familySearchChildren.map {
            makeFamilySearchCandidate(from: $0)
        }

        let jkCandidates = juuretChildren.map {
            makeJuuretCandidate(from: $0)
        }

        let hiskiCandidates = hiskiCitations.map {
            makeHiskiCandidate(from: $0)
        }

        return FamilyComparisonResult(
            familySearch: fsCandidates,
            juuretKalvialla: jkCandidates,
            hiski: hiskiCandidates
        )
    }

    func makeHiskiCandidates(from events: [HiskiService.HiskiFamilyBirthEvent]) -> [PersonCandidate] {
        events.map {
            makeHiskiCandidate(from: $0)
        }
    }

    func makeHiskiCandidates(from rows: [HiskiService.HiskiFamilyBirthRow]) -> [PersonCandidate] {
        rows.map {
            makeHiskiCandidate(from: $0)
        }
    }

    func makeJuuretCandidates(from people: [Person]) -> [PersonCandidate] {
        people.map {
            makeJuuretCandidate(from: $0)
        }
    }

    func makeFamilySearchCandidates(from children: [FamilySearchChild]) -> [PersonCandidate] {
        FamilySearchDOMService.makePersonCandidates(
            from: children,
            nameManager: nameManager,
            dateParser: parseGenealogyDate
        )
    }

    func compareChildren(
        juuretChildren: [Person],
        hiskiChildren: [HiskiService.HiskiFamilyBirthEvent],
        familySearchChildren: [FamilySearchChild]
    ) -> FamilyComparisonResult {
        compare(
            juuretCandidates: makeJuuretCandidates(from: juuretChildren),
            hiskiCandidates: makeHiskiCandidates(from: hiskiChildren),
            familySearchCandidates: makeFamilySearchCandidates(from: familySearchChildren)
        )
    }

    func compareChildren(
        juuretChildren: [Person],
        hiskiRows: [HiskiService.HiskiFamilyBirthRow],
        familySearchChildren: [FamilySearchChild]
    ) -> FamilyComparisonResult {
        compare(
            juuretCandidates: makeJuuretCandidates(from: juuretChildren),
            hiskiCandidates: makeHiskiCandidates(from: hiskiRows),
            familySearchCandidates: makeFamilySearchCandidates(from: familySearchChildren)
        )
    }

    func compareChildren(
        _ juuretChildren: [Person],
        _ hiskiChildren: [HiskiService.HiskiFamilyBirthEvent],
        _ familySearchChildren: [FamilySearchChild]
    ) -> FamilyComparisonResult {
        compareChildren(
            juuretChildren: juuretChildren,
            hiskiChildren: hiskiChildren,
            familySearchChildren: familySearchChildren
        )
    }

    func compare(
        juuretCandidates: [PersonCandidate],
        hiskiCandidates: [PersonCandidate],
        familySearchCandidates: [PersonCandidate] = []
    ) -> FamilyComparisonResult {
        FamilyComparisonResult(
            familySearch: familySearchCandidates,
            juuretKalvialla: juuretCandidates,
            hiski: hiskiCandidates
        )
    }

    func status(for match: FamilyComparisonResult.Match) -> String {
        switch (match.juuretKalvialla, match.hiski, match.familySearch) {
        case (.some, .some, .some):
            return hasNameMismatch(match) ? "Name mismatch" : "Present in all three"
        case (.some, .some, nil):
            return "Missing in FamilySearch"
        case (.some, nil, nil):
            return "Juuret-only"
        case (nil, .some, nil):
            return "HisKi-only"
        case (nil, nil, .some(let familySearch)):
            return familySearch.birthDate == nil
                ? "FamilySearch date needed"
                : "FamilySearch-only"
        case (.some, nil, .some):
            return hasNameMismatch(match) ? "Name mismatch" : "Missing in HisKi"
        case (nil, .some, .some):
            return hasNameMismatch(match) ? "Name mismatch" : "Missing in Juuret"
        case (nil, nil, nil):
            return "Unknown"
        }
    }

    func renderJuuretHiskiReport(_ result: FamilyComparisonResult) -> String {
        let juuretHiskiMatches = result.matches.filter(isJuuretHiskiMatch)

        return [
            renderReportSection(title: "Matches", items: juuretHiskiMatches.map(renderMatchLine)),
            renderReportSection(title: "Juuret only", items: result.juuretOnly.map(renderCandidateLine)),
            renderReportSection(title: "HisKi only", items: result.hiskiOnly.map(renderCandidateLine))
        ].joined(separator: "\n\n")
    }

    func makeHiskiCitationProposals(from result: FamilyComparisonResult) -> [HiskiCitationProposal] {
        result.matches.compactMap(makeHiskiCitationProposal)
    }

    func renderHiskiCitationProposals(_ proposals: [HiskiCitationProposal]) -> String {
        let title = "HisKi Citation Proposals"

        guard !proposals.isEmpty else {
            return [title, String(repeating: "-", count: title.count), "(none)"]
                .joined(separator: "\n")
        }

        return ([title, String(repeating: "-", count: title.count)] + proposals.map(renderProposalBlock))
            .joined(separator: "\n\n")
    }
}

private extension FamilyComparisonService {

    func isJuuretHiskiMatch(_ match: FamilyComparisonResult.Match) -> Bool {
        match.juuretKalvialla != nil && match.hiski != nil
    }

    func makeFamilySearchCandidate(from person: Person) -> PersonCandidate {
        PersonCandidate(
            name: person.name,
            birthDate: parseGenealogyDate(person.birthDate),
            deathDate: parseGenealogyDate(person.deathDate),
            source: .familySearch,
            nameManager: nameManager,
            familySearchId: person.familySearchId,
            hiskiCitation: nil
        )
    }

    func makeJuuretCandidate(from person: Person) -> PersonCandidate {
        PersonCandidate(
            name: person.name,
            birthDate: parseGenealogyDate(person.birthDate),
            source: .juuretKalvialla,
            nameManager: nameManager,
            familySearchId: nil,
            hiskiCitation: nil
        )
    }

    func makeHiskiCandidate(from citation: HiskiCitation) -> PersonCandidate {
        PersonCandidate(
            name: citation.personName,
            birthDate: parseGenealogyDate(citation.date),
            source: .hiski,
            nameManager: nameManager,
            familySearchId: nil,
            hiskiCitation: URL(string: citation.url)
        )
    }

    func makeHiskiCandidate(from event: HiskiService.HiskiFamilyBirthEvent) -> PersonCandidate {
        PersonCandidate(
            name: event.childName,
            birthDate: parseGenealogyDate(event.birthDate),
            source: .hiski,
            nameManager: nameManager,
            familySearchId: nil,
            hiskiCitation: URL(string: event.citationURL)
        )
    }

    func makeHiskiCandidate(from row: HiskiService.HiskiFamilyBirthRow) -> PersonCandidate {
        PersonCandidate(
            name: row.childName,
            birthDate: parseGenealogyDate(row.birthDate),
            source: .hiski,
            nameManager: nameManager,
            familySearchId: nil,
            hiskiCitation: nil
        )
    }

    func parseGenealogyDate(_ rawDate: String?) -> Date? {
        guard let rawDate else {
            return nil
        }

        let trimmed = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        for format in familySearchDateFormats {
            let formatter = DateFormatter()
            formatter.calendar = genealogyCalendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = format

            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    func hasNameMismatch(_ match: FamilyComparisonResult.Match) -> Bool {
        let canonicalNames = [
            match.juuretKalvialla?.identity.canonicalName,
            match.hiski?.identity.canonicalName,
            match.familySearch?.identity.canonicalName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Set(canonicalNames).count > 1
    }

    func renderReportSection(title: String, items: [String]) -> String {
        let body = items.isEmpty ? ["(none)"] : items
        return ([title, String(repeating: "-", count: title.count)] + body).joined(separator: "\n")
    }

    func makeHiskiCitationProposal(from match: FamilyComparisonResult.Match) -> HiskiCitationProposal? {
        guard
            let hiski = match.hiski,
            let citationURL = hiski.hiskiCitation
        else {
            return nil
        }

        return HiskiCitationProposal(
            identity: match.identity,
            displayName: makeProposalDisplayName(
                juuretName: match.juuretKalvialla?.rawName,
                hiskiName: hiski.rawName
            ),
            birthDate: match.identity.birthDate,
            juuretName: match.juuretKalvialla?.rawName,
            hiskiName: hiski.rawName,
            citationURL: citationURL
        )
    }

    func makeProposalDisplayName(juuretName: String?, hiskiName: String) -> String {
        guard let juuretName else {
            return hiskiName
        }

        if juuretName == hiskiName {
            return juuretName
        }

        return "\(juuretName) / \(hiskiName)"
    }

    func renderProposalBlock(_ proposal: HiskiCitationProposal) -> String {
        "\(proposal.displayName) — \(proposal.shortCitationString(from: proposal.citationURL))"
    }

    func renderMatchLine(_ match: FamilyComparisonResult.Match) -> String {
        let juuretName = match.juuretKalvialla?.rawName
        let hiskiName = match.hiski?.rawName

        let displayName: String
        switch (juuretName, hiskiName) {
        case let (juuret?, hiski?) where juuret != hiski:
            displayName = "\(juuret) / \(hiski)"
        case let (juuret?, _):
            displayName = juuret
        case let (_, hiski?):
            displayName = hiski
        default:
            displayName = "(unknown)"
        }

        return "\(displayName) — \(formatReportDate(match.identity.birthDate))"
    }

    func renderCandidateLine(_ candidate: PersonCandidate) -> String {
        "\(candidate.rawName) — \(formatReportDate(candidate.birthDate))"
    }

    func formatReportDate(_ date: Date?) -> String {
        guard let date else {
            return "unknown birth"
        }

        return reportDateFormatter.string(from: date)
    }
}
