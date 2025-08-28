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
        
        // FIXED: Additional spouses (couples beyond the first)
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
            // Try both displayName and name for lookup
            let asParentFamily = network.getAsParentFamily(for: person) ??
                                 network.asParentFamilies[person.displayName] ??
                                 network.asParentFamilies[person.name]
            
            if let asParentFamily = asParentFamily {
                // Find the person in their asParent family
                let personAsParent = asParentFamily.allParents.first { parent in
                    parent.name.lowercased() == person.name.lowercased()
                }
                
                var additionalInfo: [String] = []
                
                if let personAsParent = personAsParent {
                    // Check for death date not in asChild family
                    if personAsParent.deathDate != nil && person.deathDate == nil {
                        additionalInfo.append("death date")
                    }
                    
                    // Check for marriage date enhancement
                    let hasFullMarriageInAsParent = personAsParent.fullMarriageDate != nil || 
                                                    (personAsParent.marriageDate != nil && 
                                                     personAsParent.marriageDate!.count > 2)
                    let hasOnlyPartialInAsChild = person.fullMarriageDate == nil && 
                                                  (person.marriageDate == nil || 
                                                   person.marriageDate!.count <= 2)
                    
                    if hasFullMarriageInAsParent && hasOnlyPartialInAsChild {
                        additionalInfo.append("marriage date")
                    }
                }
                
                // Add the additional information section if applicable
                if let personAsParent = personAsParent, !additionalInfo.isEmpty {
                    citation += "\nAdditional Information:\n"
                    let dateTypes = formatDateAdditions(additionalInfo)
                    citation += "\(person.name)'s \(dateTypes) found on \(asParentFamily.pageReferenceString)\n"
                    
                    let spouseName = person.spouse ?? personAsParent.spouse ?? "spouse"
                    citation += "\(person.name)'s \(dateTypes) on \(asParentFamily.pageReferenceString) where \(person.name) and \(spouseName) are parents\n"
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
        
        // For the target person (Maria), look up their asParent family
        let asParentFamily = network.getAsParentFamily(for: person) ??
                            network.asParentFamilies[person.displayName] ??
                            network.asParentFamilies[person.name]
        
        if let asParentFamily = asParentFamily {
            // Find Maria as a parent in ISO-PEITSO III 2
            if let childAsParent = asParentFamily.allParents.first(where: {
                $0.name.lowercased() == person.name.lowercased()
            }) {
                // Enhance with death date if missing
                if enhancedChild.deathDate == nil && childAsParent.deathDate != nil {
                    enhancedChild.deathDate = childAsParent.deathDate
                }
                
                // Always use the 8-digit marriage date from asParent if available
                if childAsParent.fullMarriageDate != nil {
                    enhancedChild.fullMarriageDate = childAsParent.fullMarriageDate
                    // Clear any partial date to avoid confusion
                    enhancedChild.marriageDate = nil
                } else if childAsParent.marriageDate != nil && childAsParent.marriageDate!.count > 2 {
                    // Use 8-digit marriageDate if that's what we have
                    enhancedChild.fullMarriageDate = childAsParent.marriageDate
                    enhancedChild.marriageDate = nil
                }
                
                // Get spouse name if not already present
                if enhancedChild.spouse == nil || enhancedChild.spouse!.isEmpty {
                    enhancedChild.spouse = childAsParent.spouse
                }
            }
        }
        
        // Format the enhanced child with all dates
        var line = enhancedChild.name
        
        // Birth date
        if let birthDate = enhancedChild.birthDate {
            line += ", b \(normalizeDate(birthDate))"
        }
        
        // Marriage info with full date
        if let spouse = enhancedChild.spouse, !spouse.isEmpty {
            if let fullMarriage = enhancedChild.fullMarriageDate {
                line += ", m \(spouse) \(normalizeDate(fullMarriage))"
            } else if let marriageDate = enhancedChild.marriageDate {
                line += ", m \(spouse) \(extractMarriageYear(from: enhancedChild) ?? marriageDate)"
            } else {
                line += ", m \(spouse)"
            }
        }
        
        // Death date
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
        
        // Marriage info
        if let spouse = child.spouse, !spouse.isEmpty {
            let marriageYear = extractMarriageYear(from: child)
            if let year = marriageYear {
                line += ", m \(spouse) \(year)"
            } else if let rawMarriage = child.bestMarriageDate {
                line += ", m \(spouse) \(rawMarriage)"
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
        
        // Try to extract 4-digit year
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
                // Convert 2-digit to 4-digit (assuming 18xx for genealogical data)
                let fourDigitYear = year + 1800
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

