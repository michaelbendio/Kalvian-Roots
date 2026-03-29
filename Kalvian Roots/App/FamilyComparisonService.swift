import Foundation

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

    func compare(
        juuretCandidates: [PersonCandidate],
        hiskiCandidates: [PersonCandidate]
    ) -> FamilyComparisonResult {
        FamilyComparisonResult(
            familySearch: [],
            juuretKalvialla: juuretCandidates,
            hiski: hiskiCandidates
        )
    }

    func renderJuuretHiskiReport(_ result: FamilyComparisonResult) -> String {
        [
            renderReportSection(title: "Matches", items: result.matches.map(renderMatchLine)),
            renderReportSection(title: "Juuret only", items: result.juuretOnly.map(renderCandidateLine)),
            renderReportSection(title: "HisKi only", items: result.hiskiOnly.map(renderCandidateLine))
        ].joined(separator: "\n\n")
    }
}

private extension FamilyComparisonService {

    func makeFamilySearchCandidate(from person: Person) -> PersonCandidate {
        PersonCandidate(
            name: person.name,
            birthDate: parseGenealogyDate(person.birthDate),
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

    func parseGenealogyDate(_ rawDate: String?) -> Date? {
        guard let rawDate else {
            return nil
        }

        let trimmed = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let fullDateFormats = ["d.M.yyyy", "dd.MM.yyyy"]

        for format in fullDateFormats {
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

    func renderReportSection(title: String, items: [String]) -> String {
        let body = items.isEmpty ? ["(none)"] : items
        return ([title, String(repeating: "-", count: title.count)] + body).joined(separator: "\n")
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
