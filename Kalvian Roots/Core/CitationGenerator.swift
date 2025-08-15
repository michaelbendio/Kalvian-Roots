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
        
        // Parents information with marriage date
        citation += formatParent(family.father)
        
        if let mother = family.mother {
            citation += formatParent(mother)
        }
        
        // Marriage date for parents
        if let marriageDate = extractParentsMarriageDate(from: family) {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        // Additional spouses
        if !family.additionalSpouses.isEmpty {
            citation += "\nAdditional spouse(s):\n"
            for spouse in family.additionalSpouses {
                citation += formatParent(spouse)
            }
        }
        
        // Children
        if !family.children.isEmpty {
            citation += "\nChildren:\n"
            for child in family.children {
                citation += formatChild(child)
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
     * This is the ONLY generateAsChildCitation method - consolidated from the duplicate
     */
    static func generateAsChildCitation(for person: Person, in family: Family) -> String {
        var citation = "Information on \(family.pageReferenceString) includes:\n\n"
        
        // Parents
        citation += formatParent(family.father)
        if let mother = family.mother {
            citation += formatParent(mother)
        }
        
        // Marriage date
        if let marriageDate = extractParentsMarriageDate(from: family) {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        // Additional spouses
        if !family.additionalSpouses.isEmpty {
            citation += "\nAdditional spouse(s):\n"
            for spouse in family.additionalSpouses {
                citation += formatParent(spouse)
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
        
        if let deathDate = person.bestDeathDate {
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
        
        // Marriage info (fix duplicate spouse issue)
        if let spouse = child.spouse, !spouse.isEmpty {
            let marriageYear = extractMarriageYear(from: child)
            if let year = marriageYear {
                line += ", m \(spouse) \(year)"
            } else if let rawMarriage = child.bestMarriageDate {
                // Handle cases where we have a marriage date but couldn't extract year
                line += ", m \(spouse) \(rawMarriage)"
            } else {
                line += ", m \(spouse)"
            }
        }
        
        // Death date (enhanced takes priority)
        if let deathDate = child.bestDeathDate {
            line += ", d \(normalizeDate(deathDate))"
        }
        
        line += "\n"
        return line
    }
    
    // MARK: - Data Extraction and Normalization
    
    /**
     * Extract parents' marriage date from family data
     */
    private static func extractParentsMarriageDate(from family: Family) -> String? {
        return family.father.bestMarriageDate ?? family.mother?.bestMarriageDate
    }
    
    /**
     * Extract marriage year from person's data
     */
    private static func extractMarriageYear(from person: Person) -> String? {
        guard let marriageDate = person.bestMarriageDate else { return nil }
        
        // Try to extract 4-digit year
        if let match = marriageDate.range(of: #"\b(\d{4})\b"#, options: .regularExpression) {
            let fullMatch = String(marriageDate[match])
            let components = fullMatch.components(separatedBy: ".")
            if components.count == 3 {
                return components[2]
            }
        }
        
        return nil
    }
    
    /**
     * Check if child matches target person for highlighting
     */
    private static func isTargetPerson(_ child: Person, _ target: Person) -> Bool {
        return child.name.lowercased() == target.name.lowercased() &&
               child.birthDate == target.birthDate
    }
    
    /**
     * Normalize date format from DD.MM.YYYY to readable format
     */
    private static func normalizeDate(_ date: String) -> String {
        // Convert "09.09.1727" to "9 September 1727"
        if let formatted = DateFormatter.formatGenealogyDate(date) {
            return formatted
        }
        
        // Handle partial dates or return as-is
        return date
    }
}
