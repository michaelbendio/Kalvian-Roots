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
 * 2. As_child citations (person in their parents' family)
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
     * Used for: parents showing where they came from
     */
    static func generateAsChildCitation(for person: Person, in family: Family) -> String {
        var citation = "Information on \(family.pageReferenceString) includes:\n\n"
        
        // Parents
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
        
        // Children with target person highlighted
        citation += "\nChildren:\n"
        for child in family.children {
            let prefix = isTargetPerson(child, person) ? "→ " : "  "
            citation += "\(prefix)\(formatChild(child))"
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
