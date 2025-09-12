// CitationGenerator.swift

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
        if let father = family.father {
            citation += formatParentCompact(father) + "\n"
        }
        
        if let mother = family.mother {
            citation += formatParentCompact(mother) + "\n"
        }
        
        // Marriage date for primary couple
        if let primaryCouple = family.primaryCouple,
           let marriageDate = primaryCouple.marriageDate {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        // Children from primary couple
        if !family.children.isEmpty {
            citation += "Children:\n"
            for child in family.children {
                citation += formatChild(child)
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
        if let childrenDied = family.childrenDiedInfancy, childrenDied > 0 {
            if family.notes.isEmpty {
                citation += "Note(s):\n"
            }
            citation += "Children died as infants: \(childrenDied)\n"
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
        if let father = asChildFamily.father {
            citation += formatParentCompact(father) + "\n"
        }
        if let mother = asChildFamily.mother {
            citation += formatParentCompact(mother) + "\n"
        }
        
        // Marriage date for primary couple
        if let primaryCouple = asChildFamily.primaryCouple,
           let marriageDate = primaryCouple.marriageDate {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        // Track if we found the target person
        var targetPersonFound = false
        
        // Children from primary couple
        if !asChildFamily.children.isEmpty {
            citation += "Children:\n"
            for child in asChildFamily.children {
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
        
        // Additional spouses properly formatted
        if asChildFamily.couples.count > 1 {
            for couple in asChildFamily.couples.dropFirst() {
                citation += "Additional spouse:\n"
                citation += formatParentCompact(couple.wife) + "\n"
                if let marriageDate = couple.marriageDate {
                    citation += "m \(normalizeDate(marriageDate))\n"
                }
                
                // Children with this spouse
                if !couple.children.isEmpty {
                    citation += "Children:\n"
                    for child in couple.children {
                        let isTarget = isTargetPerson(child, person)
                        if isTarget {
                            targetPersonFound = true
                        }
                        
                        let prefix = isTarget ? "→ " : ""
                        
                        if isTarget, let network = network {
                            citation += "\(prefix)\(formatChildWithEnhancement(child, person: person, network: network))"
                        } else {
                            citation += "\(prefix)\(formatChild(child))"
                        }
                    }
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
        if let childrenDied = asChildFamily.childrenDiedInfancy, childrenDied > 0 {
            if asChildFamily.notes.isEmpty {
                citation += "Note(s):\n"
            }
            citation += "Children died as infants: \(childrenDied)\n"
        }
        
        // Additional Information section - show source of enhanced data
        if targetPersonFound, let network = network {
            // The enhanced data comes from the person's asParent family (where they appear as a parent)
            // We need to find what data was enhanced and cite the source
            let asParentFamily = network.getAsParentFamily(for: person) ??
                                 network.asParentFamilies[person.displayName] ??
                                 network.asParentFamilies[person.name]
            
            if let asParentFamily = asParentFamily {
                let personName = person.name
                var additionalInfo: [String] = []
                
                // Find the person in their asParent family
                if let personAsParent = asParentFamily.allParents.first(where: {
                    $0.name.lowercased() == person.name.lowercased()
                }) {
                    // Check for death date enhancement (compare original person to asParent version)
                    if personAsParent.deathDate != nil && person.deathDate == nil {
                        additionalInfo.append("death date")
                    }
                    
                    // Check for marriage date enhancement (full vs partial date)
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
                        citation += "\(personName)'s marriage date and death date found on \(asParentFamily.pageReferenceString)\n"
                    } else if additionalInfo.contains("marriage date") {
                        citation += "\(personName)'s marriage date found on \(asParentFamily.pageReferenceString)\n"
                    } else if additionalInfo.contains("death date") {
                        citation += "\(personName)'s death date found on \(asParentFamily.pageReferenceString)\n"
                    }
                }
            }
        }
        
        // WARNING: Add warning if target person not found by birth date
        if !targetPersonFound {
            citation += "WARNING: Could not match target person '\(person.name)' (birth: \(person.birthDate ?? "unknown")) by birth date in source family\n"
        }
        
        return citation
    }

    /**
     * Generate nuclear family citation with cross-reference supplements
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
                    // Use birth date matching for better accuracy
                    if let childBirth = child.birthDate, let parentBirth = parent.birthDate {
                        return normalizeDateForComparison(childBirth) == normalizeDateForComparison(parentBirth)
                    }
                    // Fallback to name matching
                    return parent.name.lowercased() == child.name.lowercased()
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
            citation += "Additional information:\n"
            for supplement in supplements {
                citation += "\(supplement)\n"
            }
        }
        
        return citation
    }
    
    /**
     * Generate citation for a person in a family
     * This is the main entry point for citation generation
     *
     * @param person The person to generate a citation for
     * @param family The family context
     * @param fileURL The source file URL (currently unused but kept for compatibility)
     */
    static func generateCitation(
        for person: Person,
        in family: Family,
        fileURL: URL? = nil
    ) -> String {
        // Simplest implementation - just use the main family citation
        return generateMainFamilyCitation(family: family)
    }
    
    // MARK: - Enhanced Target Person Matching with Birth Dates
    
    /**
     * Check if a child matches the target person using birth date matching
     * This is more reliable than name matching since names can vary between childhood and adulthood
     */
    private static func isTargetPerson(_ child: Person, _ target: Person) -> Bool {
        // Primary matching: birth date (most reliable)
        if let childBirth = child.birthDate, let targetBirth = target.birthDate {
            return normalizeDateForComparison(childBirth) == normalizeDateForComparison(targetBirth)
        }
        
        // If birth dates are missing, this is an edge case we're ignoring for now
        // Return false so the warning system handles it
        return false
    }
    
    /**
     * Normalize dates for comparison - handles minor formatting variations
     */
    private static func normalizeDateForComparison(_ date: String) -> String {
        // Remove extra whitespace and normalize formatting
        var normalized = date.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle common variations: "06.01.1759" vs "6.1.1759"
        if normalized.contains(".") {
            let components = normalized.components(separatedBy: ".")
            if components.count == 3 {
                let day = String(format: "%02d", Int(components[0]) ?? 0)
                let month = String(format: "%02d", Int(components[1]) ?? 0)
                let year = components[2]
                normalized = "\(day).\(month).\(year)"
            }
        }
        
        return normalized
    }
    
    // MARK: - Enhanced Child Formatting
    
    /**
     * Enhanced formatChildWithEnhancement - now only called when we have a confirmed target match
     */
    private static func formatChildWithEnhancement(_ child: Person, person: Person, network: FamilyNetwork) -> String {
        var enhancedChild = child
        
        // Since we know this is the target person (birth dates matched),
        // use the person parameter to look up asParent family
        let asParentFamily = network.getAsParentFamily(for: person) ??
                            network.asParentFamilies[person.displayName] ??
                            network.asParentFamilies[person.name]
        
        // Try to enhance the child with dates from asParent family
        if let asParentFamily = asParentFamily {
            // Find the person in their asParent family
            if let parentInAsParentFamily = asParentFamily.allParents.first(where: {
                $0.name.lowercased() == person.name.lowercased()
            }) {
                // Add death date if missing
                if enhancedChild.deathDate == nil && parentInAsParentFamily.deathDate != nil {
                    enhancedChild.deathDate = parentInAsParentFamily.deathDate
                }
                
                // Get full marriage date from the COUPLE in asParent family
                if let couple = asParentFamily.couples.first(where: { couple in
                    couple.husband.name.lowercased() == person.name.lowercased() ||
                    couple.wife.name.lowercased() == person.name.lowercased()
                }) {
                    // Use the couple's marriage date which should be the full 8-digit date
                    if let fullMarriage = couple.marriageDate, fullMarriage.count >= 8 {
                        enhancedChild.fullMarriageDate = fullMarriage
                    }
                }
            }
        }
        
        // Format the enhanced child using compact format for target person
        var line = enhancedChild.name
        
        // Use compact birth-death format if both dates are present
        if let birthDate = enhancedChild.birthDate, let deathDate = enhancedChild.deathDate {
            line += ", \(normalizeDate(birthDate)) - \(normalizeDate(deathDate))"
        } else if let birthDate = enhancedChild.birthDate {
            line += ", \(normalizeDate(birthDate))"
        } else if let deathDate = enhancedChild.deathDate {
            line += ", d \(normalizeDate(deathDate))"
        }
        
        // Marriage info after dates - use the enhanced full date
        if let spouse = enhancedChild.spouse, !spouse.isEmpty {
            line += ", m \(spouse)"
            if let fullMarriage = enhancedChild.fullMarriageDate {
                // Use the full date from asParent family
                line += " \(normalizeDate(fullMarriage))"
            } else if let marriageDate = enhancedChild.marriageDate {
                // Fall back to year extraction
                let marriageYear = extractMarriageYear(from: enhancedChild)
                if let year = marriageYear {
                    line += " \(year)"
                }
            }
        }
        
        line += "\n"
        return line
    }

    // MARK: - Formatting Helpers
    
    /**
     * Format parent with compact birth-death format
     */
    private static func formatParentCompact(_ person: Person) -> String {
        var line = person.displayName + ", "
        
        // Use full dates for both birth and death
        if let birthDate = person.birthDate, let deathDate = person.deathDate {
            // Both dates present: use full dates with dash
            line += "\(normalizeDate(birthDate)) - \(normalizeDate(deathDate))"
        } else if let birthDate = person.birthDate {
            // Only birth date
            line += normalizeDate(birthDate)
        } else if let deathDate = person.deathDate {
            // Only death date
            line += "d \(normalizeDate(deathDate))"
        }
        
        return line
    }
    
    /**
     * Format parent with birth and death dates (original style for backward compatibility)
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
            
            if components.count >= 3 {
                // Full date: dd.mm.yyyy - return year
                return components.last
            } else {
                // Just a year
                return fullMatch
            }
        }
        
        // Handle 2-digit year
        if let match = marriageDate.range(of: #"\b(\d{2})\b"#, options: .regularExpression) {
            let yearPart = String(marriageDate[match])
            if let year = Int(yearPart) {
                // Convert to 4-digit year (assuming 1700s or 1800s)
                if year < 50 {
                    return "18\(String(format: "%02d", year))"
                } else {
                    return "17\(String(format: "%02d", year))"
                }
            }
        }
        
        return nil
    }
    
    /**
     * Extract year from a date string
     */
    private static func extractYear(from dateStr: String) -> String? {
        if let match = dateStr.range(of: #"\b(\d{4})\b"#, options: .regularExpression) {
            return String(dateStr[match])
        }
        return nil
    }
    
    /**
     * Normalize date format for consistent display
     */
    private static func normalizeDate(_ date: String) -> String {
        // Remove FamilySearch IDs
        var normalized = date.replacingOccurrences(of: #"<[A-Z0-9]{4}-[A-Z0-9]{3}>"#, with: "", options: .regularExpression)
        
        // Clean up whitespace
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // Format date properly
        if normalized.contains(".") {
            // Full date format
            let components = normalized.components(separatedBy: ".")
            if components.count == 3 {
                let day = Int(components[0]) ?? 0
                let month = Int(components[1]) ?? 0
                let year = components[2].trimmingCharacters(in: .whitespaces)
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "d MMMM yyyy"
                dateFormatter.locale = Locale(identifier: "en_US")
                
                if let date = DateComponents(calendar: .current, year: Int(year), month: month, day: day).date {
                    return dateFormatter.string(from: date)
                }
            }
        } else if let year = extractYear(from: normalized) {
            // Year-only format
            return year
        }
        
        return normalized
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
