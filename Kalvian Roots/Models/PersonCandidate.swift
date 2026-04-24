/**
 PersonCandidate

 Represents a person as observed in a specific source.

 Sources include:
 - FamilySearch
 - Juuret Kälviällä
 - HisKi parish records

 A candidate wraps a PersonIdentity and carries source-specific
 information used for comparison and citation generation.
 */

import Foundation

struct PersonCandidate: Hashable, CustomStringConvertible {

    // MARK: - Source Type

    enum SourceType: String, Codable, CustomStringConvertible, CustomDebugStringConvertible {
        case familySearch
        case juuretKalvialla
        case hiski

        var description: String { rawValue }
        var debugDescription: String { rawValue }
    }
    
    // MARK: - Core Identity

    let identity: PersonIdentity

    // MARK: - Raw Source Data

    let source: SourceType
    let rawName: String
    let birthDate: Date?
    let deathDate: Date?

    // MARK: - Source Identifiers

    let familySearchId: String?
    let hiskiCitation: URL?

    // MARK: - Initialization

    init(
        name: String,
        identityName: String? = nil,
        birthDate: Date?,
        deathDate: Date? = nil,
        source: SourceType,
        nameManager: NameEquivalenceManager,
        familySearchId: String? = nil,
        hiskiCitation: URL? = nil
    ) {

        self.identity = PersonIdentity(
            name: identityName ?? name,
            birthDate: birthDate,
            nameManager: nameManager
        )

        self.rawName = name
        self.birthDate = birthDate
        self.deathDate = deathDate
        self.source = source
        self.familySearchId = familySearchId
        self.hiskiCitation = hiskiCitation
    }

    // MARK: - Convenience Flags

    var isFromFamilySearch: Bool {
        source == .familySearch
    }

    var isFromJuuret: Bool {
        source == .juuretKalvialla
    }

    var isFromHiski: Bool {
        source == .hiski
    }

    // MARK: - Debugging

    var description: String {

        var parts: [String] = []

        parts.append(rawName)

        if let birthDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM yyyy"
            parts.append(formatter.string(from: birthDate))
        }

        parts.append("[\(source.rawValue)]")

        return parts.joined(separator: " ")
    }
}
