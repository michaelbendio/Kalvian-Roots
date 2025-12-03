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
 *
 * Date Handling:
 * - Approximate dates (n yyyy) formatted as "abt yyyy"
 * - Smart century inference for 2-digit years using parent birth dates
 * - Full 8-digit dates preferred over 2-digit dates
 */
public struct CitationGenerator {
    
    // MARK: - Main Family Citation
    
    /**
     * Generate main family citation (nuclear family)
     * Tracks and reports where enhanced data comes from
     */
    public static func generateMainFamilyCitation(
        family: Family,
        targetPerson: Person? = nil,
        network: FamilyNetwork? = nil,
        nameEquivalenceManager: NameEquivalenceManager? = nil
    ) -> String {
        var citation = "Information on \(family.pageReferenceString) includes:\n"
        
        // Track which children got enhanced data
        var enhancementSources: [EnhancementSource] = []
        
        // Parents with beautiful date format
        if let primaryCouple = family.primaryCouple {
            citation += formatParentCompact(primaryCouple.husband) + "\n"
            citation += formatParentCompact(primaryCouple.wife) + "\n"
            
            // Marriage date with context-aware formatting
            if let fullMarriageDate = primaryCouple.fullMarriageDate {
                citation += "m. \(formatDate(fullMarriageDate))\n"
            } else if let marriageDate = primaryCouple.marriageDate {
                let parentBirthYear = extractBirthYear(from: primaryCouple.husband)
                                    ?? extractBirthYear(from: primaryCouple.wife)
                citation += "m. \(extractMarriageYear(marriageDate, parentBirthYear: parentBirthYear))\n"
            }
            
            // Primary couple's children
            if !primaryCouple.children.isEmpty {
                citation += "Children:\n"
                for child in primaryCouple.children {
                    let isTarget: Bool
                    if let target = targetPerson {
                        isTarget = isTargetPerson(child, target, nameEquivalenceManager: nameEquivalenceManager)
                    } else {
                        isTarget = false
                    }
                    
                    let shouldEnhance = shouldEnhanceChild(child, isTarget: isTarget, person: targetPerson ?? child, network: network)
                    let prefix = shouldEnhance ? "→ " : ""
                    
                    if shouldEnhance, let target = targetPerson {
                        // Track enhancements...
                        citation += "\(prefix)\(formatChildWithEnhancement(child, person: target, network: network!))"
                    } else {
                        citation += "\(prefix)\(formatChild(child))"
                    }
                }
            }
        }
        
        // Additional spouses
        if family.couples.count > 1 {
            for (index, couple) in family.couples.dropFirst().enumerated() {
                citation += "Additional spouse:\n"
                
                let additionalSpouse = couple.husband != family.primaryCouple?.husband ?
                    couple.husband : couple.wife
                
                var spouseInfo = formatParentCompact(additionalSpouse)
                if let widowInfo = extractWidowInfo(from: family.notes, spouseIndex: index) {
                    let components = spouseInfo.components(separatedBy: ", ")
                    if components.count > 0 {
                        let name = components[0]
                        let dates = components.count > 1 ? ", " + components[1...].joined(separator: ", ") : ""
                        spouseInfo = "\(name), widow of \(widowInfo)\(dates)"
                    }
                }
                citation += spouseInfo + "\n"
                
                if let fullMarriageDate = couple.fullMarriageDate {
                    citation += "m. \(formatDate(fullMarriageDate))\n"
                } else if let marriageDate = couple.marriageDate {
                    citation += "m. \(formatDate(marriageDate))\n"
                }
                
                if !couple.children.isEmpty {
                    citation += "Children:\n"
                    for child in couple.children {
                        let isTarget: Bool
                        if let target = targetPerson {
                            isTarget = isTargetPerson(child, target, nameEquivalenceManager: nil)
                        } else {
                            isTarget = false
                        }
                        let prefix = isTarget ? "→ " : ""
                        
                        if isTarget, let network = network, let target = targetPerson {
                            // Track enhancements for this child
                            if let asParentFamily = network.getAsParentFamily(for: target) {
                                let enhancementInfo = trackEnhancement(
                                    nuclearChild: child,
                                    person: target,
                                    asParentFamily: asParentFamily
                                )
                                if let info = enhancementInfo {
                                    enhancementSources.append(info)
                                }
                            }
                            
                            citation += "\(prefix)\(formatChildWithEnhancement(child, person: target, network: network))"
                        } else {
                            citation += "\(prefix)\(formatChild(child))"
                        }
                    }
                }
            }
        }
        
        // Notes section
        let filteredNotes = family.notes.filter { !$0.lowercased().contains("leski") }
        if !filteredNotes.isEmpty {
            citation += "Note:\n"
            for note in filteredNotes {
                citation += "\(note)\n"
            }
        }
        
        let totalChildrenDied = family.totalChildrenDiedInfancy
        if totalChildrenDied > 0 {
            if filteredNotes.isEmpty {
                citation += "Note:\n"
            }
            citation += "Children died as infants: \(totalChildrenDied)\n"
        }
        
        // Additional Information section - report where enhanced data came from
        if !enhancementSources.isEmpty {
            citation += "Additional information:\n"
            for source in enhancementSources {
                var parts: [String] = []
                
                if source.hasEnhancedMarriage && source.hasEnhancedDeath {
                    parts.append("death and marriage dates are")
                } else if source.hasEnhancedMarriage {
                    parts.append("marriage date is")
                } else if source.hasEnhancedDeath {
                    parts.append("death date is")
                }
                
                if !parts.isEmpty {
                    let dataTypes = parts.joined(separator: " and ")
                    citation += "\(source.childName)'s \(dataTypes) on \(source.asParentPages)\n"
                }
            }
        }
        
        return citation
    }

    /// Track what data was enhanced for a child
    private static func trackEnhancement(
        nuclearChild: Person,
        person: Person,
        asParentFamily: Family
    ) -> EnhancementSource? {
        // First, check if child is married (unmarried children can't have enhancements)
        guard nuclearChild.spouse != nil && !nuclearChild.spouse!.isEmpty else {
            return nil
        }
        
        // Try to find the person in the asParent family
        var asParent: Person? = nil
        
        // STEP 1: Try birth date matching (most reliable)
        if let nuclearBirth = nuclearChild.birthDate?.trimmingCharacters(in: .whitespaces),
           !nuclearBirth.isEmpty {
            asParent = asParentFamily.allParents.first { parent in
                if let parentBirth = parent.birthDate?.trimmingCharacters(in: .whitespaces),
                   !parentBirth.isEmpty {
                    return parentBirth == nuclearBirth
                }
                return false
            }
        }
        
        // STEP 2: Try name matching with spouse verification
        if asParent == nil {
            asParent = asParentFamily.allParents.first { parent in
                let nameMatches = parent.name.lowercased() == nuclearChild.name.lowercased() ||
                                parent.name.lowercased() == person.name.lowercased()
                
                if nameMatches, let spouse = nuclearChild.spouse {
                    let couple = asParentFamily.couples.first { c in
                        c.husband.name.lowercased() == parent.name.lowercased() ||
                        c.wife.name.lowercased() == parent.name.lowercased()
                    }
                    
                    if let couple = couple {
                        let spouseInFamily = parent.name.lowercased() == couple.husband.name.lowercased()
                            ? couple.wife
                            : couple.husband
                        
                        return spouseInFamily.name.lowercased() == spouse.lowercased() ||
                               spouseInFamily.displayName.lowercased().contains(spouse.lowercased())
                    }
                }
                return false
            }
        }
        
        // If we found a match, check what was enhanced
        guard let asParent = asParent else {
            return nil
        }
        
        let hasEnhancedDeath = asParent.deathDate != nil && nuclearChild.deathDate == nil
        
        // Check if marriage date was enhanced
        var hasEnhancedMarriage = false
        
        // Check person-level marriage date
        if asParent.fullMarriageDate != nil || asParent.marriageDate != nil {
            let nuclearMarriage = nuclearChild.fullMarriageDate ?? nuclearChild.marriageDate
            let asParentMarriage = asParent.fullMarriageDate ?? asParent.marriageDate
            
            // Consider it enhanced if asParent has a more complete date
            if asParentMarriage != nil && nuclearMarriage != asParentMarriage {
                hasEnhancedMarriage = true
            }
        }
        
        // Check couple-level marriage date
        if !hasEnhancedMarriage {
            if let couple = asParentFamily.couples.first(where: { c in
                c.husband.name.lowercased() == person.name.lowercased() ||
                c.wife.name.lowercased() == person.name.lowercased()
            }) {
                let coupleMarriage = couple.fullMarriageDate ?? couple.marriageDate
                let nuclearMarriage = nuclearChild.fullMarriageDate ?? nuclearChild.marriageDate
                
                if coupleMarriage != nil && nuclearMarriage != coupleMarriage {
                    hasEnhancedMarriage = true
                }
            }
        }
        
        // Only return if something was actually enhanced
        if hasEnhancedDeath || hasEnhancedMarriage {
            return EnhancementSource(
                childName: nuclearChild.name,
                hasEnhancedMarriage: hasEnhancedMarriage,
                hasEnhancedDeath: hasEnhancedDeath,
                asParentPages: asParentFamily.pageReferenceString
            )
        }
        
        return nil
    }
    
    // MARK: - As-Child Citation
    
    /**
     * Generate as_child citation (person in their parents' family)
     * Can be enhanced with asParent information when network is provided
     */
    public static func generateAsChildCitation(
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
            
            // Marriage date with context-aware formatting
            if let fullMarriageDate = primaryCouple.fullMarriageDate {
                citation += "m. \(formatDate(fullMarriageDate))\n"
            } else if let marriageDate = primaryCouple.marriageDate {
                let parentBirthYear = extractBirthYear(from: primaryCouple.husband)
                                    ?? extractBirthYear(from: primaryCouple.wife)
                citation += "m. \(extractMarriageYear(marriageDate, parentBirthYear: parentBirthYear))\n"
            }
        }
        
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
                    
                    let shouldEnhance = shouldEnhanceChild(child, isTarget: isTarget, person: person, network: network)
                    let prefix = shouldEnhance ? "→ " : ""
                    
                    if shouldEnhance {
                        citation += "\(prefix)\(formatChildWithEnhancement(child, person: person, network: network!))"
                    } else {
                        citation += "\(prefix)\(formatChild(child))"
                    }
                }
            }
            
            // Additional spouse
            if couple != asChildFamily.primaryCouple {
                citation += "Additional spouse:\n"
                
                var spouseInfo = formatParentCompact(couple.wife)
                
                let additionalCouples = asChildFamily.couples.filter { $0 != asChildFamily.primaryCouple }
                if let index = additionalCouples.firstIndex(of: couple) {
                    if let widowInfo = extractWidowInfo(from: asChildFamily.notes, spouseIndex: index) {
                        let components = spouseInfo.components(separatedBy: ", ")
                        if components.count > 0 {
                            let name = components[0]
                            let dates = components.count > 1 ? ", " + components[1...].joined(separator: ", ") : ""
                            spouseInfo = "\(name), widow of \(widowInfo)\(dates)"
                        }
                    }
                }
                citation += spouseInfo + "\n"
                
                if let fullMarriageDate = couple.fullMarriageDate {
                    citation += "m. \(formatDate(fullMarriageDate))\n"
                } else if let marriageDate = couple.marriageDate {
                    citation += "m. \(formatDate(marriageDate))\n"
                }
            }
        }
        
        // Notes section
        let filteredNotes = asChildFamily.notes.filter { !$0.lowercased().contains("leski") }
        if !filteredNotes.isEmpty {
            citation += "Note:\n"
            for note in filteredNotes {
                citation += "\(note)\n"
            }
        }
        
        let totalChildrenDied = asChildFamily.totalChildrenDiedInfancy
        if totalChildrenDied > 0 {
            if filteredNotes.isEmpty {
                citation += "Note:\n"
            }
            citation += "Children died as infants: \(totalChildrenDied)\n"
        }
        
        // Additional Information section for enhanced data
        if targetPersonFound, let targetChildInAsChild = targetChildInAsChild, let network = network {
            if let asParentFamily = network.getAsParentFamily(for: person) {
                var additionalInfo: [String] = []
                
                if let asParent = findPersonInAsParentFamily(person, in: asParentFamily) {
                    // Track death date enhancement
                    var hasEnhancedDeath = false
                    if asParent.deathDate != nil && targetChildInAsChild.deathDate == nil {
                        hasEnhancedDeath = true
                    }
                    
                    // Track marriage date enhancement
                    var hasEnhancedMarriage = false
                    
                    // Check person-level marriage date
                    let nuclearMarriage = targetChildInAsChild.fullMarriageDate ?? targetChildInAsChild.marriageDate
                    let asParentMarriage = asParent.fullMarriageDate ?? asParent.marriageDate
                    
                    if asParentMarriage != nil && nuclearMarriage != asParentMarriage {
                        hasEnhancedMarriage = true
                    }
                    
                    // Check couple-level marriage date if not yet enhanced
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
                    
                    // Build additional info text
                    if hasEnhancedMarriage || hasEnhancedDeath {
                        citation += "Additional information:\n"
                        
                        var parts: [String] = []
                        if hasEnhancedMarriage && hasEnhancedDeath {
                            parts.append("marriage and death dates are")
                        } else if hasEnhancedMarriage {
                            parts.append("marriage date is")
                        } else if hasEnhancedDeath {
                            parts.append("death date is")
                        }
                        
                        if !parts.isEmpty {
                            let dataTypes = parts.joined(separator: " and ")
                            citation += "\(person.name)'s \(dataTypes) on \(asParentFamily.pageReferenceString)\n"
                        }
                    }
                }
            }
        }
        
        return citation
    }
    
    
    /**
     * Generate spouse as_child citation (spouse in their parents' family)
     */
    public static func generateSpouseAsChildCitation(
        spouseName: String,
        in spouseAsChildFamily: Family
    ) -> String {
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
        
        return trimmed
    }
    
    /// Extract year from marriage date with smart context-aware century inference
    /// Uses parent birth year when available for accurate century determination
    private static func extractMarriageYear(_ marriageDate: String, parentBirthYear: Int? = nil) -> String {
        let trimmed = marriageDate.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle approximate dates with "n " prefix
        if trimmed.hasPrefix("n ") {
            let yearPart = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            
            // Check if it's a 2-digit year: "n 30" -> "abt 1730"
            if let twoDigit = Int(yearPart), yearPart.count == 2 {
                let fullYear = inferCentury(for: twoDigit, parentBirthYear: parentBirthYear)
                return "abt \(fullYear)"
            }
            
            // Check if it's a 4-digit year: "n 1730" -> "abt 1730"
            if let fourDigit = Int(yearPart), yearPart.count == 4 {
                return "abt \(yearPart)"
            }
            
            // Otherwise just prefix with abt
            return "abt \(yearPart)"
        }
        
        // If it's a 2-digit year, convert to 4-digit with smart inference
        if let twoDigit = Int(trimmed), trimmed.count == 2 {
            return String(inferCentury(for: twoDigit, parentBirthYear: parentBirthYear))
        }
        
        // If it's already a 4-digit year
        if trimmed.count == 4, Int(trimmed) != nil {
            return trimmed
        }
        
        return trimmed
    }
    
    /// Smart century inference based on parent birth year context
    /// Determines which century (1600, 1700, 1800) makes most sense for marriage
    public static func inferCentury(for twoDigitYear: Int, parentBirthYear: Int? = nil) -> Int {
        // If we have parent birth year, use it for smart inference
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
            
            // If none in range, pick closest to reasonable range
            let distances = ages.map { age -> Int in
                if age < 15 {
                    return 15 - age
                } else {
                    return age - 50
                }
            }
            
            if let minIndex = distances.indices.min(by: { distances[$0] < distances[$1] }) {
                return candidates[minIndex]
            }
        }
        
        // Fallback heuristic when no context available
        return 1700 + twoDigitYear
    }
    
    /// Helper to extract birth year from a person for context
    private static func extractBirthYear(from person: Person) -> Int? {
        guard let birthDate = person.birthDate else { return nil }
        
        // Handle full date format: dd.mm.yyyy
        let components = birthDate.components(separatedBy: ".")
        if components.count == 3, let year = Int(components[2]) {
            return year
        }
        
        // Handle year-only format: yyyy
        if birthDate.count == 4, let year = Int(birthDate) {
            return year
        }
        
        return nil
    }
    
    /// Extract widow information from notes for a specific spouse
    private static func extractWidowInfo(from notes: [String], spouseIndex: Int) -> String? {
        let widowNotes = notes.filter { $0.lowercased().contains("leski") }
        
        if spouseIndex < widowNotes.count {
            let note = widowNotes[spouseIndex]
            let components = note.components(separatedBy: " leski")
            if components.count > 0 {
                return components[0].trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    // MARK: - Person Formatting
    
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
        
        line += "\n"
        return line
    }
    
    /// Format child with enhanced dates from asParent family
    private static func formatChildWithEnhancement(
        _ nuclearChild: Person,
        person: Person,
        network: FamilyNetwork
    ) -> String {
        logInfo(.citation, "🔍 formatChildWithEnhancement called:")
        logInfo(.citation, "  nuclearChild.name: '\(nuclearChild.name)'")
        logInfo(.citation, "  person.displayName: '\(person.displayName)'")
        logInfo(.citation, "  asParentFamilies keys: \(Array(network.asParentFamilies.keys))")
        
        // CRITICAL: If the child has no spouse, they cannot have an asParent family
        // Return immediately without enhancement to prevent incorrect matching
        guard let spouse = nuclearChild.spouse, !spouse.isEmpty else {
            logInfo(.citation, "⚠️ Child has no spouse - cannot have asParent family, skipping enhancement")
            return formatChild(nuclearChild)
        }
        
        guard let asParentFamily = network.getAsParentFamily(for: person) else {
            logWarn(.citation, "❌ No asParent family found - returning non-enhanced")
            return formatChild(nuclearChild)
        }

        // STEP 1: Try PRIMARY matching - birth date match (most reliable)
        var asParent: Person? = nil
        
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
                logInfo(.citation, "✅ Found match by BIRTH DATE: \(nuclearBirth)")
            }
        }
        
        // STEP 2: Only if birth date match fails AND we have a spouse,
        // try name matching with spouse verification
        if asParent == nil {
            logInfo(.citation, "⚠️ No birth date match found, trying name match with spouse verification")
            
            asParent = asParentFamily.allParents.first { parent in
                let nameMatches = parent.name.lowercased() == nuclearChild.name.lowercased() ||
                                parent.name.lowercased() == person.name.lowercased()
                
                // If names match, verify this is the right person by checking spouse
                if nameMatches {
                    // Find the couple this parent belongs to
                    let couple = asParentFamily.couples.first { c in
                        c.husband.name.lowercased() == parent.name.lowercased() ||
                        c.wife.name.lowercased() == parent.name.lowercased()
                    }
                    
                    if let couple = couple {
                        let spouseInFamily = parent.name.lowercased() == couple.husband.name.lowercased()
                            ? couple.wife
                            : couple.husband
                        
                        // Check if the spouse name matches
                        let spouseMatches = spouseInFamily.name.lowercased() == spouse.lowercased() ||
                                          spouseInFamily.displayName.lowercased().contains(spouse.lowercased())
                        
                        if spouseMatches {
                            logInfo(.citation, "✅ Found match by NAME + SPOUSE verification")
                            return true
                        } else {
                            logWarn(.citation, "❌ Name matched but spouse doesn't match: expected '\(spouse)', found '\(spouseInFamily.name)'")
                            return false
                        }
                    }
                }
                return false
            }
        }
        
        // If still no match found, return non-enhanced
        guard let asParent = asParent else {
            logWarn(.citation, "❌ No matching person found in asParent family - returning non-enhanced")
            return formatChild(nuclearChild)
        }
        
        // Build the enhanced citation line
        var line = nuclearChild.name
        
        let enhancedBirthDate = nuclearChild.birthDate
        let enhancedDeathDate = asParent.deathDate ?? nuclearChild.deathDate
        
        // Use beautiful date range format
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
        enhancedMarriageDate = asParent.fullMarriageDate ?? asParent.marriageDate
        
        // 2. Check couple-level date in asParent family
        if enhancedMarriageDate == nil {
            let matchingCouple = asParentFamily.couples.first { couple in
                couple.husband.name.lowercased() == person.name.lowercased() ||
                couple.wife.name.lowercased() == person.name.lowercased()
            }
            
            if let couple = matchingCouple {
                enhancedMarriageDate = couple.fullMarriageDate ?? couple.marriageDate
            }
        }
        
        // 3. Fall back to nuclear family data
        enhancedMarriageDate = enhancedMarriageDate ?? nuclearChild.bestMarriageDate
        
        // Log the marriage date being used
        logInfo(.citation, "  enhancedMarriageDate: '\(enhancedMarriageDate ?? "nil")'")
        logInfo(.citation, "  nuclearChild.bestMarriageDate: '\(nuclearChild.bestMarriageDate ?? "nil")'")
        
        // Format marriage information
        line += ", m. \(spouse)"
        if let marriageDate = enhancedMarriageDate {
            let birthYear = extractBirthYear(from: nuclearChild)
            
            logInfo(.citation, "  marriageDate contains '.': \(marriageDate.contains("."))")
            logInfo(.citation, "  calling extractMarriageYear with: '\(marriageDate)'")
            
            if marriageDate.contains(".") {
                line += " \(formatDate(marriageDate))"
            } else {
                let formatted = extractMarriageYear(marriageDate, parentBirthYear: birthYear)
                logInfo(.citation, "  extractMarriageYear returned: '\(formatted)'")
                line += " \(formatted)"
            }
        }
        
        line += "\n"
        return line
    }

    /// Track enhancement sources for Additional Information section
    private struct EnhancementSource {
        let childName: String
        let hasEnhancedMarriage: Bool
        let hasEnhancedDeath: Bool
        let asParentPages: String
    }
    
    // MARK: - Helper Methods
    
    /// Determine if a child should get an arrow and enhancement
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
    
    /// Check if this child matches the target person
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
        if child.name.lowercased().trimmingCharacters(in: .whitespaces) ==
           target.name.lowercased().trimmingCharacters(in: .whitespaces) {
            return true
        }
        
        // PRIORITY 3: Name equivalence matching
        if let nameManager = nameEquivalenceManager {
            if nameManager.areNamesEquivalent(child.name, target.name) {
                return true
            }
        }
        
        return false
    }
    
    /// Find matching person in asParent family with birth date fallback
    private static func findPersonInAsParentFamily(
        _ targetPerson: Person,
        in asParentFamily: Family
    ) -> Person? {
        // Try exact name matching
        if let match = asParentFamily.allParents.first(where: {
            $0.name.lowercased() == targetPerson.name.lowercased() ||
            $0.displayName.lowercased() == targetPerson.displayName.lowercased()
        }) {
            return match
        }
        
        // Fallback to birth date matching
        if let targetBirth = targetPerson.birthDate?.trimmingCharacters(in: .whitespaces),
           !targetBirth.isEmpty {
            if let match = asParentFamily.allParents.first(where: { parent in
                if let parentBirth = parent.birthDate?.trimmingCharacters(in: .whitespaces),
                   !parentBirth.isEmpty {
                    return parentBirth == targetBirth
                }
                return false
            }) {
                return match
            }
        }
        
        return nil
    }
}

// MARK: - Extensions

extension CitationGenerator {
    /**
     * Generate as_child citation using enhanced birth date matching
     */
    public static func generateEnhancedAsChildCitation(
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
