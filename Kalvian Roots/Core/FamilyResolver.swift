//
//  FamilyResolver.swift
//  Kalvian Roots
//
//  Cross-reference resolution using birth date search and family references
//

import Foundation

/**
 * FamilyResolver.swift - Cross-reference resolution for genealogical families
 *
 * Implements birth date search and family reference validation for finding
 * as_child and as_parent families. Core component for enhanced citation generation.
 */

/**
 * Service for resolving family cross-references using multiple strategies
 *
 * Two-method approach:
 * 1. Family Reference Resolution - Use {FAMILY_ID} notation
 * 2. Birth Date Search Resolution - Search entire text for birth date matches
 */
@Observable
class FamilyResolver {
    
    // MARK: - Properties
    
    private let aiParsingService: AIParsingService
    private let nameEquivalenceManager: NameEquivalenceManager
    private var fileContent: String?
    
    /// Cache for resolved families to avoid re-parsing
    private var familyCache: [String: Family] = [:]
    
    /// Statistics for monitoring resolution success
    var resolutionStats = ResolutionStatistics()
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService, nameEquivalenceManager: NameEquivalenceManager) {
        self.aiParsingService = aiParsingService
        self.nameEquivalenceManager = nameEquivalenceManager
    }
    
    /// Set the file content for birth date searching
    func setFileContent(_ content: String) {
        self.fileContent = content
        self.familyCache.removeAll() // Clear cache when file changes
        print("📄 FamilyResolver loaded file content (\(content.count) characters)")
    }
    
    // MARK: - Main Resolution Methods
    
    /**
     * Resolve all cross-references for a family
     *
     * Returns FamilyNetwork with resolved as_child and as_parent families
     */
    func resolveCrossReferences(for family: Family) async throws -> FamilyNetwork {
        guard let fileContent = fileContent else {
            throw FamilyResolverError.noFileContent
        }
        
        print("🔍 Resolving cross-references for family: \(family.familyId)")
        
        var network = FamilyNetwork(mainFamily: family)
        
        // Resolve parent as_child families
        for parent in family.allParents {
            if let asChildRef = parent.asChildReference {
                do {
                    let resolvedFamily = try await resolveAsChildFamily(
                        for: parent,
                        reference: asChildRef,
                        fileContent: fileContent
                    )
                    network.asChildFamilies[parent.displayName] = resolvedFamily
                    resolutionStats.recordSuccess(.asChild)
                } catch {
                    print("⚠️ Failed to resolve as_child for \(parent.displayName): \(error)")
                    resolutionStats.recordFailure(.asChild)
                }
            }
        }
        
        // Resolve children as_parent families
        for child in family.children {
            if let asParentRef = child.asParentReference {
                do {
                    let resolvedFamily = try await resolveAsParentFamily(
                        for: child,
                        reference: asParentRef,
                        fileContent: fileContent
                    )
                    network.asParentFamilies[child.displayName] = resolvedFamily
                    resolutionStats.recordSuccess(.asParent)
                } catch {
                    print("⚠️ Failed to resolve as_parent for \(child.displayName): \(error)")
                    resolutionStats.recordFailure(.asParent)
                }
            }
        }
        
        // Resolve spouse as_child families for married children
        for child in family.marriedChildren {
            if let spouse = child.spouse {
                do {
                    let resolvedFamily = try await resolveSpouseAsChildFamily(
                        childName: child.displayName,
                        spouseName: spouse,
                        marriageDate: child.bestMarriageDate,
                        fileContent: fileContent
                    )
                    network.spouseAsChildFamilies[spouse] = resolvedFamily
                    resolutionStats.recordSuccess(.spouseAsChild)
                } catch {
                    print("⚠️ Failed to resolve spouse as_child for \(spouse): \(error)")
                    resolutionStats.recordFailure(.spouseAsChild)
                }
            }
        }
        
        print("✅ Cross-reference resolution complete:")
        print("   As_child families: \(network.asChildFamilies.count)")
        print("   As_parent families: \(network.asParentFamilies.count)")
        print("   Spouse as_child families: \(network.spouseAsChildFamilies.count)")
        
        return network
    }
    
    // MARK: - Specific Resolution Methods
    
    /**
     * Resolve as_child family (where person appears as a child)
     */
    private func resolveAsChildFamily(
        for person: Person,
        reference: String,
        fileContent: String
    ) async throws -> Family {
        print("👨‍👩‍👧‍👦 Resolving as_child family for \(person.displayName) → \(reference)")
        
        // Method 1: Try family reference first
        if FamilyIDs.isValid(familyId: reference) {
            do {
                let family = try await getFamilyById(reference)
                
                // Validate that person appears as child in this family
                if validateAsChildMatch(person: person, family: family) {
                    print("✅ Family reference validation successful")
                    return family
                } else {
                    print("⚠️ Family reference validation failed, trying birth date search")
                }
            } catch {
                print("⚠️ Family reference resolution failed: \(error)")
            }
        }
        
        // Method 2: Birth date search
        return try await resolveByBirthDateSearch(
            person: person,
            searchType: .asChild,
            fileContent: fileContent
        )
    }
    
    /**
     * Resolve as_parent family (where person appears as a parent)
     */
    private func resolveAsParentFamily(
        for person: Person,
        reference: String,
        fileContent: String
    ) async throws -> Family {
        print("👨‍👩‍👧‍👦 Resolving as_parent family for \(person.displayName) → \(reference)")
        
        // Method 1: Try family reference first (but many are incomplete like "Pieni-Porkola")
        if FamilyIDs.isValid(familyId: reference) {
            do {
                let family = try await getFamilyById(reference)
                
                // Validate that person appears as parent in this family
                if validateAsParentMatch(person: person, family: family) {
                    print("✅ Family reference validation successful")
                    return family
                } else {
                    print("⚠️ Family reference validation failed, trying birth date search")
                }
            } catch {
                print("⚠️ Family reference resolution failed: \(error)")
            }
        }
        
        // Method 2: Birth date search (more reliable for as_parent)
        return try await resolveByBirthDateSearch(
            person: person,
            searchType: .asParent,
            fileContent: fileContent
        )
    }
    
    /**
     * Resolve spouse's as_child family
     */
    private func resolveSpouseAsChildFamily(
        childName: String,
        spouseName: String,
        marriageDate: String?,
        fileContent: String
    ) async throws -> Family {
        print("💑 Resolving spouse as_child family for \(spouseName) (married to \(childName))")
        
        // Use birth date search to find spouse's birth record
        let spousePerson = Person(
            name: extractGivenName(from: spouseName),
            patronymic: extractPatronymic(from: spouseName),
            marriageDate: marriageDate,
            spouse: childName,
            noteMarkers: []
        )
        
        return try await resolveByBirthDateSearch(
            person: spousePerson,
            searchType: .spouseAsChild,
            fileContent: fileContent
        )
    }
    
    // MARK: - Birth Date Search Resolution
    
    /**
     * Core birth date search algorithm
     *
     * Searches entire file content for birth date matches and validates candidates
     */
    private func resolveByBirthDateSearch(
        person: Person,
        searchType: CrossRefType,
        fileContent: String
    ) async throws -> Family {
        
        guard let birthDate = person.birthDate else {
            throw FamilyResolverError.noBirthDate(person.displayName)
        }
        
        print("🔍 Birth date search for \(person.displayName) (\(birthDate))")
        
        // Find all families containing this birth date
        let candidateFamilyIds = findFamiliesWithBirthDate(birthDate, in: fileContent)
        
        guard !candidateFamilyIds.isEmpty else {
            throw FamilyResolverError.noBirthDateMatches(birthDate)
        }
        
        print("📋 Found \(candidateFamilyIds.count) candidate families: \(candidateFamilyIds)")
        
        // Parse and validate each candidate
        var matches: [FamilyMatch] = []
        
        for familyId in candidateFamilyIds {
            do {
                let candidateFamily = try await getFamilyById(familyId)
                let match = validateCandidate(
                    person: person,
                    family: candidateFamily,
                    searchType: searchType
                )
                
                if match.confidence > 0.0 {
                    matches.append(match)
                }
            } catch {
                print("⚠️ Failed to parse candidate family \(familyId): \(error)")
            }
        }
        
        // Sort by confidence and select best match
        matches.sort { $0.confidence > $1.confidence }
        
        guard let bestMatch = matches.first else {
            throw FamilyResolverError.noValidMatches(person.displayName)
        }
        
        print("🎯 Best match: \(bestMatch.family.familyId) (confidence: \(bestMatch.confidence))")
        print("   Reasons: \(bestMatch.reasons.joined(separator: ", "))")
        
        if !bestMatch.warnings.isEmpty {
            print("⚠️ Warnings: \(bestMatch.warnings.joined(separator: ", "))")
        }
        
        // Check for ambiguous matches
        if matches.count > 1 && matches[1].confidence > 0.7 {
            print("⚠️ Ambiguous match detected - confidence difference: \(bestMatch.confidence - matches[1].confidence)")
        }
        
        return bestMatch.family
    }
    
    // MARK: - Birth Date Searching
    
    /**
     * Find all family IDs that contain a specific birth date
     */
    private func findFamiliesWithBirthDate(_ birthDate: String, in fileContent: String) -> [String] {
        var familyIds: [String] = []
        let lines = fileContent.components(separatedBy: .newlines)
        var currentFamilyId: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for family header
            if let familyId = extractFamilyIdFromHeader(trimmedLine) {
                currentFamilyId = familyId
            }
            
            // Check for birth date in this line
            if trimmedLine.contains("★") && trimmedLine.contains(birthDate) {
                if let familyId = currentFamilyId {
                    familyIds.append(familyId)
                }
            }
        }
        
        return Array(Set(familyIds)) // Remove duplicates
    }
    
    /**
     * Extract family ID from header line like "KORPI 6, pages 105-106"
     */
    private func extractFamilyIdFromHeader(_ line: String) -> String? {
        // Look for pattern like "FAMILY_NAME NUMBER" at start of line
        let pattern = #"^([A-ZÄÖÅ-]+(?:\s+[IVX]+)?\s+\d+[A-Z]?)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        
        let matchRange = Range(match.range(at: 1), in: line)!
        return String(line[matchRange])
    }
    
    // MARK: - Candidate Validation
    
    /**
     * Validate a candidate family match for a person
     */
    private func validateCandidate(
        person: Person,
        family: Family,
        searchType: CrossRefType
    ) -> FamilyMatch {
        
        var confidence: Double = 0.0
        var reasons: [String] = []
        
        // Birth date match is guaranteed (0.3 points)
        confidence += 0.3
        reasons.append("Birth date match")
        
        switch searchType {
        case .asChild:
            return validateAsChildCandidate(person: person, family: family, baseConfidence: confidence, baseReasons: reasons)
        case .asParent:
            return validateAsParentCandidate(person: person, family: family, baseConfidence: confidence, baseReasons: reasons)
        case .spouseAsChild:
            return validateSpouseAsChildCandidate(person: person, family: family, baseConfidence: confidence, baseReasons: reasons)
        }
    }
    
    /**
     * Validate person as child in candidate family
     */
    private func validateAsChildCandidate(
        person: Person,
        family: Family,
        baseConfidence: Double,
        baseReasons: [String]
    ) -> FamilyMatch {
        
        var confidence = baseConfidence
        var reasons = baseReasons
        var warnings: [String] = []
        
        // Find matching child in family
        guard let matchingChild = family.findChild(named: person.name) else {
            return FamilyMatch(family: family, confidence: 0.0, reasons: [], warnings: ["Person not found as child"])
        }
        
        // Name match (0.4 points)
        if nameEquivalenceManager.areEquivalent(person.name, matchingChild.name) {
            confidence += 0.4
            reasons.append("Name match")
        } else {
            confidence += 0.2
            reasons.append("Partial name match")
            warnings.append("Name variation: \(person.name) vs \(matchingChild.name)")
        }
        
        // Patronymic match (0.2 points)
        if let personPatronymic = person.patronymic,
           let childPatronymic = matchingChild.patronymic {
            if personPatronymic.lowercased() == childPatronymic.lowercased() {
                confidence += 0.2
                reasons.append("Patronymic match")
            } else {
                warnings.append("Patronymic mismatch: \(personPatronymic) vs \(childPatronymic)")
            }
        }
        
        // Marriage info validation (0.1 points)
        if let personSpouse = person.spouse,
           let childSpouse = matchingChild.spouse {
            if nameEquivalenceManager.areEquivalent(personSpouse, childSpouse) {
                confidence += 0.1
                reasons.append("Spouse match")
            } else {
                warnings.append("Spouse name difference: \(personSpouse) vs \(childSpouse)")
            }
        }
        
        return FamilyMatch(family: family, confidence: confidence, reasons: reasons, warnings: [])
    }
    
    /**
     * Validate person as parent in candidate family
     */
    private func validateAsParentCandidate(
        person: Person,
        family: Family,
        baseConfidence: Double,
        baseReasons: [String]
    ) -> FamilyMatch {
        
        var confidence = baseConfidence
        var reasons = baseReasons
        var warnings: [String] = []
        
        // Find matching parent in family
        guard let matchingParent = family.findParent(named: person.name) else {
            return FamilyMatch(family: family, confidence: 0.0, reasons: [], warnings: ["Person not found as parent"])
        }
        
        // Name match (0.3 points)
        if nameEquivalenceManager.areEquivalent(person.name, matchingParent.name) {
            confidence += 0.3
            reasons.append("Name match")
        } else {
            confidence += 0.1
            warnings.append("Name variation: \(person.name) vs \(matchingParent.name)")
        }
        
        // Spouse match (0.3 points)
        if let personSpouse = person.spouse,
           let parentSpouse = matchingParent.spouse {
            if nameEquivalenceManager.areEquivalent(personSpouse, parentSpouse) {
                confidence += 0.3
                reasons.append("Spouse match")
            } else {
                warnings.append("Spouse name difference: \(personSpouse) vs \(parentSpouse)")
            }
        }
        
        // Marriage date match (0.1 points)
        if let personMarriage = person.bestMarriageDate,
           let parentMarriage = matchingParent.bestMarriageDate {
            if marriageDatesMatch(personMarriage, parentMarriage) {
                confidence += 0.1
                reasons.append("Marriage date match")
            } else {
                warnings.append("Marriage date difference: \(personMarriage) vs \(parentMarriage)")
            }
        }
        
        return FamilyMatch(family: family, confidence: confidence, reasons: reasons, warnings: warnings)
    }
    
    /**
     * Validate spouse as child in candidate family
     */
    private func validateSpouseAsChildCandidate(
        person: Person,
        family: Family,
        baseConfidence: Double,
        baseReasons: [String]
    ) -> FamilyMatch {
        
        var confidence = baseConfidence
        var reasons = baseReasons
        var warnings: [String] = []
        
        // Find matching child in family (by name)
        guard let matchingChild = family.findChild(named: person.name) else {
            return FamilyMatch(family: family, confidence: 0.0, reasons: [], warnings: ["Spouse not found as child"])
        }
        
        // Name match (0.4 points)
        if nameEquivalenceManager.areEquivalent(person.name, matchingChild.name) {
            confidence += 0.4
            reasons.append("Spouse name match")
        } else {
            confidence += 0.2
            warnings.append("Spouse name variation: \(person.name) vs \(matchingChild.name)")
        }
        
        // Cross-reference spouse match (0.3 points)
        if let personSpouse = person.spouse,
           let childSpouse = matchingChild.spouse {
            if nameEquivalenceManager.areEquivalent(personSpouse, childSpouse) {
                confidence += 0.3
                reasons.append("Cross-spouse match")
            } else {
                warnings.append("Cross-spouse difference: \(personSpouse) vs \(childSpouse)")
            }
        }
        
        return FamilyMatch(family: family, confidence: confidence, reasons: reasons, warnings: warnings)
    }
    
    // MARK: - Validation Helpers
    
    private func validateAsChildMatch(person: Person, family: Family) -> Bool {
        return family.children.contains { child in
            child.birthDate == person.birthDate &&
            nameEquivalenceManager.areEquivalent(child.name, person.name)
        }
    }
    
    private func validateAsParentMatch(person: Person, family: Family) -> Bool {
        return family.allParents.contains { parent in
            parent.birthDate == person.birthDate &&
            nameEquivalenceManager.areEquivalent(parent.name, person.name)
        }
    }
    
    private func marriageDatesMatch(_ date1: String, _ date2: String) -> Bool {
        // Handle cases like "1773" vs "06.11.1773" or "∞ 73" vs "1773"
        let year1 = extractYear(from: date1)
        let year2 = extractYear(from: date2)
        
        return year1 == year2
    }
    
    private func extractYear(from dateString: String) -> String? {
        // Extract 4-digit year from various formats
        let pattern = #"\b(\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: dateString, range: NSRange(dateString.startIndex..., in: dateString)) else {
            return nil
        }
        
        let matchRange = Range(match.range(at: 1), in: dateString)!
        return String(dateString[matchRange])
    }
    
    // MARK: - Name Parsing Helpers
    
    private func extractGivenName(from fullName: String) -> String {
        // Extract given name from "Elias Iso-Peitso" → "Elias"
        return fullName.components(separatedBy: " ").first ?? fullName
    }
    
    private func extractPatronymic(from fullName: String) -> String? {
        // Extract patronymic if present in format "Name Patronymic"
        let components = fullName.components(separatedBy: " ")
        guard components.count >= 2 else { return nil }
        
        let secondPart = components[1]
        
        // Check if it looks like a patronymic (ends with 'p.' or 't.')
        if secondPart.hasSuffix("p.") || secondPart.hasSuffix("t.") {
            return secondPart
        }
        
        return nil
    }
    
    // MARK: - Family Retrieval and Caching
    
    /**
     * Get family by ID with caching
     */
    private func getFamilyById(_ familyId: String) async throws -> Family {
        let normalizedId = FamilyIDs.normalize(familyId: familyId)
        
        // Check cache first
        if let cachedFamily = familyCache[normalizedId] {
            print("📋 Using cached family: \(normalizedId)")
            return cachedFamily
        }
        
        // Extract family text and parse
        guard let fileContent = fileContent else {
            throw FamilyResolverError.noFileContent
        }
        
        guard let familyText = extractFamilyText(familyId: normalizedId, from: fileContent) else {
            throw FamilyResolverError.familyNotFound(normalizedId)
        }
        
        print("🤖 Parsing family \(normalizedId) with AI...")
        let family = try await aiParsingService.parseFamily(familyId: normalizedId, familyText: familyText)
        
        // Cache the result
        familyCache[normalizedId] = family
        
        return family
    }
    
    /**
     * Extract family text from file content
     */
    private func extractFamilyText(familyId: String, from fileContent: String) -> String? {
        let lines = fileContent.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inTargetFamily = false
        var foundFamily = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for family header
            if let currentFamilyId = extractFamilyIdFromHeader(trimmedLine) {
                if currentFamilyId.uppercased() == familyId.uppercased() {
                    inTargetFamily = true
                    foundFamily = true
                    familyLines.append(line)
                } else if inTargetFamily {
                    // Started a new family, stop collecting
                    break
                } else {
                    inTargetFamily = false
                }
            } else if inTargetFamily {
                familyLines.append(line)
                
                // Stop at empty line after notes (end of family)
                if trimmedLine.isEmpty && !familyLines.isEmpty && familyLines.count > 3 {
                    // Check if we've collected enough content
                    let content = familyLines.joined(separator: "\n")
                    if content.contains("Lapset") || content.contains("★") {
                        break
                    }
                }
            }
        }
        
        guard foundFamily else {
            return nil
        }
        
        return familyLines.joined(separator: "\n")
    }
    
    // MARK: - Statistics and Monitoring
    
    func getResolutionStatistics() -> ResolutionStatistics {
        return resolutionStats
    }
    
    func resetStatistics() {
        resolutionStats = ResolutionStatistics()
    }
}

// MARK: - Supporting Data Structures

/**
 * Family network with resolved cross-references
 */
struct FamilyNetwork {
    let mainFamily: Family
    var asChildFamilies: [String: Family] = [:]      // Person name → their parent family
    var asParentFamilies: [String: Family] = [:]     // Person name → their family as parent
    var spouseAsChildFamilies: [String: Family] = [:] // Spouse name → spouse's parent family
    
    init(mainFamily: Family) {
        self.mainFamily = mainFamily
    }
    
    /// Get as_child family for a person
    func getAsChildFamily(for person: Person) -> Family? {
        return asChildFamilies[person.displayName]
    }
    
    /// Get as_parent family for a person
    func getAsParentFamily(for person: Person) -> Family? {
        return asParentFamilies[person.displayName]
    }
    
    /// Get spouse's as_child family
    func getSpouseAsChildFamily(for spouseName: String) -> Family? {
        return spouseAsChildFamilies[spouseName]
    }
    
    /// Get total count of resolved families
    var totalResolvedFamilies: Int {
        return asChildFamilies.count + asParentFamilies.count + spouseAsChildFamilies.count
    }
    
    /// Create enhanced family with cross-reference data integrated
    func createEnhancedFamily() -> Family {
        var enhancedFamily = mainFamily
        
        // Enhance children with as_parent family data
        for i in enhancedFamily.children.indices {
            let child = enhancedFamily.children[i]
            
            if let asParentFamily = getAsParentFamily(for: child) {
                // Extract enhanced death and marriage dates
                if let parentInFamily = asParentFamily.findParent(named: child.name) {
                    enhancedFamily.children[i].enhanceWithAsParentData(
                        deathDate: parentInFamily.deathDate,
                        marriageDate: parentInFamily.marriageDate
                    )
                }
                
                // Extract spouse birth date and parent family
                if let spouse = child.spouse,
                   let spouseInFamily = asParentFamily.findParent(named: spouse) {
                    enhancedFamily.children[i].enhanceWithSpouseData(
                        birthDate: spouseInFamily.birthDate,
                        parentsFamilyId: spouseInFamily.asChildReference
                    )
                }
            }
        }
        
        return enhancedFamily
    }
}

/**
 * Family match with confidence scoring
 */
struct FamilyMatch {
    let family: Family
    let confidence: Double      // 0.0 to 1.0
    let reasons: [String]       // Match justifications
    let warnings: [String]     // Potential issues
    
    init(family: Family, confidence: Double, reasons: [String], warnings: [String] = []) {
        self.family = family
        self.confidence = confidence
        self.reasons = reasons
        self.warnings = warnings
    }
}

/**
 * Resolution statistics for monitoring
 */
struct ResolutionStatistics {
    var asChildSuccess: Int = 0
    var asChildFailed: Int = 0
    var asParentSuccess: Int = 0
    var asParentFailed: Int = 0
    var spouseAsChildSuccess: Int = 0
    var spouseAsChildFailed: Int = 0
    
    mutating func recordSuccess(_ type: CrossRefType) {
        switch type {
        case .asChild:
            asChildSuccess += 1
        case .asParent:
            asParentSuccess += 1
        case .spouseAsChild:
            spouseAsChildSuccess += 1
        }
    }
    
    mutating func recordFailure(_ type: CrossRefType) {
        switch type {
        case .asChild:
            asChildFailed += 1
        case .asParent:
            asParentFailed += 1
        case .spouseAsChild:
            spouseAsChildFailed += 1
        }
    }
    
    var totalAttempts: Int {
        return asChildSuccess + asChildFailed +
               asParentSuccess + asParentFailed +
               spouseAsChildSuccess + spouseAsChildFailed
    }
    
    var totalSuccesses: Int {
        return asChildSuccess + asParentSuccess + spouseAsChildSuccess
    }
    
    var successRate: Double {
        guard totalAttempts > 0 else { return 0.0 }
        return Double(totalSuccesses) / Double(totalAttempts)
    }
}

// MARK: - Error Types

enum FamilyResolverError: LocalizedError {
    case noFileContent
    case familyNotFound(String)
    case noBirthDate(String)
    case noBirthDateMatches(String)
    case noValidMatches(String)
    case ambiguousMatches(String, [String])
    
    var errorDescription: String? {
        switch self {
        case .noFileContent:
            return "No file content loaded for family resolution"
        case .familyNotFound(let familyId):
            return "Family '\(familyId)' not found in file"
        case .noBirthDate(let personName):
            return "No birth date available for \(personName)"
        case .noBirthDateMatches(let birthDate):
            return "No families found containing birth date \(birthDate)"
        case .noValidMatches(let personName):
            return "No valid family matches found for \(personName)"
        case .ambiguousMatches(let personName, let familyIds):
            return "Ambiguous matches for \(personName): \(familyIds.joined(separator: ", "))"
        }
    }
}

