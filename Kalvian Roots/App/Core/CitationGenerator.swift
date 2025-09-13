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
        
        // Parents with compact format
        if let primaryCouple = asChildFamily.primaryCouple {
            citation += formatParentCompact(primaryCouple.husband) + "\n"
            citation += formatParentCompact(primaryCouple.wife) + "\n"
            
            // Marriage date for primary couple
            if let marriageDate = primaryCouple.marriageDate {
                citation += "m \(normalizeDate(marriageDate))\n"
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
                        targetChildInAsChild = child  // Store the target child from asChild family
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
        
        logDebug(.citation, "🔍 DEBUG: === ADDITIONAL INFO SECTION START ===")
        logDebug(.citation, "🔍 DEBUG: targetPersonFound: \(targetPersonFound)")
        logDebug(.citation, "🔍 DEBUG: network != nil: \(network != nil)")
        logDebug(.citation, "🔍 DEBUG: targetChildInAsChild found: \(targetChildInAsChild != nil)")

        if targetPersonFound, let network = network, let targetChild = targetChildInAsChild {
            logDebug(.citation, "🔍 DEBUG: ✅ Entering Additional Information logic")
            
            // The enhanced data comes from the person's asParent family (where they appear as a parent)
            let asParentFamily = network.getAsParentFamily(for: person)
            logDebug(.citation, "🔍 DEBUG: person.name: '\(person.name)'")
            logDebug(.citation, "🔍 DEBUG: person.displayName: '\(person.displayName)'")
            logDebug(.citation, "🔍 DEBUG: targetChild.name: '\(targetChild.name)'")
            logDebug(.citation, "🔍 DEBUG: targetChild.marriageDate: '\(targetChild.marriageDate ?? "nil")'")
            logDebug(.citation, "🔍 DEBUG: targetChild.fullMarriageDate: '\(targetChild.fullMarriageDate ?? "nil")'")
            logDebug(.citation, "🔍 DEBUG: targetChild.spouse: '\(targetChild.spouse ?? "nil")'")
            logDebug(.citation, "🔍 DEBUG: asParentFamily found: \(asParentFamily?.familyId ?? "nil")")
            
            if let asParentFamily = asParentFamily {
                logDebug(.citation, "🔍 DEBUG: ✅ AsParent family: \(asParentFamily.familyId) (page: \(asParentFamily.pageReferenceString))")
                
                var additionalInfo: [String] = []
                
                // DEBUG: Show all parents in asParent family
                logDebug(.citation, "🔍 DEBUG: All parents in asParent family:")
                for parent in asParentFamily.allParents {
                    logDebug(.citation, "🔍 DEBUG:   - '\(parent.name)' (display: '\(parent.displayName)') birth: '\(parent.birthDate ?? "nil")'")
                }
                
                // Check what was enhanced by comparing targetChild (from asChild family) vs asParent family
                logDebug(.citation, "🔍 DEBUG: Looking for person '\(person.name)' in asParent family...")
                
                if let personAsParent = asParentFamily.allParents.first(where: {
                    let match = $0.name.lowercased() == person.name.lowercased()
                    logDebug(.citation, "🔍 DEBUG: Comparing '\($0.name.lowercased())' == '\(person.name.lowercased())' → \(match)")
                    return match
                }) {
                    logDebug(.citation, "🔍 DEBUG: ✅ Found person as parent: '\(personAsParent.name)'")
                    logDebug(.citation, "🔍 DEBUG: personAsParent.deathDate: '\(personAsParent.deathDate ?? "nil")'")
                    logDebug(.citation, "🔍 DEBUG: personAsParent.marriageDate: '\(personAsParent.marriageDate ?? "nil")'")
                    logDebug(.citation, "🔍 DEBUG: personAsParent.fullMarriageDate: '\(personAsParent.fullMarriageDate ?? "nil")'")
                    logDebug(.citation, "🔍 DEBUG: targetChild.deathDate: '\(targetChild.deathDate ?? "nil")'")
                    
                    // Death date enhancement - compare targetChild vs personAsParent
                    let deathEnhancement = personAsParent.deathDate != nil && targetChild.deathDate == nil
                    logDebug(.citation, "🔍 DEBUG: Death enhancement check: asParent='\(personAsParent.deathDate ?? "nil")' targetChild='\(targetChild.deathDate ?? "nil")' → \(deathEnhancement)")
                    
                    if deathEnhancement {
                        additionalInfo.append("death date")
                        logDebug(.citation, "🔍 DEBUG: ✅ Added death date to additionalInfo")
                    }
                    
                    // Marriage date enhancement - compare targetChild vs asParent family
                    logDebug(.citation, "🔍 DEBUG: Marriage enhancement checks...")
                    
                    // Method 1: Compare targetChild's marriage vs personAsParent's marriage
                    if let asParentMarriage = personAsParent.fullMarriageDate ?? personAsParent.marriageDate,
                       let childMarriage = targetChild.marriageDate {
                        logDebug(.citation, "🔍 DEBUG: Marriage comparison 1 (person-level):")
                        logDebug(.citation, "🔍 DEBUG:   asParentMarriage: '\(asParentMarriage)' (length: \(asParentMarriage.count))")
                        logDebug(.citation, "🔍 DEBUG:   childMarriage: '\(childMarriage)' (length: \(childMarriage.count))")
                        logDebug(.citation, "🔍 DEBUG:   Length difference: \(asParentMarriage.count - childMarriage.count)")
                        logDebug(.citation, "🔍 DEBUG:   Threshold (>2): \(asParentMarriage.count > childMarriage.count + 2)")
                        
                        if asParentMarriage.count > childMarriage.count + 2 {
                            additionalInfo.append("marriage date")
                            logDebug(.citation, "🔍 DEBUG: ✅ Added marriage date to additionalInfo (person comparison)")
                        } else {
                            logDebug(.citation, "🔍 DEBUG: ❌ Marriage threshold not met (person comparison)")
                        }
                    } else {
                        logDebug(.citation, "🔍 DEBUG: ❌ Missing data for person marriage comparison")
                        logDebug(.citation, "🔍 DEBUG:   asParentMarriage: '\(personAsParent.fullMarriageDate ?? personAsParent.marriageDate ?? "nil")'")
                        logDebug(.citation, "🔍 DEBUG:   childMarriage: '\(targetChild.marriageDate ?? "nil")'")
                    }
                    
                } else {
                    logDebug(.citation, "🔍 DEBUG: ❌ Person not found as parent in asParent family")
                }
                
                // Method 2: Compare targetChild's marriage vs couple-level marriage in asParent family
                logDebug(.citation, "🔍 DEBUG: Checking couple-level marriage enhancement...")
                logDebug(.citation, "🔍 DEBUG: Number of couples in asParent family: \(asParentFamily.couples.count)")
                
                for (index, couple) in asParentFamily.couples.enumerated() {
                    logDebug(.citation, "🔍 DEBUG: Couple \(index + 1): husband='\(couple.husband.name)' wife='\(couple.wife.name)'")
                    logDebug(.citation, "🔍 DEBUG: Couple \(index + 1) marriage date: '\(couple.marriageDate ?? "nil")'")
                    logDebug(.citation, "🔍 DEBUG: Couple \(index + 1) full marriage date: '\(couple.fullMarriageDate ?? "nil")'")
                }
                
                if let couple = asParentFamily.couples.first(where: { couple in
                    let husbandMatch = couple.husband.name.lowercased() == person.name.lowercased()
                    let wifeMatch = couple.wife.name.lowercased() == person.name.lowercased()
                    logDebug(.citation, "🔍 DEBUG: Couple check - husband: '\(couple.husband.name)' (match: \(husbandMatch)), wife: '\(couple.wife.name)' (match: \(wifeMatch))")
                    return husbandMatch || wifeMatch
                }) {
                    logDebug(.citation, "🔍 DEBUG: ✅ Found person in couple")
                    logDebug(.citation, "🔍 DEBUG: Couple marriage date: '\(couple.marriageDate ?? "nil")'")
                    logDebug(.citation, "🔍 DEBUG: Couple full marriage date: '\(couple.fullMarriageDate ?? "nil")'")
                    
                    // Compare couple marriage vs targetChild marriage
                    let coupleMarriage = couple.fullMarriageDate ?? couple.marriageDate
                    let childMarriage = targetChild.marriageDate
                    
                    if let coupleMarriage = coupleMarriage,
                       let childMarriage = childMarriage {
                        logDebug(.citation, "🔍 DEBUG: Marriage comparison 2 (couple-level):")
                        logDebug(.citation, "🔍 DEBUG:   coupleMarriage: '\(coupleMarriage)' (length: \(coupleMarriage.count))")
                        logDebug(.citation, "🔍 DEBUG:   childMarriage: '\(childMarriage)' (length: \(childMarriage.count))")
                        logDebug(.citation, "🔍 DEBUG:   Couple length >= 8: \(coupleMarriage.count >= 8)")
                        logDebug(.citation, "🔍 DEBUG:   Child length <= 4: \(childMarriage.count <= 4)")
                        logDebug(.citation, "🔍 DEBUG:   Enhancement criteria: \(coupleMarriage.count >= 8 && childMarriage.count <= 4)")
                        
                        // Enhancement criteria: couple has full date (8+ chars), child has partial (≤4 chars)
                        if coupleMarriage.count >= 8 && childMarriage.count <= 4 {
                            if !additionalInfo.contains("marriage date") {
                                additionalInfo.append("marriage date")
                                logDebug(.citation, "🔍 DEBUG: ✅ Added marriage date to additionalInfo (couple comparison)")
                            } else {
                                logDebug(.citation, "🔍 DEBUG: ℹ️ Marriage date already in additionalInfo")
                            }
                        } else {
                            logDebug(.citation, "🔍 DEBUG: ❌ Couple marriage criteria not met")
                        }
                    } else if let coupleMarriage = coupleMarriage,
                              childMarriage == nil,
                              coupleMarriage.count >= 8 {
                        // Case: child has no marriage date, but couple has full date
                        if !additionalInfo.contains("marriage date") {
                            additionalInfo.append("marriage date")
                            logDebug(.citation, "🔍 DEBUG: ✅ Added marriage date to additionalInfo (child nil, couple has date)")
                        }
                    } else {
                        logDebug(.citation, "🔍 DEBUG: ❌ Missing data for couple marriage comparison")
                        logDebug(.citation, "🔍 DEBUG:   coupleMarriage: '\(coupleMarriage ?? "nil")'")
                        logDebug(.citation, "🔍 DEBUG:   childMarriage: '\(childMarriage ?? "nil")'")
                    }
                } else {
                    logDebug(.citation, "🔍 DEBUG: ❌ Person not found in any couple")
                }
                
                logDebug(.citation, "🔍 DEBUG: Final additionalInfo array: \(additionalInfo)")
                
                // Add Additional Information section if we have enhancements
                if !additionalInfo.isEmpty {
                    logDebug(.citation, "🔍 DEBUG: ✅ Generating Additional Information section")
                    citation += "\n"  // Add blank line for readability
                    citation += "Additional Information:\n"
                    if additionalInfo.contains("marriage date") && additionalInfo.contains("death date") {
                        let infoLine = "\(person.name)'s marriage date and death date found on \(asParentFamily.pageReferenceString)\n"
                        citation += infoLine
                        logDebug(.citation, "🔍 DEBUG: Added line: '\(infoLine.trimmingCharacters(in: .whitespacesAndNewlines))'")
                    } else if additionalInfo.contains("marriage date") {
                        let infoLine = "\(person.name)'s marriage date found on \(asParentFamily.pageReferenceString)\n"
                        citation += infoLine
                        logDebug(.citation, "🔍 DEBUG: Added line: '\(infoLine.trimmingCharacters(in: .whitespacesAndNewlines))'")
                    } else if additionalInfo.contains("death date") {
                        let infoLine = "\(person.name)'s death date found on \(asParentFamily.pageReferenceString)\n"
                        citation += infoLine
                        logDebug(.citation, "🔍 DEBUG: Added line: '\(infoLine.trimmingCharacters(in: .whitespacesAndNewlines))'")
                    }
                } else {
                    logDebug(.citation, "🔍 DEBUG: ❌ No additional info to add - additionalInfo is empty")
                }
            } else {
                logDebug(.citation, "🔍 DEBUG: ❌ No asParent family found for person")
                
                // DEBUG: Show available asParent families
                logDebug(.citation, "🔍 DEBUG: Available asParent families in network:")
                for (key, family) in network.asParentFamilies {
                    logDebug(.citation, "🔍 DEBUG:   - key: '\(key)' → family: \(family.familyId)")
                }
            }
        } else {
            if !targetPersonFound {
                logDebug(.citation, "🔍 DEBUG: ❌ Target person not found in asChild family")
            }
            if network == nil {
                logDebug(.citation, "🔍 DEBUG: ❌ No network provided")
            }
            if targetChildInAsChild == nil {
                logDebug(.citation, "🔍 DEBUG: ❌ Target child not captured from asChild family")
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
        
        // ENHANCED: Get marriage date from multiple sources in priority order
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
        
        // Display the best available marriage date
        if let marriageDate = enhancedMarriageDate {
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
    /// ENHANCED to handle name variations like Malin/Magdalena using birth date priority
    private static func isTargetPerson(
        _ child: Person,
        _ target: Person,
        nameEquivalenceManager: NameEquivalenceManager? = nil
    ) -> Bool {
        logDebug(.citation, "🔍 Matching '\(child.name)' (birth: \(child.birthDate ?? "none")) vs '\(target.name)' (birth: \(target.birthDate ?? "none"))")
        
        // PRIORITY 1: Birth date matching (most reliable for name variations like Malin/Magdalena)
        if let childBirth = child.birthDate?.trimmingCharacters(in: .whitespaces),
           let targetBirth = target.birthDate?.trimmingCharacters(in: .whitespaces),
           !childBirth.isEmpty && !targetBirth.isEmpty {
            
            if childBirth == targetBirth {
                logInfo(.citation, "✅ MATCH: Birth date '\(childBirth)' - '\(child.name)' = '\(target.name)'")
                return true
            } else {
                logDebug(.citation, "❌ Birth dates don't match: '\(childBirth)' ≠ '\(targetBirth)'")
            }
        }
        
        // PRIORITY 2: Exact name matching
        let exactNameMatch = child.name.lowercased().trimmingCharacters(in: .whitespaces) ==
                            target.name.lowercased().trimmingCharacters(in: .whitespaces)
        if exactNameMatch {
            logInfo(.citation, "✅ MATCH: Exact name '\(child.name)' = '\(target.name)'")
            return true
        }
        
        // PRIORITY 3: Name equivalence matching (handles Malin/Magdalena)
        if let nameManager = nameEquivalenceManager {
            if nameManager.areNamesEquivalent(child.name, target.name) {
                logInfo(.citation, "✅ MATCH: Name equivalence '\(child.name)' ↔ '\(target.name)'")
                return true
            }
        }
        
        // PRIORITY 4: FamilySearch ID matching (if both have IDs)
        if let childId = child.familySearchId?.trimmingCharacters(in: .whitespaces),
           let targetId = target.familySearchId?.trimmingCharacters(in: .whitespaces),
           !childId.isEmpty && !targetId.isEmpty {
            if childId.lowercased() == targetId.lowercased() {
                logInfo(.citation, "✅ MATCH: FamilySearch ID '\(childId)'")
                return true
            }
        }
        
        logDebug(.citation, "❌ No match found")
        return false
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
