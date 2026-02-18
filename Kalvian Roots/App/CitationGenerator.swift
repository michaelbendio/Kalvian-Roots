//
//  CitationGenerator.swift
//  Kalvian Roots
//
//  Citation Generator
//

import Foundation

/**
 * Citation Generator for Finnish Genealogical Records
 *
 * Generates citations for:
 * - Main family (nuclear family with parents + children)
 * - As-child (person appearing as child in their parents' family)
 * - Spouse as-child (spouse in their parents' family)
 *
 * Date Handling:
 * - Approximate dates (n yyyy) formatted as "abt yyyy"
 * - Smart century inference for 2-digit years using parent birth dates
 * - Full 8-digit dates preferred over 2-digit dates
 */
struct CitationGenerator {
    
    // MARK: - Public Citation Methods
    
    /**
     * Generate main family citation (nuclear family)
     */
    static func generateMainFamilyCitation(
        family: Family,
        targetPerson: Person? = nil,
        network: FamilyNetwork? = nil,
        nameEquivalenceManager: NameEquivalenceManager? = nil
    ) -> String {
        return generateFamilyCitation(
            family: family,
            targetPerson: targetPerson,
            network: network,
            nameEquivalenceManager: nameEquivalenceManager,
            citationType: .main
        )
    }
    
    /**
     * Generate as-child citation (person in their parents' family)
     */
    static func generateAsChildCitation(
        for person: Person,
        in asChildFamily: Family,
        network: FamilyNetwork? = nil,
        nameEquivalenceManager: NameEquivalenceManager? = nil
    ) -> String {
        return generateFamilyCitation(
            family: asChildFamily,
            targetPerson: person,
            network: network,
            nameEquivalenceManager: nameEquivalenceManager,
            citationType: .asChild
        )
    }
    
    /**
     * Generate spouse as-child citation (spouse in their parents' family)
     */
    static func generateSpouseAsChildCitation(
        spouseName: String,
        in spouseAsChildFamily: Family
    ) -> String {
        let spousePerson = Person(name: spouseName, noteMarkers: [])
        return generateAsChildCitation(for: spousePerson, in: spouseAsChildFamily)
    }
    
    // MARK: - Citation Type
    
    private enum CitationType {
        case main      // Nuclear family citation
        case asChild   // Person as child in parents' family
    }
    
    // MARK: - Unified Citation Generator
    
    private static func generateFamilyCitation(
        family: Family,
        targetPerson: Person?,
        network: FamilyNetwork?,
        nameEquivalenceManager: NameEquivalenceManager?,
        citationType: CitationType
    ) -> String {
        var citation = "Information on \(family.pageReferenceString) includes:\n"
        var enhancementSources: [EnhancementSource] = []
        var targetChildInFamily: Person? = nil
        
        // Format parents and marriage
        if let primaryCouple = family.primaryCouple {
            citation += formatParentsSection(
                couple: primaryCouple,
                targetPerson: targetPerson,
                nameEquivalenceManager: nameEquivalenceManager
            )
        }
        
        // Format children for all couples
        for couple in family.couples {
            if !couple.children.isEmpty {
                citation += "Children:\n"
                
                for child in couple.children {
                    let isTarget = targetPerson.map { isTargetPerson(child, $0, nameEquivalenceManager: nameEquivalenceManager) } ?? false
                    
                    if isTarget {
                        targetChildInFamily = child
                    }
                    
                    let childLine = formatChildLine(
                        child: child,
                        isTarget: isTarget,
                        targetPerson: targetPerson,
                        network: network,
                        enhancementSources: &enhancementSources
                    )
                    citation += childLine
                }
            }
            
            // Additional spouse section
            if couple != family.primaryCouple {
                citation += formatAdditionalSpouseSection(couple: couple, family: family)
            }
        }
        
        // Notes section
        citation += formatNotesSection(family: family)
        
        // Additional information section (enhancement sources)
        if citationType == .asChild, let target = targetPerson, let targetChild = targetChildInFamily {
            citation += formatAsChildEnhancementInfo(
                person: target,
                targetChild: targetChild,
                network: network
            )
        } else if !enhancementSources.isEmpty {
            citation += formatEnhancementSourcesSection(sources: enhancementSources)
        }
        
        return citation
    }
    
    // MARK: - Section Formatters
    
    private static func formatParentsSection(
        couple: Couple,
        targetPerson: Person?,
        nameEquivalenceManager: NameEquivalenceManager?
    ) -> String {
        var section = ""
        
        // Check if husband is target
        let husbandIsTarget = targetPerson.map { isTargetParent(couple.husband, $0) } ?? false
        let husbandPrefix = husbandIsTarget ? "→ " : ""
        section += husbandPrefix + formatParentCompact(couple.husband) + "\n"
        
        // Check if wife is target
        let wifeIsTarget = targetPerson.map { isTargetParent(couple.wife, $0) } ?? false
        let wifePrefix = wifeIsTarget ? "→ " : ""
        section += wifePrefix + formatParentCompact(couple.wife) + "\n"
        
        // Marriage date formatting...
        if let fullMarriageDate = couple.fullMarriageDate {
            section += "m. \(formatDate(fullMarriageDate))\n"
        } else if let marriageDate = couple.marriageDate {
            let parentBirthYear = extractBirthYear(from: couple.husband)
                                ?? extractBirthYear(from: couple.wife)
            section += "m. \(extractMarriageYear(marriageDate, parentBirthYear: parentBirthYear))\n"
        }
        
        return section
    }

    // Similar logic to isTargetPerson but for parents
    private static func isTargetParent(_ parent: Person, _ target: Person) -> Bool {
        // If both have birth dates, they must match
        if let parentBirth = parent.birthDate?.trimmingCharacters(in: .whitespaces),
           let targetBirth = target.birthDate?.trimmingCharacters(in: .whitespaces),
           !parentBirth.isEmpty && !targetBirth.isEmpty {
            if parentBirth == targetBirth {
                return true
            }
            // Year comparison for "1730" vs "dd.mm.1730"
            let parentYear = extractBirthYear(from: parent)
            let targetYear = extractBirthYear(from: target)
            if let py = parentYear, let ty = targetYear {
                return py == ty
            }
            return false
        }
        
        // Fall back to name matching
        return parent.name.lowercased().trimmingCharacters(in: .whitespaces) ==
               target.name.lowercased().trimmingCharacters(in: .whitespaces)
    }
    
    private static func formatChildLine(
        child: Person,
        isTarget: Bool,
        targetPerson: Person?,
        network: FamilyNetwork?,
        enhancementSources: inout [EnhancementSource]
    ) -> String {
        let person = targetPerson ?? child
        let shouldEnhance = shouldEnhanceChild(child, isTarget: isTarget, person: person, network: network)
        let prefix = isTarget ? "→ " : ""
        
        if shouldEnhance, let network = network {
            // Track enhancement source
            if let asParentFamily = network.getAsParentFamily(for: person),
               let enhancementInfo = trackEnhancement(nuclearChild: child, person: person, asParentFamily: asParentFamily) {
                enhancementSources.append(enhancementInfo)
            }
            return "\(prefix)\(formatChildWithEnhancement(child, person: person, network: network))"
        } else {
            return "\(prefix)\(formatChild(child))"
        }
    }
    
    private static func formatAdditionalSpouseSection(couple: Couple, family: Family) -> String {
        var section = "Additional spouse:\n"
        
        var spouseInfo = formatParentCompact(couple.wife)
        
        let additionalCouples = family.couples.filter { $0 != family.primaryCouple }
        if let index = additionalCouples.firstIndex(of: couple),
           let widowInfo = extractWidowInfo(from: family.notes, spouseIndex: index) {
            let components = spouseInfo.components(separatedBy: ", ")
            if !components.isEmpty {
                let name = components[0]
                let dates = components.count > 1 ? ", " + components[1...].joined(separator: ", ") : ""
                spouseInfo = "\(name), widow of \(widowInfo)\(dates)"
            }
        }
        section += spouseInfo + "\n"
        
        if let fullMarriageDate = couple.fullMarriageDate {
            section += "m. \(formatDate(fullMarriageDate))\n"
        } else if let marriageDate = couple.marriageDate {
            section += "m. \(formatDate(marriageDate))\n"
        }
        
        return section
    }
    
    private static func formatNotesSection(family: Family) -> String {
        var section = ""
        
        let filteredNotes = family.notes.filter { !$0.lowercased().contains("leski") }
        if !filteredNotes.isEmpty {
            section += "Note:\n"
            for note in filteredNotes {
                section += "\(note)\n"
            }
        }
        
        // Note definitions (*) **) etc.)
        if !family.noteDefinitions.isEmpty {
            if section.isEmpty { section += "Note:\n" }
            for key in family.noteDefinitions.keys.sorted() {
                if let text = family.noteDefinitions[key] {
                    section += "\(key) \(text)\n"
                }
            }
        }

        let totalChildrenDied = family.totalChildrenDiedInfancy
        if totalChildrenDied > 0 {
            if filteredNotes.isEmpty {
                section += "Note:\n"
            }
            let childNoun = totalChildrenDied == 1 ? "child" : "children"
            section += "\(totalChildrenDied) \(childNoun) died in infancy\n"
        }
        
        return section
    }
    
    private static func formatEnhancementSourcesSection(sources: [EnhancementSource]) -> String {
        guard !sources.isEmpty else { return "" }
        
        var section = "Additional information:\n"
        
        for source in sources {
            let dataTypes: String
            if source.hasEnhancedMarriage && source.hasEnhancedDeath {
                dataTypes = "marriage and death dates are"
            } else if source.hasEnhancedMarriage {
                dataTypes = "marriage date is"
            } else if source.hasEnhancedDeath {
                dataTypes = "death date is"
            } else {
                continue
            }
            section += "\(source.childName)'s \(dataTypes) on \(source.asParentPages)\n"
        }
        
        return section
    }
    
    private static func formatAsChildEnhancementInfo(
        person: Person,
        targetChild: Person,
        network: FamilyNetwork?
    ) -> String {
        guard let network = network,
              let asParentFamily = network.getAsParentFamily(for: person) else {
            return ""
        }
        
        guard let asParent = findPersonInAsParentFamily(person, in: asParentFamily) else {
            return ""
        }
        
        // Check for enhanced death date
        let hasEnhancedDeath = asParent.deathDate != nil && targetChild.deathDate == nil
        
        // Check for enhanced marriage date
        var hasEnhancedMarriage = false
        
        let nuclearMarriage = targetChild.fullMarriageDate ?? targetChild.marriageDate
        let asParentMarriage = asParent.fullMarriageDate ?? asParent.marriageDate
        
        if asParentMarriage != nil && nuclearMarriage != asParentMarriage {
            hasEnhancedMarriage = true
        }
        
        // Check couple-level marriage date
        if !hasEnhancedMarriage {
            if let couple = asParentFamily.couples.first(where: { c in
                c.husband.name.lowercased() == person.name.lowercased() ||
                c.wife.name.lowercased() == person.name.lowercased()
            }) {
                let coupleMarriage = couple.fullMarriageDate ?? couple.marriageDate
                if coupleMarriage != nil && nuclearMarriage != coupleMarriage {
                    hasEnhancedMarriage = true
                }
            }
        }
        
        guard hasEnhancedMarriage || hasEnhancedDeath else { return "" }
        
        var section = "Additional information:\n"
        let dataTypes: String
        if hasEnhancedMarriage && hasEnhancedDeath {
            dataTypes = "marriage and death dates are"
        } else if hasEnhancedMarriage {
            dataTypes = "marriage date is"
        } else {
            dataTypes = "death date is"
        }
        section += "\(person.name)'s \(dataTypes) on \(asParentFamily.pageReferenceString)\n"
        
        return section
    }
    
    // MARK: - Person Formatting
    
    private static func formatParentCompact(_ person: Person) -> String {
        let name = person.displayName
        
        let markers = person.noteMarkers.isEmpty ? "" : " \(person.noteMarkers.joined(separator: " "))"
        
        if let birthDate = person.birthDate, let deathDate = person.deathDate {
            return "\(name), \(formatDate(birthDate)) - \(formatDate(deathDate))\(markers)"
        } else if let birthDate = person.birthDate {
            return "\(name), b. \(formatDate(birthDate))\(markers)"
        } else if let deathDate = person.deathDate {
            return "\(name), d. \(formatDate(deathDate))\(markers)"
        }
        
        return "\(name)\(markers)"
    }
    
    private static func formatChild(_ child: Person) -> String {
        var line = child.name
        
        if let birthDate = child.birthDate {
            line += ", b. \(formatDate(birthDate))"
        }
        
        if let spouse = child.spouse, !spouse.isEmpty {
            line += ", m. \(spouse)"
            if let marriageDate = child.bestMarriageDate {
                if marriageDate.contains(".") {
                    line += " \(formatDate(marriageDate))"
                } else {
                    let birthYear = extractBirthYear(from: child)
                    line += " \(extractMarriageYear(marriageDate, parentBirthYear: birthYear))"
                }
            }
        }
        
        if let deathDate = child.deathDate {
            line += ", d. \(formatDate(deathDate))"
        }
        
        if !child.noteMarkers.isEmpty {
            line += " \(child.noteMarkers.joined(separator: " "))"
        }
        
        line += "\n"
        return line
    }
    
    private static func formatChildWithEnhancement(
        _ nuclearChild: Person,
        person: Person,
        network: FamilyNetwork
    ) -> String {
        // If child has no spouse, cannot have asParent family
        guard let spouse = nuclearChild.spouse, !spouse.isEmpty else {
            return formatChild(nuclearChild)
        }
        
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            return formatChild(nuclearChild)
        }
        
        // Find matching person in asParent family
        guard let asParent = findPersonInAsParentFamilyWithSpouseVerification(
            nuclearChild: nuclearChild,
            person: person,
            spouse: spouse,
            asParentFamily: asParentFamily
        ) else {
            return formatChild(nuclearChild)
        }
        
        // Build enhanced citation line
        var line = nuclearChild.name
        
        let enhancedBirthDate = nuclearChild.birthDate
        let enhancedDeathDate = asParent.deathDate ?? nuclearChild.deathDate
        
        // Date range format
        if let birthDate = enhancedBirthDate, let deathDate = enhancedDeathDate {
            line += ", \(formatDate(birthDate)) - \(formatDate(deathDate))"
        } else if let birthDate = enhancedBirthDate {
            line += ", b. \(formatDate(birthDate))"
        } else if let deathDate = enhancedDeathDate {
            line += ", d. \(formatDate(deathDate))"
        }
        
        // Enhanced marriage information
        let enhancedMarriageDate = findEnhancedMarriageDate(
            nuclearChild: nuclearChild,
            person: person,
            asParent: asParent,
            asParentFamily: asParentFamily
        )
        
        line += ", m. \(spouse)"
        if let marriageDate = enhancedMarriageDate {
            let birthYear = extractBirthYear(from: nuclearChild)
            if marriageDate.contains(".") {
                line += " \(formatDate(marriageDate, parentBirthYear: birthYear))"
            } else {
                line += " \(extractMarriageYear(marriageDate, parentBirthYear: birthYear))"
            }
        }
        line += "\n"
        return line
    }
    
    // MARK: - Person Matching
    
    private static func findPersonInAsParentFamilyWithSpouseVerification(
        nuclearChild: Person,
        person: Person,
        spouse: String,
        asParentFamily: Family
    ) -> Person? {
        // STEP 1: Try birth date match (most reliable)
        if let nuclearBirth = nuclearChild.birthDate?.trimmingCharacters(in: .whitespaces),
           !nuclearBirth.isEmpty {
            if let match = asParentFamily.allParents.first(where: { parent in
                if let parentBirth = parent.birthDate?.trimmingCharacters(in: .whitespaces),
                   !parentBirth.isEmpty {
                    return parentBirth == nuclearBirth
                }
                return false
            }) {
                return match
            }
        }
        
        // STEP 2: Name matching with spouse verification
        return asParentFamily.allParents.first { parent in
            let nameMatches = parent.name.lowercased() == nuclearChild.name.lowercased() ||
                            parent.name.lowercased() == person.name.lowercased()
            
            guard nameMatches else { return false }
            
            // Verify spouse matches
            guard let couple = asParentFamily.couples.first(where: { c in
                c.husband.name.lowercased() == parent.name.lowercased() ||
                c.wife.name.lowercased() == parent.name.lowercased()
            }) else { return false }
            
            let spouseInFamily = parent.name.lowercased() == couple.husband.name.lowercased()
                ? couple.wife
                : couple.husband
            
            // Flexible first-name matching
            let spouseFirstName = spouseInFamily.name.components(separatedBy: " ").first?.lowercased() ?? ""
            let expectedSpouseFirstName = spouse.components(separatedBy: " ").first?.lowercased() ?? ""
            
            return spouseInFamily.name.lowercased() == spouse.lowercased() ||
                   spouseInFamily.displayName.lowercased().contains(spouse.lowercased()) ||
                   spouse.lowercased().contains(spouseFirstName) ||
                   spouseFirstName == expectedSpouseFirstName
        }
    }
    
    private static func findPersonInAsParentFamily(_ person: Person, in asParentFamily: Family) -> Person? {
        // Try exact name matching
        if let match = asParentFamily.allParents.first(where: {
            $0.name.lowercased() == person.name.lowercased() ||
            $0.displayName.lowercased() == person.displayName.lowercased()
        }) {
            return match
        }
        
        // Fallback to birth date matching
        if let targetBirth = person.birthDate?.trimmingCharacters(in: .whitespaces),
           !targetBirth.isEmpty {
            return asParentFamily.allParents.first { parent in
                if let parentBirth = parent.birthDate?.trimmingCharacters(in: .whitespaces),
                   !parentBirth.isEmpty {
                    return parentBirth == targetBirth
                }
                return false
            }
        }
        
        return nil
    }
    
    private static func findEnhancedMarriageDate(
        nuclearChild: Person,
        person: Person,
        asParent: Person,
        asParentFamily: Family
    ) -> String? {
        // 1. Check asParent person-level dates
        if let date = asParent.fullMarriageDate ?? asParent.marriageDate {
            return date
        }
        
        // 2. Check couple-level date
        if let couple = asParentFamily.couples.first(where: { c in
            c.husband.name.lowercased() == person.name.lowercased() ||
            c.wife.name.lowercased() == person.name.lowercased()
        }) {
            if let date = couple.fullMarriageDate ?? couple.marriageDate {
                return date
            }
        }
        
        // 3. Fall back to nuclear family data
        return nuclearChild.bestMarriageDate
    }
    
    // MARK: - Helper Methods
    
    private static func shouldEnhanceChild(
        _ child: Person,
        isTarget: Bool,
        person: Person,
        network: FamilyNetwork?
    ) -> Bool {
        guard isTarget,
              let network = network,
              let spouse = child.spouse,
              !spouse.isEmpty else {
            return false
        }
        return network.getAsParentFamily(for: person) != nil
    }
    
    private static func isTargetPerson(
        _ child: Person,
        _ target: Person,
        nameEquivalenceManager: NameEquivalenceManager?
    ) -> Bool {
        // CRITICAL: If BOTH have birth dates, use them for matching
        if let childBirth = child.birthDate?.trimmingCharacters(in: .whitespaces),
           let targetBirth = target.birthDate?.trimmingCharacters(in: .whitespaces),
           !childBirth.isEmpty && !targetBirth.isEmpty {
            // Exact match
            if childBirth == targetBirth {
                return true
            }
            // Year-only comparison (e.g., "1730" vs "27.01.1762")
            let childYear = extractBirthYear(from: Person(name: "", birthDate: childBirth, noteMarkers: []))
            let targetYear = extractBirthYear(from: Person(name: "", birthDate: targetBirth, noteMarkers: []))
            if let cy = childYear, let ty = targetYear, cy == ty {
                return true
            }
            // Both have birth dates but they don't match - NOT the same person
            return false
        }
        
        // Only fall through to name matching if one/both lack birth dates
        
        // PRIORITY 2: Exact name matching
        if child.name.lowercased().trimmingCharacters(in: .whitespaces) ==
           target.name.lowercased().trimmingCharacters(in: .whitespaces) {
            return true
        }
        
        // PRIORITY 3: Name equivalence matching
        if let nameManager = nameEquivalenceManager,
           nameManager.areNamesEquivalent(child.name, target.name) {
            return true
        }
        
        return false
    }
    
    // MARK: - Enhancement Tracking
    
    private struct EnhancementSource {
        let childName: String
        let hasEnhancedMarriage: Bool
        let hasEnhancedDeath: Bool
        let asParentPages: String
    }
    
    private static func trackEnhancement(
        nuclearChild: Person,
        person: Person,
        asParentFamily: Family
    ) -> EnhancementSource? {
        guard nuclearChild.spouse != nil && !nuclearChild.spouse!.isEmpty else {
            return nil
        }
        
        guard let asParent = findPersonInAsParentFamily(person, in: asParentFamily) else {
            return nil
        }
        
        let hasEnhancedDeath = asParent.deathDate != nil && nuclearChild.deathDate == nil
        
        var hasEnhancedMarriage = false
        let nuclearMarriage = nuclearChild.fullMarriageDate ?? nuclearChild.marriageDate
        let asParentMarriage = asParent.fullMarriageDate ?? asParent.marriageDate
        
        if asParentMarriage != nil && nuclearMarriage != asParentMarriage {
            hasEnhancedMarriage = true
        }
        
        // Check couple-level marriage date
        if !hasEnhancedMarriage {
            if let couple = asParentFamily.couples.first(where: { c in
                c.husband.name.lowercased() == person.name.lowercased() ||
                c.wife.name.lowercased() == person.name.lowercased()
            }) {
                let coupleMarriage = couple.fullMarriageDate ?? couple.marriageDate
                if coupleMarriage != nil && nuclearMarriage != coupleMarriage {
                    hasEnhancedMarriage = true
                }
            }
        }
        
        guard hasEnhancedDeath || hasEnhancedMarriage else { return nil }
        
        return EnhancementSource(
            childName: nuclearChild.name,
            hasEnhancedMarriage: hasEnhancedMarriage,
            hasEnhancedDeath: hasEnhancedDeath,
            asParentPages: asParentFamily.pageReferenceString
        )
    }
    
    // MARK: - Date Formatting
    
    private static func formatDate(_ date: String, parentBirthYear: Int? = nil) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle approximate dates (n 1666 -> abt 1666)
        if trimmed.hasPrefix("n ") {
            let yearPart = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return "abt \(yearPart)"
        }
        
        // Handle "n" prefix without space (n1666 -> abt 1666)
        if trimmed.hasPrefix("n") && trimmed.count > 1 {
            let yearPart = String(trimmed.dropFirst(1))
            if Int(yearPart) != nil {
                return "abt \(yearPart)"
            }
        }
        
        let components = trimmed.components(separatedBy: ".")
        if components.count == 3,
           let day = Int(components[0]),
           let month = Int(components[1]) {
            let monthNames = ["January", "February", "March", "April", "May", "June",
                            "July", "August", "September", "October", "November", "December"]
            
            if month >= 1 && month <= 12 {
                let year: String
                if components[2].count == 4 {
                    // Full 4-digit year
                    year = components[2]
                } else if components[2].count == 2, let twoDigitYear = Int(components[2]) {
                    // 2-digit year - infer century
                    year = String(inferCentury(for: twoDigitYear, parentBirthYear: parentBirthYear))
                } else {
                    return trimmed
                }
                return "\(day) \(monthNames[month - 1]) \(year)"
            }
        }
        return trimmed
    }
    
    private static func extractMarriageYear(_ marriageDate: String, parentBirthYear: Int?) -> String {
        let trimmed = marriageDate.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If already full date, format it
        if trimmed.contains(".") {
            return formatDate(trimmed)
        }
        
        // If 4-digit year, return as-is
        if trimmed.count == 4 && Int(trimmed) != nil {
            return trimmed
        }
        
        // If 2-digit year, infer century
        if trimmed.count == 2, let twoDigitYear = Int(trimmed) {
            let fullYear = inferCentury(for: twoDigitYear, parentBirthYear: parentBirthYear)
            return String(fullYear)
        }
        
        return trimmed
    }
    
    static func inferCentury(for twoDigitYear: Int, parentBirthYear: Int?) -> Int {
        if let birthYear = parentBirthYear {
            // Marriage typically happens 15-50 years after birth
            let candidates = [1600 + twoDigitYear, 1700 + twoDigitYear, 1800 + twoDigitYear]
            let ages = candidates.map { $0 - birthYear }
            
            // Prefer century that puts marriage age in range 15-50
            for (index, age) in ages.enumerated() {
                if age >= 15 && age <= 50 {
                    return candidates[index]
                }
            }
            
            // Pick closest to reasonable range
            let distances = ages.map { age -> Int in
                if age < 15 { return 15 - age }
                else { return age - 50 }
            }
            
            if let minIndex = distances.indices.min(by: { distances[$0] < distances[$1] }) {
                return candidates[minIndex]
            }
        }
        
        // Default fallback
        return 1700 + twoDigitYear
    }
    
    private static func extractBirthYear(from person: Person) -> Int? {
        guard let birthDate = person.birthDate else { return nil }
        
        // Handle DD.MM.YYYY format
        let components = birthDate.components(separatedBy: ".")
        if components.count == 3, let year = Int(components[2]) {
            return year
        }
        
        // Handle year-only format
        if birthDate.count == 4, let year = Int(birthDate) {
            return year
        }
        
        return nil
    }
    
    private static func extractWidowInfo(from notes: [String], spouseIndex: Int) -> String? {
        let widowNotes = notes.filter { $0.lowercased().contains("leski") }
        
        if spouseIndex < widowNotes.count {
            let note = widowNotes[spouseIndex]
            let components = note.components(separatedBy: " leski")
            if !components.isEmpty {
                return components[0].trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
}
