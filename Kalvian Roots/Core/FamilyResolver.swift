//
//  FamilyResolver.swift
//  Kalvian Roots
//
//  Cross-reference resolution service for genealogical family networks
//

import Foundation

/**
 * FamilyResolver.swift - Cross-reference resolution and family network building
 *
 * Resolves family cross-references using two methods:
 * 1. Family reference resolution ({KORPI 5} notation)
 * 2. Birth date search with multi-factor validation
 *
 * Builds complete family networks with confidence scoring and user validation.
 */

@Observable
class FamilyResolver {
    
    // MARK: - Dependencies
    
    private let aiParsingService: AIParsingService
    private let nameEquivalenceManager: NameEquivalenceManager
    
    // MARK: - State Properties
    
    private var fileContent: String?
    private var resolutionStatistics = ResolutionStatistics()
    
    // MARK: - Computed Properties
    
    var hasFileContent: Bool {
        fileContent != nil && !(fileContent?.isEmpty ?? true)
    }
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService, nameEquivalenceManager: NameEquivalenceManager) {
        logInfo(.resolver, "🔗 FamilyResolver initialization started")
        
        self.aiParsingService = aiParsingService
        self.nameEquivalenceManager = nameEquivalenceManager
        
        logInfo(.resolver, "✅ FamilyResolver initialized")
        logDebug(.resolver, "AI Service: \(aiParsingService.currentServiceName)")
        logDebug(.resolver, "Name Equivalence Manager ready")
    }
    
    // MARK: - File Content Management
    
    /**
     * Set the file content for cross-reference search operations
     */
    func setFileContent(_ content: String) {
        logInfo(.resolver, "📁 Setting file content for cross-reference resolution")
        logDebug(.resolver, "File content length: \(content.count) characters")
        
        self.fileContent = content
        
        // Pre-process content for efficient searching
        preprocessFileContent()
        
        logInfo(.resolver, "✅ File content set and preprocessed")
    }
    
    private func preprocessFileContent() {
        // Future optimization: Create family ID index, birth date index, etc.
        logTrace(.resolver, "File content preprocessing completed")
    }
    
    // MARK: - Main Cross-Reference Resolution Method
    
    /**
     * Resolve all cross-references for a family and build complete family network
     */
    func resolveCrossReferences(for family: Family) async throws -> FamilyNetwork {
        logInfo(.resolver, "🔗 Starting cross-reference resolution for family: \(family.familyId)")
        DebugLogger.shared.startTimer("family_network_resolution")
        
        guard hasFileContent else {
            logError(.resolver, "❌ No file content available for cross-reference resolution")
            throw FamilyResolverError.noFileContent
        }
        
        resolutionStatistics.incrementAttempt()
        
        var network = FamilyNetwork(mainFamily: family)
        
        do {
            // Step 1: Resolve as-child families (parents' families)
            logInfo(.resolver, "Step 1: Resolving as-child families")
            network = try await resolveAsChildFamilies(for: family, network: network)
            
            // Step 2: Resolve as-parent families (children's families)
            logInfo(.resolver, "Step 2: Resolving as-parent families")
            network = try await resolveAsParentFamilies(for: family, network: network)
            
            // Step 3: Resolve spouse as-child families
            logInfo(.resolver, "Step 3: Resolving spouse as-child families")
            network = try await resolveSpouseAsChildFamilies(for: family, network: network)

            resolutionStatistics.incrementSuccess()
            
            let duration = DebugLogger.shared.endTimer("family_network_resolution")
            logInfo(.resolver, "✅ Cross-reference resolution completed in \(String(format: "%.2f", duration))s")
            logDebug(.resolver, "Network summary: \(network.totalResolvedFamilies) families resolved")
            
            return network
            
        } catch {
            _ = resolutionStatistics.incrementFailure()
            DebugLogger.shared.endTimer("family_network_resolution")
            
            logError(.resolver, "❌ Cross-reference resolution failed: \(error)")
            throw error
        }
    }
    
    // MARK: - As-Child Family Resolution
    
    private func resolveAsChildFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork{
        logDebug(.resolver, "🔍 Resolving as-child families for parents")
        
        // Resolve father's as-child family
        if let fatherFamily = try await findAsChildFamily(for: family.father) {
            logInfo(.resolver, "✅ Found father's as-child family: \(fatherFamily.familyId)")
            network.asChildFamilies[family.father.name] = fatherFamily
        } else {
            logWarn(.resolver, "⚠️ Could not resolve father's as-child family")
        }
        
        // Resolve mother's as-child family
        if let mother = family.mother,
           let motherFamily = try await findAsChildFamily(for: mother) {
            logInfo(.resolver, "✅ Found mother's as-child family: \(motherFamily.familyId)")
            network.asChildFamilies[mother.name] = motherFamily
        } else if family.mother != nil {
            logWarn(.resolver, "⚠️ Could not resolve mother's as-child family")
        }
        
        // Resolve additional spouses' as-child families
        for spouse in family.additionalSpouses {
            if let spouseFamily = try await findAsChildFamily(for: spouse) {
                logInfo(.resolver, "✅ Found additional spouse's as-child family: \(spouseFamily.familyId)")
                network.asChildFamilies[spouse.name] = spouseFamily
            } else {
                logWarn(.resolver, "⚠️ Could not resolve additional spouse's as-child family")
            }
        }
    }
    
    // MARK: - As-Parent Family Resolution
    
    private func resolveAsParentFamilies(for family: Family, into network: inout FamilyNetwork) async throws {
        logDebug(.resolver, "🔍 Resolving as-parent families for children")
        
        for child in family.children {
            guard child.spouse != nil else {
                logTrace(.resolver, "Skipping unmarried child: \(child.name)")
                continue
            }
            
            if let childFamily = try await findAsParentFamily(for: child) {
                logInfo(.resolver, "✅ Found child's as-parent family: \(childFamily.familyId)")
                network.asParentFamilies[child.name] = childFamily
            } else {
                logWarn(.resolver, "⚠️ Could not resolve as-parent family for child: \(child.name)")
            }
        }
    }
    
    // MARK: - Spouse As-Child Family Resolution
    
    private func resolveSpouseAsChildFamilies(for family: Family, into network: inout FamilyNetwork) async throws {
        logDebug(.resolver, "🔍 Resolving spouse as-child families")
        
        for child in family.children {
            guard let spouse = child.spouse else { continue }
            
            // Create a temporary Person object for the spouse
            let spousePerson = Person(
                name: spouse,
                birthDate: extractSpouseBirthDate(from: child),
                spouse: child.name,
                noteMarkers: []
            )
            
            if let spouseFamily = try await findAsChildFamily(for: spousePerson) {
                logInfo(.resolver, "✅ Found spouse's as-child family: \(spouseFamily.familyId)")
                network.spouseAsChildFamilies[spouse] = spouseFamily
            } else {
                logTrace(.resolver, "Could not resolve spouse's as-child family for: \(spouse)")
            }
        }
    }
    
    // MARK: - Core Resolution Methods
    
    /**
     * Find the family where this person is a child using both resolution methods
     */
    private func findAsChildFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-child family for: \(person.name)")
        
        var candidates: [FamilyCandidate] = []
        
        // Method 1: Family reference resolution
        if let familyRef = person.asChildReference {
            logDebug(.resolver, "Trying family reference method: \(familyRef)")
            
            if let referencedFamily = try await findFamilyById(familyRef) {
                let confidence = validateFamilyReference(person, referencedFamily)
                candidates.append(FamilyCandidate(
                    family: referencedFamily,
                    confidence: confidence,
                    matchMethod: "family_reference",
                    reasons: ["Direct family reference match"],
                    warnings: confidence < 0.8 ? ["Low confidence family reference"] : []
                ))
                logDebug(.resolver, "Family reference candidate: \(referencedFamily.familyId), confidence: \(String(format: "%.2f", confidence))")
            }
        }
        
        // Method 2: Birth date search
        if let birthDate = person.birthDate {
            logDebug(.resolver, "Trying birth date search method: \(birthDate)")
            
            let birthDateCandidates = try await searchByBirthDate(birthDate, targetPerson: person)
            candidates.append(contentsOf: birthDateCandidates)
            
            logDebug(.resolver, "Birth date search found \(birthDateCandidates.count) candidates")
        }
        
        // Sort by confidence and return best match
        let sortedCandidates = candidates.sorted { $0.confidence > $1.confidence }
        
        if let bestCandidate = sortedCandidates.first {
            logInfo(.resolver, "Best match: \(bestCandidate.family.familyId) (confidence: \(String(format: "%.2f", bestCandidate.confidence)), method: \(bestCandidate.matchMethod))")
            
            if bestCandidate.confidence >= 0.8 {
                return bestCandidate.family
            } else if bestCandidate.confidence >= 0.5 {
                logWarn(.resolver, "Medium confidence match - may require user validation")
                return bestCandidate.family
            } else {
                logWarn(.resolver, "Low confidence match - skipping")
                return nil
            }
        }
        
        logDebug(.resolver, "No suitable as-child family found for: \(person.name)")
        return nil
    }
    
    /**
     * Find the family where this person is a parent using asParentReference
     */
    private func findAsParentFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-parent family for: \(person.name)")
        
        guard let parentRef = person.asParentReference else {
            logTrace(.resolver, "No as-parent reference for: \(person.name)")
            return nil
        }
        
        return try await findFamilyById(parentRef)
    }
    
    // MARK: - Family Search Methods
    
    /**
     * Find family by ID in the file content
     */
    private func findFamilyById(_ familyId: String) async throws -> Family? {
        logDebug(.resolver, "🔍 Searching for family: \(familyId)")
        
        guard let fileContent = fileContent else {
            throw FamilyResolverError.noFileContent
        }
        
        // Extract family text from file content
        guard let familyText = extractFamilyText(familyId: familyId, from: fileContent) else {
            logWarn(.resolver, "Family \(familyId) not found in file")
            return nil
        }
        
        // Parse the family using AI service
        do {
            let family = try await aiParsingService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            logInfo(.resolver, "✅ Successfully parsed family: \(familyId)")
            return family
            
        } catch {
            logError(.resolver, "❌ Failed to parse family \(familyId): \(error)")
            return nil
        }
    }
    
    /**
     * Search for families by birth date with multi-factor validation
     */
    private func searchByBirthDate(_ birthDate: String, targetPerson: Person) async throws -> [FamilyCandidate] {
        logDebug(.resolver, "🔍 Searching by birth date: \(birthDate)")
        
        guard let fileContent = fileContent else {
            throw FamilyResolverError.noFileContent
        }
        
        var candidates: [FamilyCandidate] = []
        
        // Find all occurrences of the birth date in the file
        let birthDateMatches = findBirthDateOccurrences(birthDate, in: fileContent)
        
        logDebug(.resolver, "Found \(birthDateMatches.count) birth date matches")
        
        for match in birthDateMatches {
            // Extract the family containing this birth date
            if let familyId = extractFamilyIdFromMatch(match),
               let family = try await findFamilyById(familyId) {
                
                // Find the person in this family with the matching birth date
                if let matchingPerson = findPersonWithBirthDate(birthDate, in: family) {
                    
                    // Validate if this person could be our target person
                    let confidence = calculateMatchConfidence(targetPerson, matchingPerson, family)
                    
                    if confidence > 0.3 { // Minimum threshold
                        candidates.append(FamilyCandidate(
                            family: family,
                            confidence: confidence,
                            matchMethod: "birth_date_search",
                            reasons: buildMatchReasons(targetPerson, matchingPerson),
                            warnings: confidence < 0.8 ? ["Uncertain match - requires validation"] : []
                        ))
                    }
                }
            }
        }
        
        return candidates
    }
    
    // MARK: - Validation and Confidence Scoring
    
    private func validateFamilyReference(_ person: Person, _ family: Family) -> Double {
        var confidence = 0.5 // Base confidence for family reference
        
        // Check if person appears as child in this family
        let isChild = family.children.contains { child in
            isNameMatch(person.name, child.name)
        }
        
        if isChild {
            confidence += 0.3
        }
        
        // Validate spouse information if available
        if let personSpouse = person.spouse {
            let spouseInFamily = family.children.contains { child in
                child.spouse != nil && isNameMatch(personSpouse, child.spouse!)
            }
            if spouseInFamily {
                confidence += 0.2
            }
        }
        
        return min(confidence, 1.0)
    }
    
    private func calculateMatchConfidence(_ target: Person, _ candidate: Person, _ family: Family) -> Double {
        var confidence = 0.0
        
        // Birth date match (guaranteed if we found them this way)
        confidence += 0.3
        
        // Name match
        if isNameMatch(target.name, candidate.name) {
            confidence += 0.4
        } else if isNameVariant(target.name, candidate.name) {
            confidence += 0.2
        }
        
        // Spouse match
        if let targetSpouse = target.spouse,
           let candidateSpouse = candidate.spouse {
            if isNameMatch(targetSpouse, candidateSpouse) {
                confidence += 0.2
            } else if isNameVariant(targetSpouse, candidateSpouse) {
                confidence += 0.1
            }
        }
        
        // Marriage date/year match
        if let targetMarriage = target.marriageDate,
           let candidateMarriage = candidate.marriageDate {
            if isMarriageDateMatch(targetMarriage, candidateMarriage) {
                confidence += 0.2
            }
        }
        
        return min(confidence, 1.0)
    }
    
    // MARK: - Helper Methods
    
    private func extractFamilyText(familyId: String, from fileContent: String) -> String? {
        logTrace(.resolver, "Extracting text for family: \(familyId)")
        
        let lines = fileContent.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inFamily = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this line starts the target family
            if trimmedLine.uppercased().hasPrefix(familyId.uppercased()) {
                inFamily = true
                familyLines.append(line)
                continue
            }
            
            // If we're in a family and hit another family ID, stop
            if inFamily && trimmedLine.contains(" ") {
                let firstPart = trimmedLine.components(separatedBy: " ").first ?? ""
                if FamilyIDs.validFamilyIds.contains(where: { firstPart.uppercased().hasPrefix($0) }) {
                    break
                }
            }
            
            // Collect lines while in the target family
            if inFamily {
                familyLines.append(line)
            }
        }
        
        guard !familyLines.isEmpty else {
            return nil
        }
        
        return familyLines.joined(separator: "\n")
    }
    
    private func findBirthDateOccurrences(_ birthDate: String, in content: String) -> [BirthDateMatch] {
        var matches: [BirthDateMatch] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            if line.contains(birthDate) {
                matches.append(BirthDateMatch(
                    lineNumber: index,
                    line: line,
                    birthDate: birthDate
                ))
            }
        }
        
        return matches
    }
    
    private func extractFamilyIdFromMatch(_ match: BirthDateMatch) -> String? {
        // Implementation to find the family ID that contains this birth date match
        // This would scan backwards/forwards from the match to find the family header
        // Simplified implementation for now
        return nil
    }
    
    private func findPersonWithBirthDate(_ birthDate: String, in family: Family) -> Person? {
        // Check all family members for matching birth date
        let allPersons = [family.father] +
                        (family.mother.map { [$0] } ?? []) +
                        family.additionalSpouses +
                        family.children
        
        return allPersons.first { person in
            person.birthDate == birthDate
        }
    }
    
    private func isNameMatch(_ name1: String, _ name2: String) -> Bool {
        let normalized1 = name1.lowercased().trimmingCharacters(in: .whitespaces)
        let normalized2 = name2.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized1 == normalized2
    }
    
    private func isNameVariant(_ name1: String, _ name2: String) -> Bool {
        return nameEquivalenceManager.areEquivalent(name1, name2)
    }
    
    private func isMarriageDateMatch(_ date1: String, _ date2: String) -> Bool {
        // Handle various date formats and partial matches
        let year1 = extractYear(from: date1)
        let year2 = extractYear(from: date2)
        return year1 == year2 && year1 != nil
    }
    
    private func extractYear(from dateString: String) -> String? {
        // Extract 4-digit year or convert 2-digit year to 4-digit
        let components = dateString.components(separatedBy: CharacterSet.decimalDigits.inverted)
        for component in components {
            if component.count == 4 {
                return component
            } else if component.count == 2, let year = Int(component) {
                return "17\(component)" // Assume 1700s
            }
        }
        return nil
    }
    
    private func extractSpouseBirthDate(from child: Person) -> String? {
        // Try to extract spouse birth date from marriage information
        // This would be implemented based on the specific format patterns
        return nil
    }
    
    private func buildMatchReasons(_ target: Person, _ candidate: Person) -> [String] {
        var reasons: [String] = []
        
        if isNameMatch(target.name, candidate.name) {
            reasons.append("Exact name match")
        } else if isNameVariant(target.name, candidate.name) {
            reasons.append("Name variant match")
        }
        
        if let targetSpouse = target.spouse,
           let candidateSpouse = candidate.spouse,
           isNameMatch(targetSpouse, candidateSpouse) {
            reasons.append("Spouse name match")
        }
        
        return reasons
    }
    
    // MARK: - Statistics and Monitoring
    
    func getResolutionStatistics() -> ResolutionStatistics {
        return resolutionStatistics
    }
    
    func resetStatistics() {
        resolutionStatistics = ResolutionStatistics()
        logInfo(.resolver, "Resolution statistics reset")
    }
}

// MARK: - Supporting Data Structures

/**
 * Family candidate with confidence scoring
 */
struct FamilyCandidate {
    let family: Family
    let confidence: Double
    let matchMethod: String
    let reasons: [String]
    let warnings: [String]
}

/**
 * Birth date match information
 */
struct BirthDateMatch {
    let lineNumber: Int
    let line: String
    let birthDate: String
}

/**
 * Resolution statistics tracking
 */
struct ResolutionStatistics {
    private(set) var totalAttempts: Int = 0
    private(set) var totalSuccesses: Int = 0
    private(set) var totalFailures: Int = 0
    
    var successRate: Double {
        guard totalAttempts > 0 else { return 0.0 }
        return Double(totalSuccesses) / Double(totalAttempts)
    }
    
    mutating func incrementAttempt() {
        totalAttempts += 1
    }
    
    mutating func incrementSuccess() {
        totalSuccesses += 1
    }
    
    mutating func incrementFailure() {
        totalFailures += 1
    }
}

/**
 * Family network structure containing all resolved cross-references
 */
struct FamilyNetwork {
    let mainFamily: Family
    var asChildFamilies: [String: Family] = [:]      // Person name -> their parent family
    var asParentFamilies: [String: Family] = [:]     // Person name -> their family as parent
    var spouseAsChildFamilies: [String: Family] = [:] // Spouse name -> spouse's parent family
    
    var totalResolvedFamilies: Int {
        return 1 + asChildFamilies.count + asParentFamilies.count + spouseAsChildFamilies.count
    }
    
    /**
     * Create enhanced family with integrated cross-reference data
     */
    func createEnhancedFamily() -> Family {
        var enhanced = mainFamily
        
        // Enhance each person with cross-reference data
        enhanced = Family(
            familyId: enhanced.familyId,
            pageReferences: enhanced.pageReferences,
            father: enhancePersonWithCrossRefData(enhanced.father),
            mother: enhanced.mother.map { enhancePersonWithCrossRefData($0) },
            additionalSpouses: enhanced.additionalSpouses.map { enhancePersonWithCrossRefData($0) },
            children: enhanced.children.map { enhancePersonWithCrossRefData($0) },
            notes: enhanced.notes,
            childrenDiedInfancy: enhanced.childrenDiedInfancy
        )
        
        return enhanced
    }
    
    private func enhancePersonWithCrossRefData(_ person: Person) -> Person {
        var enhanced = person
        
        // Add enhanced data from as-parent family
        if let asParentFamily = asParentFamilies[person.name] {
            // Find this person in their as-parent family and extract enhanced data
            if let asParent = asParentFamily.father.name == person.name ? asParentFamily.father :
                              asParentFamily.mother?.name == person.name ? asParentFamily.mother : nil {
                enhanced.enhancedDeathDate = asParent.deathDate
                enhanced.enhancedMarriageDate = asParent.marriageDate
            }
        }
        
        // Add spouse birth date from spouse's as-child family
        if let spouseName = person.spouse,
           let spouseAsChildFamily = spouseAsChildFamilies[spouseName] {
            // Find spouse birth date in their parent family
            let allPersons = [spouseAsChildFamily.father] +
                           (spouseAsChildFamily.mother.map { [$0] } ?? []) +
                           spouseAsChildFamily.children
            
            if let spouseInFamily = allPersons.first(where: { $0.name == spouseName }) {
                enhanced.spouseBirthDate = spouseInFamily.birthDate
            }
        }
        
        return enhanced
    }
}

/**
 * FamilyResolver specific errors
 */
enum FamilyResolverError: LocalizedError {
    case noFileContent
    case familyNotFound(String)
    case resolutionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noFileContent:
            return "No file content available for cross-reference resolution"
        case .familyNotFound(let familyId):
            return "Family \(familyId) not found in file"
        case .resolutionFailed(let reason):
            return "Cross-reference resolution failed: \(reason)"
        }
    }
}
