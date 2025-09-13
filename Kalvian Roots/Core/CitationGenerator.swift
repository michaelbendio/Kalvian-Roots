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
                citation += "m \(normalizeDate(marriageDate))\n"
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
                    citation += "m \(normalizeDate(marriageDate))\n"
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
     * ENHANCED with birth date matching and warning system
     * Includes additional information from the person's asParent family if available
     *
     * @param person The person who appears as a child in this family
     * @param asChildFamily The family where the person appears as a child
     * @param network Optional network to find the person's asParent family for additional dates
     */
    static func generateAsChildCitation(
        for person: Person,
        in asChildFamily: Family,
        network: FamilyNetwork? = nil
    ) -> String {
        var citation = "Information on \(asChildFamily.pageReferenceString) includes:\n"
        
        // Parents with compact format
        if let primaryCouple = asChildFamily.primaryCouple {
            citation += formatParentCompact(primaryCouple.husband) + "\n"
            citation += formatParentCompact(primaryCouple.wife) + "\n"
            
            // Marriage date for primary couple
            if let marriageDate = primaryCouple.marriageDate {
                citation += "m \(normalizeDate(marriageDate))\n"
            }
        }
        
        // Track if we found the target person
        var targetPersonFound = false
        
        // Process all couples in the family
        for couple in asChildFamily.couples {
            if !couple.children.isEmpty {
                citation += "Children:\n"
                for child in couple.children {
                    let isTarget = isTargetPerson(child, person)
                    if isTarget {
                        targetPersonFound = true
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
                    citation += "m \(normalizeDate(marriageDate))\n"
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
        
        // Additional Information section - show source of enhanced data
        if targetPersonFound, let network = network {
            // The enhanced data comes from the person's asParent family (where they appear as a parent)
            // We need to find what data was enhanced and cite the source
            let asParentFamily = network.getAsParentFamily(for: person) ??
                                 network.asParentFamilies[person.displayName] ??
                                 network.asParentFamilies[person.name]
            
            if let asParentFamily = asParentFamily {
                var additionalInfo: [String] = []
                
                // Check what was enhanced by comparing original vs enhanced
                if let personAsParent = asParentFamily.allParents.first(where: {
                    $0.name.lowercased() == person.name.lowercased()
                }) {
                    
                    // Death date enhancement
                    if personAsParent.deathDate != nil && person.deathDate == nil {
                        additionalInfo.append("death date")
                    }
                    
                    // Marriage date enhancement - check various sources
                    if let asParentMarriage = personAsParent.fullMarriageDate ?? personAsParent.marriageDate,
                       let nuclearMarriage = person.marriageDate,
                       asParentMarriage.count > nuclearMarriage.count + 2 {
                        additionalInfo.append("marriage date")
                    }
                }
                
                // Also check couple-level marriage date enhancement
                if let couple = asParentFamily.couples.first(where: { couple in
                    couple.husband.name.lowercased() == person.name.lowercased() ||
                    couple.wife.name.lowercased() == person.name.lowercased()
                }) {
                    if let coupleMarriage = couple.marriageDate,
                       let nuclearMarriage = person.marriageDate,
                       coupleMarriage.count >= 8 && nuclearMarriage.count <= 4 {
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
        
        // WARNING: Add warning if target person not found by birth date
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
    
    // MARK: - Private Helper Methods
    
    /// Format parent with compact date style (birth and death on same line)
    private static func formatParentCompact(_ person: Person) -> String {
        var line = person.displayName
        
        if let birthDate = person.birthDate {
            line += ", b. \(normalizeDate(birthDate))"
        }
        
        if let deathDate = person.deathDate {
            line += ", d. \(normalizeDate(deathDate))"
        }
        
        return line
    }
    
    /// Format child with birth date and marriage info
    private static func formatChild(_ child: Person) -> String {
        var line = child.name
        
        if let birthDate = child.birthDate {
            line += ", b. \(normalizeDate(birthDate))"
        }
        
        if let marriageDate = child.bestMarriageDate {
            line += ", m. \(normalizeDate(marriageDate))"
        }
        
        if let spouse = child.spouse {
            line += " \(spouse)"
        }
        
        if let deathDate = child.deathDate {
            line += ", d. \(normalizeDate(deathDate))"
        }
        
        line += "\n"
        return line
    }
    
    /// Format child with enhancement information from asParent family
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
        
        let additions = getDateAdditions(nuclearChild: nuclearChild, asParent: asParent)
        
        var line = nuclearChild.name
        
        if let birthDate = nuclearChild.birthDate {
            line += ", b. \(normalizeDate(birthDate))"
        }
        
        // Use enhanced marriage date if available
        let marriageDate = asParent?.fullMarriageDate ??
                          asParent?.marriageDate ??
                          nuclearChild.bestMarriageDate
        if let marriageDate = marriageDate {
            line += ", m. \(normalizeDate(marriageDate))"
        }
        
        if let spouse = nuclearChild.spouse {
            line += " \(spouse)"
        }
        
        // Use enhanced death date if available
        let deathDate = asParent?.deathDate ?? nuclearChild.deathDate
        if let deathDate = deathDate {
            line += ", d. \(normalizeDate(deathDate))"
        }
        
        // Add note about enhancements
        if !additions.isEmpty {
            let formattedAdditions = formatDateAdditions(additions)
            line += " (\(formattedAdditions) found on \(asParentFamily.pageReferenceString))"
        }
        
        line += "\n"
        return line
    }
    
    /// Check if this child matches the target person we're looking for
    private static func isTargetPerson(_ child: Person, _ target: Person) -> Bool {
        // Primary matching by name
        let nameMatch = child.name.lowercased() == target.name.lowercased()
        
        // Enhanced matching by birth date if available
        if let childBirth = child.birthDate, let targetBirth = target.birthDate {
            return nameMatch && childBirth == targetBirth
        }
        
        return nameMatch
    }
    
    /// Normalize date format for display
    private static func normalizeDate(_ date: String) -> String {
        // Handle various date formats consistently
        return date
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
        network: FamilyNetwork
    ) -> String {
        return generateAsChildCitation(for: person, in: asChildFamily, network: network)
    }
}
