//
//  CitationGenerator.swift
//  Kalvian Roots
//
//  Unified citation generation for all family relationship types
//

import Foundation

/**
 * Enhanced CitationGenerator with proper data formatting and validation
 *
 * Handles three types of citations:
 * 1. Main family citations (nuclear family with parents + children)
 * 2. As_child citations (person in their parents' family) - NOW ENHANCED
 * 3. Spouse as_child citations (spouse in their parents' family)
 */
struct CitationGenerator {
    
    /**
     * Generate main family citation with proper formatting
     * Used for: nuclear families and as_parent families (children with their spouses)
     */
    static func generateMainFamilyCitation(family: Family) -> String {
        var citation = "Information on \(family.pageReferenceString) includes:\n\n"
        
        // Parents information with marriage date (from primary couple)
        if let father = family.father {
            citation += formatParent(father)
        }
        
        if let mother = family.mother {
            citation += formatParent(mother)
        }
        
        // Marriage date for primary couple
        if let primaryCouple = family.primaryCouple,
           let marriageDate = primaryCouple.marriageDate {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        // FIXED: Additional spouses (couples beyond the first)
        if family.couples.count > 1 {
            citation += "\nAdditional spouse(s):\n"
            for couple in family.couples.dropFirst() {
                citation += formatParent(couple.wife)
                if let marriageDate = couple.marriageDate {
                    citation += "m \(normalizeDate(marriageDate))\n"
                }
            }
        }
        
        // Children from primary couple
        if !family.children.isEmpty {
            citation += "\nChildren:\n"
            for child in family.children {
                citation += formatChild(child)
            }
        }
        
        // Children from additional couples
        for (index, couple) in family.couples.dropFirst().enumerated() {
            if !couple.children.isEmpty {
                citation += "\nChildren with spouse \(index + 2):\n"
                for child in couple.children {
                    citation += formatChild(child)
                }
            }
        }
        
        // Notes
        if !family.notes.isEmpty {
            citation += "\nNotes:\n"
            for note in family.notes {
                citation += "• \(note)\n"
            }
        }
        
        // Child mortality
        if let childrenDied = family.childrenDiedInfancy, childrenDied > 0 {
            citation += "\nChildren died in infancy: \(childrenDied)\n"
        }
        
        return citation
    }

    /**
     * Generate as_child citation for a person in their parents' family
     * ENHANCED: Now includes additional information from the person's asParent family if available
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
        var citation = "Information on \(asChildFamily.pageReferenceString) includes:\n\n"
        
        // Parents
        if let father = asChildFamily.father {
            citation += formatParent(father)
        }
        if let mother = asChildFamily.mother {
            citation += formatParent(mother)
        }
        
        // Marriage date for primary couple
        if let primaryCouple = asChildFamily.primaryCouple,
           let marriageDate = primaryCouple.marriageDate {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        if asChildFamily.couples.count > 1 {
            citation += "\nAdditional spouse(s):\n"
            for couple in asChildFamily.couples.dropFirst() {
                citation += formatParent(couple.wife)
                if let marriageDate = couple.marriageDate {
                    citation += "m \(normalizeDate(marriageDate))\n"
                }
            }
        }
        
        // Children with target person highlighted - enhanced with additional dates if available
        citation += "\nChildren:\n"
        for child in asChildFamily.children {
            let isTarget = isTargetPerson(child, person)
            let prefix = isTarget ? "→ " : "  "
            
            // For the target person, try to enhance with asParent information
            if isTarget, let network = network {
                citation += "\(prefix)\(formatChildWithEnhancement(child, person: person, network: network))"
            } else {
                citation += "\(prefix)\(formatChild(child))"
            }
        }
        
        // Notes
        if !asChildFamily.notes.isEmpty {
            citation += "\nNotes:\n"
            for note in asChildFamily.notes {
                citation += "• \(note)\n"
            }
        }
        
        // Child mortality
        if let childrenDied = asChildFamily.childrenDiedInfancy, childrenDied > 0 {
            citation += "\nChildren died in infancy: \(childrenDied)\n"
        }
        
        // Additional Information section for the target person's asParent family
        if let network = network {
            let asParentFamily = network.getAsParentFamily(for: person) ??
                                 network.asParentFamilies[person.displayName] ??
                                 network.asParentFamilies[person.name]
            
            if let asParentFamily = asParentFamily {
                var additionalInfo: [String] = []
                
                // Find the person in their asParent family
                let personAsParent = asParentFamily.allParents.first { parent in
                    parent.name.lowercased() == person.name.lowercased()
                }
                
                // Get the couple's marriage date
                let coupleMarriageDate = asParentFamily.primaryCouple?.marriageDate
                
                // Check for death date enhancement
                // Person has death in asParent but not in asChild
                if personAsParent?.deathDate != nil {
                    additionalInfo.append("death date")
                }
                
                // Check for marriage date enhancement
                // Check if asParent has full date and asChild only has partial
                let hasFullMarriageInAsParent = 
                    (personAsParent?.fullMarriageDate != nil) ||
                    (personAsParent?.marriageDate != nil && personAsParent!.marriageDate!.count >= 8) ||
                    (coupleMarriageDate != nil && coupleMarriageDate!.count >= 8)
                
                let hasOnlyPartialInAsChild = 
                    person.fullMarriageDate == nil && 
                    (person.marriageDate == nil || person.marriageDate!.count <= 2)
                
                if hasFullMarriageInAsParent && hasOnlyPartialInAsChild {
                    additionalInfo.append("marriage date")
                }
                
                // Format the Additional Information section
                if !additionalInfo.isEmpty {
                    citation += "\n"  // Blank line for readability
                    citation += "Additional Information:\n"
                    
                    // Format based on what we found
                    if additionalInfo.count == 2 {
                        // Both marriage and death dates
                        citation += "\(person.name)'s marriage date and death date found on \(asParentFamily.pageReferenceString)\n"
                    } else if additionalInfo.contains("marriage date") {
                        citation += "\(person.name)'s marriage date found on \(asParentFamily.pageReferenceString)\n"
                    } else if additionalInfo.contains("death date") {
                        citation += "\(person.name)'s death date found on \(asParentFamily.pageReferenceString)\n"
                    }
                }
            }
        }
        
        return citation
    }

    /**
     * Format child with enhanced dates from their asParent family
     * Updated to handle the person parameter to get spouse info
     */
    private static func formatChildWithEnhancement(_ child: Person, person: Person, network: FamilyNetwork) -> String {
        var enhancedChild = child
        
        // CRITICAL: Use the correct person to look up asParent family
        // For parents, use 'person' parameter
        // For children in asChild citations, use 'child' parameter
        let lookupPerson = isTargetPerson(child, person) ? person : child
        
        let asParentFamily = network.getAsParentFamily(for: lookupPerson) ??
                            network.asParentFamilies[lookupPerson.displayName] ??
                            network.asParentFamilies[lookupPerson.name]
        
        if let asParentFamily = asParentFamily {
            // Find this person as a parent in their asParent family
            if let personAsParent = asParentFamily.allParents.first(where: {
                $0.name.lowercased() == lookupPerson.name.lowercased()
            }) {
                // Enhance with death date if missing
                if enhancedChild.deathDate == nil && personAsParent.deathDate != nil {
                    enhancedChild.deathDate = personAsParent.deathDate
                }
                
                // Enhance with marriage date - check ALL sources
                if enhancedChild.fullMarriageDate == nil {
                    if let fullDate = personAsParent.fullMarriageDate {
                        enhancedChild.fullMarriageDate = fullDate
                    } else if let marriageDate = personAsParent.marriageDate,
                              marriageDate.count >= 8 {
                        enhancedChild.fullMarriageDate = marriageDate
                    } else if let coupleMarriage = asParentFamily.primaryCouple?.marriageDate,
                              coupleMarriage.count >= 8 {
                        enhancedChild.fullMarriageDate = coupleMarriage
                    }
                }
                
                // Get spouse name if not already present
                if enhancedChild.spouse == nil || enhancedChild.spouse!.isEmpty {
                    enhancedChild.spouse = personAsParent.spouse
                }
            }
        }
        
        // Format the enhanced child with all dates
        var line = child.name
        
        if let birthDate = enhancedChild.birthDate {
            line += ", b \(normalizeDate(birthDate))"
        }
        
        if let spouse = enhancedChild.spouse, !spouse.isEmpty {
            if let fullMarriage = enhancedChild.fullMarriageDate {
                line += ", m \(spouse) \(normalizeDate(fullMarriage))"
            } else if let marriageDate = enhancedChild.marriageDate {
                line += ", m \(spouse) \(extractMarriageYear(from: enhancedChild) ?? marriageDate)"
            } else {
                line += ", m \(spouse)"
            }
        }
        
        if let deathDate = enhancedChild.deathDate {
            line += ", d \(normalizeDate(deathDate))"
        }
        
        line += "\n"
        return line
    }

    // MARK: - Formatting Helpers
    
    /**
     * Format parent with birth and death dates
     */
    private static func formatParent(_ person: Person) -> String {
        var line = person.displayName
        
        if let birthDate = person.birthDate {
            line += ", b \(normalizeDate(birthDate))"
        }
        
        if let deathDate = person.deathDate {
            line += ", d \(normalizeDate(deathDate))"
        }
        
        line += "\n"
        return line
    }
    
    /**
     * Format child with birth, marriage, and death dates
     */
    private static func formatChild(_ child: Person) -> String {
        var line = child.name
        
        // Birth date
        if let birthDate = child.birthDate {
            line += ", b \(normalizeDate(birthDate))"
        }
        
        // Marriage info - CHECK FULL DATE FIRST!
        if let spouse = child.spouse, !spouse.isEmpty {
            if let fullMarriage = child.fullMarriageDate {
                // Use the full date if we have it!
                line += ", m \(spouse) \(normalizeDate(fullMarriage))"
            } else if let marriageDate = child.marriageDate {
                // Otherwise extract year from partial date
                let marriageYear = extractMarriageYear(from: child)
                if let year = marriageYear {
                    line += ", m \(spouse) \(year)"
                } else {
                    line += ", m \(spouse) \(marriageDate)"
                }
            } else {
                line += ", m \(spouse)"
            }
        }
        
        // Death date
        if let deathDate = child.deathDate {
            line += ", d \(normalizeDate(deathDate))"
        }
        
        line += "\n"
        return line
    }
    
    // MARK: - Data Extraction and Normalization
    
    /**
     * Extract marriage year from person's data
     */
    private static func extractMarriageYear(from person: Person) -> String? {
        guard let marriageDate = person.bestMarriageDate else { return nil }
        
        // Try to extract 4-digit year first
        if let match = marriageDate.range(of: #"\b(\d{4})\b"#, options: .regularExpression) {
            let fullMatch = String(marriageDate[match])
            let components = fullMatch.components(separatedBy: ".")
            if let year = components.last, year.count == 4 {
                return year
            }
        }
        
        // Try to extract 2-digit year and convert to 4-digit
        if let match = marriageDate.range(of: #"\b(\d{2})\b"#, options: .regularExpression) {
            let twoDigitYear = String(marriageDate[match])
            if let year = Int(twoDigitYear) {
                // For genealogical data from Kälviä, most dates are 1700s and early 1800s
                // Use cutoff: 00-50 = 1800s, 51-99 = 1700s
                let fourDigitYear = year > 50 ? 1700 + year : 1800 + year
                return String(fourDigitYear)
            }
        }
        
        return nil
    }
    
    /**
     * Normalize date format for display
     */
    private static func normalizeDate(_ date: String) -> String {
        // Remove extra whitespace and normalize format
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's already in DD.MM.YYYY format
        if trimmed.range(of: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        
        // Check if it's a 4-digit year
        if trimmed.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        
        // Check if it starts with "n " (about)
        if trimmed.hasPrefix("n ") {
            return "about \(String(trimmed.dropFirst(2)))"
        }
        
        return trimmed
    }
    
    /**
     * Check if a child is the target person for highlighting
     */
    private static func isTargetPerson(_ child: Person, _ target: Person) -> Bool {
        // Compare by name and birth date for better accuracy
        let nameMatch = child.name.lowercased() == target.name.lowercased()
        let birthMatch = child.birthDate == target.birthDate
        
        return nameMatch && (birthMatch || child.birthDate == nil || target.birthDate == nil)
    }
}

extension CitationGenerator {
    
    /**
     * Generate enhanced nuclear family citation with cross-reference supplements
     * Only adds supplement when there's additional date information from asParent families
     */
    static func generateNuclearFamilyCitationWithSupplement(
        family: Family,
        network: FamilyNetwork
    ) -> String {
        
        // Start with the standard nuclear family citation
        var citation = generateMainFamilyCitation(family: family)
        
        // Collect supplement information from asParent families
        var supplements: [String] = []
        
        for child in family.marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                
                // Find the child as a parent in their asParent family
                let childInAsParentFamily = asParentFamily.allParents.first { parent in
                    // Match by name - could be enhanced with birth date matching
                    parent.name.lowercased() == child.name.lowercased()
                }
                
                // Check what additional date information is available
                let additionalInfo = collectAdditionalDateInfo(
                    nuclearChild: child,
                    asParent: childInAsParentFamily
                )
                
                if !additionalInfo.isEmpty {
                    let pageRef = asParentFamily.pageReferenceString
                    let description = formatDateAdditions(additionalInfo)
                    supplements.append("\(child.name)'s \(description) on \(pageRef)")
                }
            }
        }
        
        // Add supplement section only if we have additional information
        if !supplements.isEmpty {
            citation += "\nAdditional information:\n"
            for supplement in supplements {
                citation += "\(supplement)\n"
            }
        }
        
        return citation
    }
    
    // MARK: - Helper Methods for Supplements
    
    private static func collectAdditionalDateInfo(
        nuclearChild: Person,
        asParent: Person?
    ) -> [String] {
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

