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
     * Enhanced with network information when available for target person
     */
    static func generateMainFamilyCitation(
        family: Family,
        targetPerson: Person? = nil,
        network: FamilyNetwork? = nil
    ) -> String {
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
                    // Check if this child is the target person
                    let isTarget: Bool
                    if let target = targetPerson {
                        isTarget = isTargetPerson(child, target, nameEquivalenceManager: nil)
                    } else {
                        isTarget = false
                    }
                    let prefix = isTarget ? "→ " : ""
                    
                    // For the target person, try to enhance with asParent information
                    if isTarget, let network = network {
                        citation += "\(prefix)\(formatChildWithEnhancement(child, person: targetPerson!, network: network))"
                    } else {
                        citation += "\(prefix)\(formatChild(child))"
                    }
                }
            }
        }
        
        // Additional spouses - properly formatted WITH WIDOW INFO
        if family.couples.count > 1 {
            for (index, couple) in family.couples.dropFirst().enumerated() {
                citation += "Additional spouse:\n"
                
                // Determine which spouse is the additional one
                let additionalSpouse = couple.husband != family.primaryCouple?.husband ?
                    couple.husband : couple.wife
                
                // Format the spouse with widow info if available
                var spouseInfo = formatParentCompact(additionalSpouse)
                if let widowInfo = extractWidowInfo(from: family.notes, spouseIndex: index) {
                    // Insert widow info before the dates
                    let components = spouseInfo.components(separatedBy: ", ")
                    if components.count > 0 {
                        let name = components[0]
                        let dates = components.count > 1 ? ", " + components[1...].joined(separator: ", ") : ""
                        spouseInfo = "\(name), widow of \(widowInfo)\(dates)"
                    }
                }
                citation += spouseInfo + "\n"
                
                if let marriageDate = couple.marriageDate {
                    citation += "m. \(formatDate(marriageDate))\n"
                }
                
                // Children with this spouse
                if !couple.children.isEmpty {
                    citation += "Children:\n"
                    for child in couple.children {
                        // Check if this child is the target person
                        let isTarget: Bool
                        if let target = targetPerson {
                            isTarget = isTargetPerson(child, target, nameEquivalenceManager: nil)
                        } else {
                            isTarget = false
                        }
                        let prefix = isTarget ? "→ " : ""
                        
                        // For the target person, try to enhance with asParent information
                        if isTarget, let network = network {
                            citation += "\(prefix)\(formatChildWithEnhancement(child, person: targetPerson!, network: network))"
                        } else {
                            citation += "\(prefix)\(formatChild(child))"
                        }
                    }
                }
            }
        }
        
        // Notes section with proper formatting - FILTER OUT WIDOW NOTES
        let filteredNotes = family.notes.filter { !$0.lowercased().contains("leski") }
        if !filteredNotes.isEmpty {
            citation += "Note(s):\n"
            for note in filteredNotes {
                citation += "\(note)\n"
            }
        }
        
        // Child mortality - formatted on its own line
        let totalChildrenDied = family.totalChildrenDiedInfancy
        if totalChildrenDied > 0 {
            if filteredNotes.isEmpty {  // Check filteredNotes instead of family.notes
                citation += "Note(s):\n"
            }
            citation += "Children died as infants: \(totalChildrenDied)\n"
        }
        
        // Additional Information section for enhanced children
        if let targetPerson = targetPerson, let network = network {
            if let asParentFamily = network.getAsParentFamily(for: targetPerson) {
                var additionalInfo: [String] = []
                
                // Find the target child in the nuclear family
                var targetChild: Person? = nil
                for couple in family.couples {
                    if let found = couple.children.first(where: {
                        isTargetPerson($0, targetPerson, nameEquivalenceManager: nil)
                    }) {
                        targetChild = found
                        break
                    }
                }
                
                if let targetChild = targetChild {
                    // Find the person in their asParent family using robust matching
                    let personAsParent = findPersonInAsParentFamily(targetPerson, in: asParentFamily)
                    
                    // Check for death date enhancement
                    if let personAsParent = personAsParent {
                        if personAsParent.deathDate != nil && targetChild.deathDate == nil {
                            additionalInfo.append("death date")
                        }
                    }
                    
                    // Check for marriage date enhancement using robust matching
                    let matchingCouple = asParentFamily.couples.first { couple in
                        // Try name matching first
                        if couple.husband.name.lowercased() == targetPerson.name.lowercased() ||
                           couple.wife.name.lowercased() == targetPerson.name.lowercased() {
                            return true
                        }
                        
                        // Fallback to birth date matching
                        if let targetBirth = targetPerson.birthDate?.trimmingCharacters(in: .whitespaces),
                           !targetBirth.isEmpty {
                            if let husbandBirth = couple.husband.birthDate?.trimmingCharacters(in: .whitespaces),
                               !husbandBirth.isEmpty,
                               husbandBirth == targetBirth {
                                return true
                            }
                            if let wifeBirth = couple.wife.birthDate?.trimmingCharacters(in: .whitespaces),
                               !wifeBirth.isEmpty,
                               wifeBirth == targetBirth {
                                return true
                            }
                        }
                        return false
                    }
                    
                    if let couple = matchingCouple {
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
                            citation += "\(targetPerson.name)'s marriage date and death date found on \(asParentFamily.pageReferenceString)\n"
                        } else if additionalInfo.contains("marriage date") {
                            citation += "\(targetPerson.name)'s marriage date found on \(asParentFamily.pageReferenceString)\n"
                        } else if additionalInfo.contains("death date") {
                            citation += "\(targetPerson.name)'s death date found on \(asParentFamily.pageReferenceString)\n"
                        }
                    }
                }
            }
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
                if marriageDate.count <= 4 && !marriageDate.contains(".") {
                    citation += "m. \(extractMarriageYear(marriageDate))\n"
                } else {
                    citation += "m. \(formatDate(marriageDate))\n"
                }
            }
        }
        
        // Track if we found the target person
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
                    
                    // Enhanced formatting for target person
                    if isTarget, let network = network {
                        citation += "\(prefix)\(formatChildWithEnhancement(child, person: person, network: network))"
                    } else {
                        citation += "\(prefix)\(formatChild(child))"
                    }
                }
            }
            
            // Additional spouses section (omitted for brevity)
        }
        
        // Notes section
        let filteredNotes = asChildFamily.notes.filter { !$0.lowercased().contains("leski") }
        if !filteredNotes.isEmpty {
            citation += "Note(s):\n"
            for note in filteredNotes {
                citation += "\(note)\n"
            }
        }
        
        // Child mortality
        let totalChildrenDied = asChildFamily.totalChildrenDiedInfancy
        if totalChildrenDied > 0 {
            if filteredNotes.isEmpty {
                citation += "Note(s):\n"
            }
            citation += "Children died as infants: \(totalChildrenDied)\n"
        }
        
        // Enhanced spouse information section
        if targetPersonFound, let targetChildInAsChild = targetChildInAsChild, let network = network {
            var foundEnhancement = false
            var additionalInfo: [String] = []
            var enhancedFromFamily: Family? = nil
            
            // Search ALL families in the network for this person as a parent
            // Check asParent families
            for (_, asParentFamily) in network.asParentFamilies {
                for couple in asParentFamily.couples {
                    // Check if this person appears as husband or wife
                    let isHusband = couple.husband.name.lowercased() == person.name.lowercased() ||
                                    (person.name.contains(" ") && couple.husband.name.lowercased() == person.name.components(separatedBy: " ").first?.lowercased())
                    let isWife = couple.wife.name.lowercased() == person.name.lowercased() ||
                                 (person.name.contains(" ") && couple.wife.name.lowercased() == person.name.components(separatedBy: " ").first?.lowercased())
                    
                    if isHusband || isWife {
                        let enhancedPerson = isHusband ? couple.husband : couple.wife
                        
                        // Check for death date enhancement
                        if enhancedPerson.deathDate != nil && targetChildInAsChild.deathDate == nil {
                            additionalInfo.append("death date")
                            foundEnhancement = true
                        }
                        
                        // Check for marriage date enhancement
                        let enhancedMarriage = couple.fullMarriageDate ?? couple.marriageDate
                        let currentMarriage = targetChildInAsChild.marriageDate
                        
                        // For marriage dates, check if we have a better one
                        if let enhanced = enhancedMarriage {
                            if currentMarriage == nil ||
                               (enhanced.contains("n ") && !(currentMarriage?.contains("n ") ?? false)) ||
                               enhanced.count > (currentMarriage?.count ?? 0) {
                                additionalInfo.append("marriage date")
                                foundEnhancement = true
                            }
                        }
                        
                        if foundEnhancement {
                            enhancedFromFamily = asParentFamily
                            break
                        }
                    }
                }
                if foundEnhancement { break }
            }
            
            // Also check spouse families if not found
            if !foundEnhancement {
                for (_, spouseFamily) in network.spouseAsChildFamilies {
                    // This would be unusual but check anyway
                    for couple in spouseFamily.couples {
                        if couple.husband.name.lowercased() == person.name.lowercased() ||
                           couple.wife.name.lowercased() == person.name.lowercased() {
                            // Found them as a parent in a spouse family
                            // (This shouldn't normally happen but check for completeness)
                        }
                    }
                }
            }
            
            // Add Additional Information section if enhancements found
            if foundEnhancement, let enhancedFromFamily = enhancedFromFamily {
                citation += "Additional Information:\n"
                citation += "\(person.name)'s "
                
                if additionalInfo.count == 2 {
                    citation += "marriage date and death date"
                } else if additionalInfo.contains("death date") {
                    citation += "death date"
                } else if additionalInfo.contains("marriage date") {
                    citation += "marriage date"
                }
                
                citation += " found on \(enhancedFromFamily.pageReferenceString)\n"
            }
        }
        
        // Warning if target person not found
        if !targetPersonFound {
            let birthInfo = person.birthDate ?? "unknown"
            citation += "WARNING: Could not match target person '\(person.displayName)' (birth: \(birthInfo)) by birth date in this family.\n"
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
    /// Also handles approximate dates: "n 1666" becomes "abt 1666"
    private static func formatDate(_ date: String) -> String {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle approximate dates (n 1666 -> abt 1666)
        if trimmed.hasPrefix("n ") {
            let yearPart = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return "abt \(yearPart)"
        }
        
        // Handle single 'n' followed by year without space (n1666 -> abt 1666)
        if trimmed.hasPrefix("n") && trimmed.count > 1 {
            let yearPart = String(trimmed.dropFirst(1))
            // Check if the rest is numeric
            if Int(yearPart) != nil {
                return "abt \(yearPart)"
            }
        }
        
        // Check if it contains dots (DD.MM.YYYY format)
        let components = trimmed.components(separatedBy: ".")
        if components.count == 3 {
            let dayStr = components[0].trimmingCharacters(in: .whitespaces)
            let monthStr = components[1].trimmingCharacters(in: .whitespaces)
            let yearStr = components[2].trimmingCharacters(in: .whitespaces)
            
            if let day = Int(dayStr), let month = Int(monthStr), let year = Int(yearStr) {
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
    
    /// Extract widow information from notes for a specific spouse
    private static func extractWidowInfo(from notes: [String], spouseIndex: Int) -> String? {
        // Extract all widow notes in order
        let widowNotes = notes.filter { $0.lowercased().contains("leski") }
        
        // Use the spouse index to match the correct widow note
        // Index 0 = II puoliso (first additional spouse)
        // Index 1 = III puoliso (second additional spouse)
        if spouseIndex < widowNotes.count {
            let note = widowNotes[spouseIndex]
            // Extract the name before "leski"
            let components = note.components(separatedBy: " leski")
            if components.count > 0 {
                return components[0].trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }

    // MARK: - Private Helper Methods
    
    /// Helper function to find matching person in asParent family with birth date fallback
    private static func findPersonInAsParentFamily(
        _ targetPerson: Person,
        in asParentFamily: Family
    ) -> Person? {
        // First try exact name matching
        if let match = asParentFamily.allParents.first(where: {
            $0.name.lowercased() == targetPerson.name.lowercased() ||
            $0.displayName.lowercased() == targetPerson.displayName.lowercased()
        }) {
            return match
        }
        
        // Fallback to birth date matching if we have a birth date
        if let targetBirth = targetPerson.birthDate?.trimmingCharacters(in: .whitespaces),
           !targetBirth.isEmpty {
            if let match = asParentFamily.allParents.first(where: { parent in
                if let parentBirth = parent.birthDate?.trimmingCharacters(in: .whitespaces),
                   !parentBirth.isEmpty {
                    return parentBirth == targetBirth
                }
                return false
            }) {
                logInfo(.citation, "✅ Found person by birth date match: \(targetPerson.name) -> \(match.displayName)")
                return match
            }
        }
        
        return nil
    }
    
    private static func formatParentCompact(_ person: Person) -> String {
        let name = person.displayName
        
        // Handle approximate birth/death dates properly
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
                // Use formatDate for full dates, extractMarriageYear for partial dates
                if marriageDate.contains(".") {
                    line += " \(formatDate(marriageDate))"
                } else {
                    line += " \(extractMarriageYear(marriageDate))"
                }
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
        logInfo(.citation, "🔍 formatChildWithEnhancement called:")
        logInfo(.citation, "  nuclearChild.name: '\(nuclearChild.name)'")
        logInfo(.citation, "  nuclearChild.birthDate: '\(nuclearChild.birthDate ?? "nil")'")
        logInfo(.citation, "  person.name: '\(person.name)'")
        logInfo(.citation, "  person.displayName: '\(person.displayName)'")
        logInfo(.citation, "  asParentFamilies keys: \(Array(network.asParentFamilies.keys))")
        
        // Get the asParent family for additional information
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            logWarn(.citation, "❌ No asParent family found - returning non-enhanced")
            return formatChild(nuclearChild)
        }

        // Find the child as they appear in their asParent family using robust matching
        var asParent = asParentFamily.allParents.first { parent in
            parent.name.lowercased() == nuclearChild.name.lowercased() ||
            parent.name.lowercased() == person.name.lowercased()
        }
        
        // If no name match, try birth date matching
        if asParent == nil {
            if let nuclearBirth = nuclearChild.birthDate?.trimmingCharacters(in: .whitespaces),
               !nuclearBirth.isEmpty {
                asParent = asParentFamily.allParents.first { parent in
                    if let parentBirth = parent.birthDate?.trimmingCharacters(in: .whitespaces),
                       !parentBirth.isEmpty {
                        return parentBirth == nuclearBirth
                    }
                    return false
                }
                if asParent != nil {
                    logInfo(.citation, "✅ Found person by birth date match in formatChildWithEnhancement")
                }
            }
        }
        
        var line = nuclearChild.name
        
        // Enhanced date formatting for target person
        let enhancedBirthDate = nuclearChild.birthDate
        let enhancedDeathDate = asParent?.deathDate ?? nuclearChild.deathDate
        
        // Use beautiful date range format for target person with proper 'abt' handling
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
        
        // 2. If no person-level date, check couple-level date in asParent family with robust matching
        if enhancedMarriageDate == nil {
            let matchingCouple = asParentFamily.couples.first { couple in
                // Try name matching first
                if couple.husband.name.lowercased() == person.name.lowercased() ||
                   couple.wife.name.lowercased() == person.name.lowercased() {
                    return true
                }
                
                // Fallback to birth date matching
                if let nuclearBirth = nuclearChild.birthDate?.trimmingCharacters(in: .whitespaces),
                   !nuclearBirth.isEmpty {
                    if let husbandBirth = couple.husband.birthDate?.trimmingCharacters(in: .whitespaces),
                       !husbandBirth.isEmpty,
                       husbandBirth == nuclearBirth {
                        return true
                    }
                    if let wifeBirth = couple.wife.birthDate?.trimmingCharacters(in: .whitespaces),
                       !wifeBirth.isEmpty,
                       wifeBirth == nuclearBirth {
                        return true
                    }
                }
                return false
            }
            
            if let couple = matchingCouple {
                enhancedMarriageDate = couple.fullMarriageDate ?? couple.marriageDate
            }
        }
        
        // 3. Fall back to nuclear family data
        enhancedMarriageDate = enhancedMarriageDate ?? nuclearChild.bestMarriageDate
        
        // Format marriage information
        if let spouse = nuclearChild.spouse, !spouse.isEmpty {
            line += ", m. \(spouse)"
            if let marriageDate = enhancedMarriageDate {
                if marriageDate.contains(".") {
                    line += " \(formatDate(marriageDate))"
                } else {
                    line += " \(extractMarriageYear(marriageDate))"
                }
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
        var birthDateMatch = false
        var exactNameMatch = false
        var equivalentNameMatch = false
        
        // PRIORITY 1: Birth date matching (most reliable)
        if let childBirth = child.birthDate?.trimmingCharacters(in: .whitespaces),
           let targetBirth = target.birthDate?.trimmingCharacters(in: .whitespaces),
           !childBirth.isEmpty && !targetBirth.isEmpty {
            
            birthDateMatch = (childBirth == targetBirth)
            if birthDateMatch {
                return true
            }
        }
        
        // PRIORITY 2: Exact name matching
        exactNameMatch = child.name.lowercased().trimmingCharacters(in: .whitespaces) ==
                        target.name.lowercased().trimmingCharacters(in: .whitespaces)
        if exactNameMatch {
            return true
        }
        
        // PRIORITY 3: Name equivalence matching (handles Helena/Leena, Malin/Magdalena)
        if let nameManager = nameEquivalenceManager {
            equivalentNameMatch = nameManager.areNamesEquivalent(child.name, target.name)
            if equivalentNameMatch {
                // ENHANCED: Accept name equivalence match even if birth dates don't match
                // This handles cases like "Helena" vs "Leena" where the name equivalence
                // is strong evidence of the same person despite birth date discrepancies
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

