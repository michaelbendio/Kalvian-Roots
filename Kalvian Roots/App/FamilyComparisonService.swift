import Foundation

final class FamilyComparisonService {

    private let nameManager: NameEquivalenceManager
    private let genealogyCalendar = Calendar(identifier: .gregorian)

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
}
