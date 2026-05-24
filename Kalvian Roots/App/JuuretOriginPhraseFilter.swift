import Foundation

enum JuuretOriginPhraseFilter {
    private static let originPattern = #"(?i)(?:^|\s+)synt\.\s+[^,;\n.]+"#

    static func sanitized(_ network: FamilyNetwork) -> FamilyNetwork {
        var sanitizedNetwork = FamilyNetwork(mainFamily: sanitized(network.mainFamily))
        sanitizedNetwork.asChildFamilies = network.asChildFamilies.mapValues(sanitized)
        sanitizedNetwork.asParentFamilies = network.asParentFamilies.mapValues(sanitized)
        sanitizedNetwork.spouseAsChildFamilies = network.spouseAsChildFamilies.mapValues(sanitized)
        return sanitizedNetwork
    }

    static func sanitized(_ family: Family) -> Family {
        Family(
            familyId: family.familyId,
            pageReferences: family.pageReferences,
            couples: family.couples.map(sanitized),
            notes: sanitizedNotes(family.notes),
            noteDefinitions: sanitized(family.noteDefinitions)
        )
    }

    static func sanitizedNotes(_ notes: [String]) -> [String] {
        notes.compactMap(sanitizedField)
    }

    static func sanitized(_ noteDefinitions: [String: String]) -> [String: String] {
        noteDefinitions.reduce(into: [:]) { result, entry in
            guard let sanitizedText = sanitizedField(entry.value) else {
                return
            }

            result[entry.key] = sanitizedText
        }
    }

    static func sanitizedField(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let regex = try? NSRegularExpression(pattern: originPattern) else {
            return trimmed
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let cleaned = regex
            .stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty || cleaned.allSatisfy({ ".,;".contains($0) }) {
            return nil
        }

        return cleaned
    }

    private static func sanitized(_ couple: Couple) -> Couple {
        Couple(
            husband: sanitized(couple.husband),
            wife: sanitized(couple.wife),
            marriageDate: couple.marriageDate,
            fullMarriageDate: couple.fullMarriageDate,
            children: couple.children.map(sanitized),
            childrenDiedInfancy: couple.childrenDiedInfancy,
            coupleNotes: sanitizedNotes(couple.coupleNotes)
        )
    }

    private static func sanitized(_ person: Person) -> Person {
        Person(
            name: person.name,
            patronymic: person.patronymic,
            birthDate: person.birthDate,
            deathDate: sanitizedField(person.deathDate),
            marriageDate: person.marriageDate,
            fullMarriageDate: person.fullMarriageDate,
            spouse: sanitizedField(person.spouse),
            asChild: sanitizedField(person.asChild),
            asParent: sanitizedField(person.asParent),
            familySearchId: person.familySearchId,
            noteMarkers: person.noteMarkers,
            fatherName: person.fatherName,
            motherName: person.motherName,
            spouseBirthDate: person.spouseBirthDate,
            spouseParentsFamilyId: person.spouseParentsFamilyId
        )
    }

}
