//
//  FamilyTokenizer.swift
//  Kalvian Roots
//
//  Tokenizes family data for HTML rendering with clickable elements
//

#if os(macOS)
import Foundation

/**
 * Token types for family display rendering
 */
enum FamilyToken {
    case text(String)
    case person(name: String, birthDate: String?)
    case date(String, eventType: EventType, person: Person?, spouse1: Person?, spouse2: Person?)
    case familyId(String)
    case enhanced(String)
    case symbol(String)
    case lineBreak
    case sectionHeader(String)
}

/**
 * Tokenizes family data for HTML rendering
 */
struct FamilyTokenizer {

    /**
     * Tokenize a family for HTML display
     */
    func tokenizeFamily(family: Family, network: FamilyNetwork?) -> [FamilyToken] {
        var tokens: [FamilyToken] = []

        // Family header
        tokens.append(.sectionHeader(family.familyId))
        tokens.append(.text("Pages: \(family.pageReferences.joined(separator: ", "))"))
        tokens.append(.lineBreak)
        tokens.append(.lineBreak)

        // Primary couple (parents)
        if let couple = family.primaryCouple {
            tokens.append(contentsOf: tokenizeCouple(couple: couple, family: family, network: network, isAdditional: false))
        }

        // Additional couples
        if family.couples.count > 1 {
            for (index, couple) in family.couples.dropFirst().enumerated() {
                let spouseNumber = index + 2
                tokens.append(.lineBreak)
                tokens.append(.sectionHeader("\(romanNumeral(spouseNumber)) puoliso"))
                tokens.append(contentsOf: tokenizeCouple(couple: couple, family: family, network: network, isAdditional: true))
            }
        }

        // Family notes
        if !family.notes.isEmpty {
            tokens.append(.lineBreak)
            tokens.append(.sectionHeader("Notes"))
            for note in family.notes {
                tokens.append(.text(note))
                tokens.append(.lineBreak)
            }
        }

        return tokens
    }

    // MARK: - Couple Tokenization

    private func tokenizeCouple(couple: Couple, family: Family, network: FamilyNetwork?, isAdditional: Bool) -> [FamilyToken] {
        var tokens: [FamilyToken] = []

        // Father/Husband (only for primary couple)
        if !isAdditional {
            tokens.append(contentsOf: tokenizePerson(person: couple.husband, symbol: "★", family: family, network: network))
            tokens.append(.lineBreak)
        }

        // Mother/Wife
        tokens.append(contentsOf: tokenizePerson(person: couple.wife, symbol: "★", family: family, network: network))
        tokens.append(.lineBreak)

        // Marriage date
        if let marriageDate = couple.fullMarriageDate ?? couple.marriageDate {
            let displayDate = displayMarriageDate(
                marriageDate,
                parentBirthYear: CitationGenerator.extractBirthYear(from: couple.husband)
                    ?? CitationGenerator.extractBirthYear(from: couple.wife)
            )
            tokens.append(.symbol("∞"))
            tokens.append(.text(" "))
            tokens.append(.date(displayDate, eventType: .marriage, person: nil,
                              spouse1: couple.husband, spouse2: couple.wife))
            tokens.append(.lineBreak)
        }

        // Children header
        if !couple.children.isEmpty {
            tokens.append(.lineBreak)
            tokens.append(.sectionHeader("Lapset"))

            // Children
            for child in couple.children {
                tokens.append(contentsOf: tokenizeChild(child: child, couple: couple, family: family, network: network))
                tokens.append(.lineBreak)
            }
        }

        // Children died in infancy
        if let childrenDied = couple.childrenDiedInfancy, childrenDied > 0 {
            tokens.append(.text("Lapsena kuollut \(childrenDied)."))
            tokens.append(.lineBreak)
        }

        return tokens
    }

    // MARK: - Person Tokenization

    private func tokenizePerson(person: Person, symbol: String, family: Family, network: FamilyNetwork?) -> [FamilyToken] {
        var tokens: [FamilyToken] = []

        // Birth symbol and date
        tokens.append(.symbol(symbol))
        tokens.append(.text(" "))

        if let birthDate = person.birthDate {
            tokens.append(.date(birthDate, eventType: .birth, person: person, spouse1: nil, spouse2: nil))
            tokens.append(.text(" "))
        }

        // Name (clickable)
        tokens.append(.person(name: person.name, birthDate: person.birthDate))

        // FamilySearch ID
        if let fsId = person.familySearchId {
            tokens.append(.text(" <\(fsId)>"))
        }

        // Death date if present
        if let deathDate = person.deathDate {
            tokens.append(.text(" "))
            tokens.append(.symbol("†"))
            tokens.append(.text(" "))
            tokens.append(.date(deathDate, eventType: .death, person: person, spouse1: nil, spouse2: nil))
        }

        // asChild family reference
        if let asChild = person.asChild {
            tokens.append(.text(" as_child "))
            tokens.append(.familyId(asChild))
        }

        return tokens
    }

    private func tokenizeChild(child: Person, couple: Couple, family: Family, network: FamilyNetwork?) -> [FamilyToken] {
        var tokens: [FamilyToken] = []
        let childWithParents = child.withHiskiParentNames(
            father: couple.husband.displayName,
            mother: couple.wife.displayName
        )

        // Birth symbol and date
        tokens.append(.symbol("★"))
        tokens.append(.text(" "))

        if let birthDate = childWithParents.birthDate {
            tokens.append(.date(birthDate, eventType: .birth, person: childWithParents, spouse1: nil, spouse2: nil))
            tokens.append(.text(" "))
        }

        // Name (clickable)
        tokens.append(.person(name: childWithParents.name, birthDate: childWithParents.birthDate))

        // Enhanced death date from asParent family
        if let network = network,
           let asParentFamily = network.getAsParentFamily(for: childWithParents),
           let deathDate = findDeathDate(for: childWithParents, in: asParentFamily) {
            tokens.append(.text(" ["))
            tokens.append(.symbol("†"))
            tokens.append(.text(" "))
            tokens.append(.enhanced(deathDate))
            tokens.append(.text("]"))
        }

        // Marriage info
        if let marriageDate = childWithParents.fullMarriageDate ?? childWithParents.marriageDate {
            let displayDate = displayMarriageDate(
                marriageDate,
                parentBirthYear: CitationGenerator.extractBirthYear(from: childWithParents)
            )
            tokens.append(.text(" "))
            tokens.append(.symbol("∞"))
            tokens.append(.text(" "))

            // For child's marriage, we need to find their spouse
            if let spouse = childWithParents.spouse {
                // Create temporary Person objects for the marriage link
                let childPerson = childWithParents
                let spousePerson = Person(name: spouse, noteMarkers: [])
                tokens.append(.date(displayDate, eventType: .marriage, person: nil,
                                    spouse1: childPerson, spouse2: spousePerson))
            } else {
                tokens.append(.text(displayDate))
            }
        }

        // Spouse name (clickable)
        if let spouse = childWithParents.spouse {
            tokens.append(.text(" "))
            tokens.append(.person(name: spouse, birthDate: nil))

            if !childWithParents.noteMarkers.isEmpty {
                tokens.append(.text(" "))
                tokens.append(.text(childWithParents.noteMarkers.map(displayFootnoteMarker).joined(separator: " ")))
            }

            if let familySearchId = spouseFamilySearchId(for: childWithParents, network: network) {
                tokens.append(.text(" <\(familySearchId)>"))
            }
        }

        // asParent family reference
        if let asParent = childWithParents.asParent {
            tokens.append(.text(" as_parent "))
            tokens.append(.familyId(asParent))
        }

        if childWithParents.spouse == nil && !childWithParents.noteMarkers.isEmpty {
            tokens.append(.text(" "))
            tokens.append(.text(childWithParents.noteMarkers.map(displayFootnoteMarker).joined(separator: " ")))
        }

        return tokens
    }

    // MARK: - Helper Functions

    private func findDeathDate(for person: Person, in family: Family) -> String? {
        // Look for death date in the asParent family
        for parent in family.allParents {
            if parent.name == person.name && parent.birthDate == person.birthDate {
                return parent.deathDate
            }
        }
        return nil
    }

    private func spouseFamilySearchId(for person: Person, network: FamilyNetwork?) -> String? {
        guard let network,
              person.isMarried,
              let spouseName = person.spouse,
              let asParentFamily = network.getAsParentFamily(for: person) else {
            return nil
        }

        let spouseNameLower = spouseName.lowercased()
        guard let spouseInFamily = asParentFamily.allParents.first(where: {
            $0.name.lowercased().contains(spouseNameLower) || spouseNameLower.contains($0.name.lowercased())
        }) else {
            return nil
        }

        let spouseForLookup = Person(name: spouseInFamily.name, birthDate: spouseInFamily.birthDate, noteMarkers: [])
        guard let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spouseForLookup),
              let spouseAsChild = spouseAsChildFamily.allChildren.first(where: {
                  $0.name.lowercased() == spouseInFamily.name.lowercased() || $0.birthDate == spouseInFamily.birthDate
              }) else {
            return spouseInFamily.familySearchId
        }

        return spouseAsChild.familySearchId ?? spouseInFamily.familySearchId
    }

    private func romanNumeral(_ number: Int) -> String {
        switch number {
        case 1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        case 5: return "V"
        case 6: return "VI"
        case 7: return "VII"
        case 8: return "VIII"
        case 9: return "IX"
        case 10: return "X"
        default: return String(number)
        }
    }

    private func displayMarriageDate(_ date: String, parentBirthYear: Int?) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains(".") {
            let components = trimmed.components(separatedBy: ".")
            if components.count == 3,
               components[2].count == 2,
               let twoDigitYear = Int(components[2]) {
                let fullYear = CitationGenerator.inferCentury(
                    for: twoDigitYear,
                    parentBirthYear: parentBirthYear
                )
                return "\(components[0]).\(components[1]).\(fullYear)"
            }
        }

        if trimmed.count == 2, let twoDigitYear = Int(trimmed) {
            return String(CitationGenerator.inferCentury(
                for: twoDigitYear,
                parentBirthYear: parentBirthYear
            ))
        }

        return trimmed
    }
}

#endif // os(macOS)
