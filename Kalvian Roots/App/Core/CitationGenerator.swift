//
//  CitationGenerator.swift
//  Kalvian Roots
//
//  Citation Generator for Finnish Genealogical Records
//

import Foundation

/**
 * Citation Generator for Finnish Genealogical Records
 *
 * Generates three types of citations:
 * 1. Main family citations (nuclear family with parents + children)
 * 2. As_child citations (person in their parents' family) - ENHANCED with birth date matching
 * 3. Spouse as_child citations (spouse in their parents' family)
 */
struct CitationGenerator {
    
    /**
     * Generate main family citation with proper formatting
     * Used for: nuclear families and as_parent families (children with their spouses)
     */
    static func generateMainFamilyCitation(family: Family) -> String {
        var citation = "Information on \(family.pageReferenceString) includes:\n"
        
        // Primary couple with compact date format
        if let primaryCouple = family.primaryCouple {
            citation += formatParentCompact(primaryCouple.husband) + "\n"
            citation += formatParentCompact(primaryCouple.wife) + "\n"
            
            // Marriage date for primary couple
            if let marriageDate = primaryCouple.marriageDate {
                citation += "m. \(formatDate(marriageDate))\n"
            }
            
            // Children from primary couple
            if !primaryCouple.children.isEmpty {
                citation += "Children:\n"
                for child in primaryCouple.children {
                    citation += formatChild(child)
                }
            }
        }
        
        // Additional spouses - properly formatted
        if family.couples.count > 1 {
            for couple in family.couples.dropFirst() {
                citation += "Additional spouse:\n"
                citation += formatParentCompact(couple.wife) + "\n"
                if let marriageDate = couple.marriageDate {
                    citation += "m. \(formatDate(marriageDate))\n"
                }
                
                // Children with this spouse
                if !couple.children.isEmpty {
                    citation += "Children:\n"
                    for child in couple.children {
                        citation += formatChild(child)
                    }
                }
            }
        }
        
        // Notes section with proper formatting
        if !family.notes.isEmpty {
            citation += "Note(s):\n"
            for note in family.notes {
                citation += "\(note)\n"
            }
        }
        
        // Child mortality - formatted on its own line
        let totalChildrenDied = family.totalChildrenDiedInfancy
        if totalChildrenDied > 0 {
            if family.notes.isEmpty {
                citation += "Note(s):\n"
            }
            citation += "Children died as infants: \(totalChildrenDied)\n"
        }
        
        return citation
    }

    /**
     * Generate as_child citation for the person in their parents' family
     * ENHANCED with birth date matching and name equivalence support
     * Includes additional information from the person's asParent family if available
     *
     * @param person The person who appears as a child in this family
     * @param asChildFamily The family where the person appears as a child
     * @param network Optional network to find the person's asParent family for additional dates
     * @param nameEquivalenceManager Optional name equivalence manager for matching name variations
     */
    static func generateAsChildCitation(
        for person: Person,
        in asChildFamily: Family,
        network: FamilyNetwork? = nil,
        nameEquivalenceManager: NameEquivalenceManager? = nil
    ) -> String {
        var citation = "Information on \(asChildFamily.pageReferenceString) includes:\n"
        
        // Parents with beautiful date format
        if let primaryCouple = asChildFamily.primaryCouple {
            citation += formatParentCompact(primaryCouple.husband) + "\n"
            citation += formatParentCompact(primaryCouple.wife) + "\n"
            
            // Marriage date for primary couple
            if let marriageDate = primaryCouple.marriageDate {
                citation += "m. \(formatDate(marriageDate))\n"
            }
        }
        
        // Track if we found the target person and store the target child
        var targetPersonFound = false
        var targetChildInAsChild: Person? = nil
        
        // Process all couples in the family
        for couple in asChildFamily.couples {
            if !couple.children.isEmpty {
                citation += "Children:\n"
                for child in couple.children {
                    let isTarget = isTargetPerson(child, person, nameEquivalenceManager: nameEquivalenceManager)
                    if isTarget {
                        targetPersonFound = true
                        targetChildInAsChild = child
                    }
                    
                    let prefix = isTarget ? "→ " : ""
                    
                    // For the target person, try to enhance with asParent information
                    if isTarget, let network = network {
                        citation += "\(prefix)\(formatChildWithEnhancement(child, person: person, network: network))"
                    } else {
                        citation += "\(prefix)\(formatChild(child))"
                    }
                }
            }
            
            // Show additional spouse info if this isn't the primary couple
            if couple != asChildFamily.primaryCouple {
                citation += "Additional spouse:\n"
                citation += formatParentCompact(couple.wife) + "\n"
                if let marriageDate = couple.marriageDate {
                    citation += "m. \(formatDate(marriageDate))\n"
                }
            }
        }
        
        // Notes section
        if !asChildFamily.notes.isEmpty {
            citation += "Note(s):\n"
            for note in asChildFamily.notes {
                citation += "\(note)\n"
            }
        }
        
        // Child mortality
        let totalChildrenDied = asChildFamily.totalChildrenDiedInfancy
        if totalChildrenDied > 0 {
            if asChildFamily.notes.isEmpty {
                citation += "Note(s):\n"
            }
            citation += "Children died as infants: \(totalChildrenDied)\n"
        }

        // Additional Information section
        if targetPersonFound, let network = network, let targetChild = targetChildInAsChild {
            let asParentFamily = network.getAsParentFamily(for: person)
            
            if let asParentFamily = asParentFamily {
                var additionalInfo: [String] = []
                
                // Check for death date enhancement
                if let personAsParent = asParentFamily.allParents.first(where: {
                    $0.name.lowercased() == person.name.lowercased()
                }) {
                    if personAsParent.deathDate != nil && targetChild.deathDate == nil {
                        additionalInfo.append("death date")
                    }
                }
                
                // Check for marriage date enhancement
                if let couple = asParentFamily.couples.first(where: { couple in
                    couple.husband.name.lowercased() == person.name.lowercased() ||
                    couple.wife.name.lowercased() == person.name.lowercased()
                }) {
                    let coupleMarriage = couple.fullMarriageDate ?? couple.marriageDate
                    let childMarriage = targetChild.marriageDate
                    
                    if let coupleMarriage = coupleMarriage,
                       let childMarriage = childMarriage,
                       coupleMarriage.count >= 8 && childMarriage.count <= 4 {
                        if !additionalInfo.contains("marriage date") {
                            additionalInfo.append("marriage date")
                        }
                    } else if let coupleMarriage = coupleMarriage,
                              childMarriage == nil,
                              coupleMarriage.count >= 8 {
                        if !additionalInfo.contains("marriage date") {
                            additionalInfo.append("marriage date")
                        }
                    }
                }
                
                // Add Additional Information section if we have enhancements
                if !additionalInfo.isEmpty {
                    citation += "Additional Information:\n"
                    if additionalInfo.contains("marriage date") && additionalInfo.contains("death date") {
                        citation += "\(person.name)'s marriage date and death date found on \(asParentFamily.pageReferenceString)\n"
                    } else if additionalInfo.contains("marriage date") {
                        citation += "\(person.name)'s marriage date found on \(asParentFamily.pageReferenceString)\n"
                    } else if additionalInfo.contains("death date") {
                        citation += "\(person.name)'s death date found on \(asParentFamily.pageReferenceString)\n"
                    }
                }
            }
        }
        
        // WARNING: Add warning if target person not found
        if !targetPersonFound {
            citation += "WARNING: Could not match target person '\(person.name)' (birth: \(person.birthDate ?? "unknown")) by birth date in this family.\n"
        }
        
        return citation
    }
    
    /**
     * Generate spouse as_child citation (spouse in their parents' family)
     * This is a standard as_child citation but for the spouse
     */
    static func generateSpouseAsChildCitation(
        spouseName: String,
        in spouseAsChildFamily: Family
    ) -> String {
        // Create a temporary person for the spouse to use standard citation logic
        let spousePerson = Person(name: spouseName, noteMarkers: [])
        return generateAsChildCitation(for: spousePerson, in: spouseAsChildFamily)
    }
    
    // MARK: - Date Formatting
    
    /// Convert DD.MM.YYYY to beautiful format like "6 January 1759"
    private static func formatDate(_ date: String) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's in DD.MM.YYYY format
        if trimmed.range(of: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil {
            let components = trimmed.components(separatedBy: ".")
            if components.count == 3 {
                let day = Int(components[0]) ?? 0
                let month = Int(components[1]) ?? 0
                let year = components[2]
                
                let monthNames = ["", "January", "February", "March", "April", "May", "June",
                                 "July", "August", "September", "October", "November", "December"]
                
                if month >= 1 && month <= 12 {
                    return "\(day) \(monthNames[month]) \(year)"
                }
            }
        }
        
        // Return as-is if not in expected format
        return trimmed
    }
    
    /// Extract just the year from a marriage date like "78" -> "1778"
    private static func extractMarriageYear(_ marriageDate: String) -> String {
        let trimmed = marriageDate.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it's a 2-digit year, convert to 4-digit
        if let twoDigit = Int(trimmed), trimmed.count == 2 {
            return String(1700 + twoDigit)
        }
        
        // If it's already a 4-digit year
        if trimmed.count == 4, Int(trimmed) != nil {
            return trimmed
        }
        
        return trimmed
    }
    
    // MARK: - Private Helper Methods
    
    /// Format parent with beautiful date range format
    private static func formatParentCompact(_ person: Person) -> String {
        let name = person.displayName
        
        if let birthDate = person.birthDate, let deathDate = person.deathDate {
            return "\(name), \(formatDate(birthDate)) - \(formatDate(deathDate))"
        } else if let birthDate = person.birthDate {
            return "\(name), b. \(formatDate(birthDate))"
        } else if let deathDate = person.deathDate {
            return "\(name), d. \(formatDate(deathDate))"
        }
        
        return name
    }
    
    /// Format regular child (not the target person)
    private static func formatChild(_ child: Person) -> String {
        var line = child.name
        
        if let birthDate = child.birthDate {
            line += ", b. \(formatDate(birthDate))"
        }
        
        if let spouse = child.spouse, !spouse.isEmpty {
            line += ", m. \(spouse)"
            if let marriageDate = child.bestMarriageDate {
                line += " \(extractMarriageYear(marriageDate))"
            }
        }
        
        if let deathDate = child.deathDate {
            line += ", d. \(formatDate(deathDate))"
        }
        
        line += "\n"
        return line
    }
    
    /// Format child with enhanced dates and beautiful formatting
    private static func formatChildWithEnhancement(
        _ nuclearChild: Person,
        person: Person,
        network: FamilyNetwork
    ) -> String {
        // Get the asParent family for additional information
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            return formatChild(nuclearChild)
        }
        
        // Find the child as they appear in their asParent family
        let asParent = asParentFamily.allParents.first { parent in
            parent.name.lowercased() == nuclearChild.name.lowercased()
        }
        
        var line = nuclearChild.name
        
        // Enhanced date formatting for target person
        let enhancedBirthDate = nuclearChild.birthDate
        let enhancedDeathDate = asParent?.deathDate ?? nuclearChild.deathDate
        
        // Use beautiful date range format for target person
        if let birthDate = enhancedBirthDate, let deathDate = enhancedDeathDate {
            line += ", \(formatDate(birthDate)) - \(formatDate(deathDate))"
        } else if let birthDate = enhancedBirthDate {
            line += ", b. \(formatDate(birthDate))"
        } else if let deathDate = enhancedDeathDate {
            line += ", d. \(formatDate(deathDate))"
        }
        
        // Enhanced marriage information
        var enhancedMarriageDate: String? = nil
        
        // 1. Check asParent person-level dates
        if let asParent = asParent {
            enhancedMarriageDate = asParent.fullMarriageDate ?? asParent.marriageDate
        }
        
        // 2. If no person-level date, check couple-level date in asParent family
        if enhancedMarriageDate == nil {
            if let couple = asParentFamily.couples.first(where: { couple in
                couple.husband.name.lowercased() == person.name.lowercased() ||
                couple.wife.name.lowercased() == person.name.lowercased()
            }) {
                enhancedMarriageDate = couple.fullMarriageDate ?? couple.marriageDate
            }
        }
        
        // 3. Fall back to nuclear child's marriage date
        if enhancedMarriageDate == nil {
            enhancedMarriageDate = nuclearChild.bestMarriageDate
        }
        
        // Display marriage information
        if let spouse = nuclearChild.spouse, !spouse.isEmpty {
            line += ", m. \(spouse)"
            if let marriageDate = enhancedMarriageDate {
                line += " \(formatDate(marriageDate))"
            }
        }
        
        line += "\n"
        return line
    }
    
    /// Check if this child matches the target person we're looking for
    private static func isTargetPerson(
        _ child: Person,
        _ target: Person,
        nameEquivalenceManager: NameEquivalenceManager? = nil
    ) -> Bool {
        // PRIORITY 1: Birth date matching (most reliable)
        if let childBirth = child.birthDate?.trimmingCharacters(in: .whitespaces),
           let targetBirth = target.birthDate?.trimmingCharacters(in: .whitespaces),
           !childBirth.isEmpty && !targetBirth.isEmpty {
            
            if childBirth == targetBirth {
                return true
            }
        }
        
        // PRIORITY 2: Exact name matching
        let exactNameMatch = child.name.lowercased().trimmingCharacters(in: .whitespaces) ==
                            target.name.lowercased().trimmingCharacters(in: .whitespaces)
        if exactNameMatch {
            return true
        }
        
        // PRIORITY 3: Name equivalence matching (handles Malin/Magdalena)
        if let nameManager = nameEquivalenceManager {
            if nameManager.areNamesEquivalent(child.name, target.name) {
                return true
            }
        }
        
        return false
    }
    
    /// Determine what date information was added from asParent family
    private static func getDateAdditions(nuclearChild: Person, asParent: Person?) -> [String] {
        guard let asParent = asParent else { return [] }
        
        var additions: [String] = []
        
        // Death date - only in asParent family, not in nuclear family
        if asParent.deathDate != nil && nuclearChild.deathDate == nil {
            additions.append("death date")
        }
        
        // Marriage date - full 8-digit date in asParent vs 2-digit in nuclear
        if let fullMarriageDate = asParent.fullMarriageDate,
           let nuclearMarriageDate = nuclearChild.marriageDate,
           fullMarriageDate.count > nuclearMarriageDate.count + 2 { // Allow some tolerance
            additions.append("marriage date")
        }
        
        return additions
    }
    
    /// Check if two persons are the same (handles name variations)
    private static func isPersonMatch(_ person1: Person, _ person2: Person) -> Bool {
        // First try exact name match
        if person1.name.lowercased() == person2.name.lowercased() {
            return true
        }
        
        // Then try birth date match (most reliable)
        if let birth1 = person1.birthDate?.trimmingCharacters(in: .whitespaces),
           let birth2 = person2.birthDate?.trimmingCharacters(in: .whitespaces),
           !birth1.isEmpty && !birth2.isEmpty {
            return birth1 == birth2
        }
        
        return false
    }
    
    private static func formatDateAdditions(_ additions: [String]) -> String {
        switch additions.count {
        case 0: return ""
        case 1: return additions[0] + " is"
        case 2: return "marriage and death dates are"
        default: return additions.joined(separator: " and ") + " are"
        }
    }
}

// MARK: - Extensions

extension CitationGenerator {
    
    /**
     * Generate as_child citation using enhanced birth date matching
     * This is a specialized version for cross-reference resolution
     */
    static func generateEnhancedAsChildCitation(
        for person: Person,
        in asChildFamily: Family,
        network: FamilyNetwork,
        nameEquivalenceManager: NameEquivalenceManager? = nil
    ) -> String {
        return generateAsChildCitation(
            for: person,
            in: asChildFamily,
            network: network,
            nameEquivalenceManager: nameEquivalenceManager
        )
    }
}
