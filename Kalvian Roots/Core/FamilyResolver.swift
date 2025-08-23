//
//  FamilyResolver.swift
//  Kalvian Roots
//
//  Cross-reference resolution with enhanced debug logging
//

import Foundation

/**
 * FamilyResolver - Cross-reference resolution and family network building
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
        
        // Debug log what we're looking for
        debugLogResolutionAttempt(family)
        
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
            
            // Final debug summary
            debugLogResolutionSummary(network)
            
            return network
            
        } catch {
            resolutionStatistics.incrementFailure()
            logError(.resolver, "❌ Cross-reference resolution failed: \(error)")
            throw error
        }
    }
    
    // MARK: - As-Child Family Resolution (Parents' Families)
    
    private func resolveAsChildFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        var updatedNetwork = network
        
        logInfo(.resolver, "👨‍👩 Resolving as-child families for parents")
        
        for parent in family.allParents {
            if let asChildRef = parent.asChild {
                logInfo(.resolver, "🔍 Attempting to resolve as_child: \(parent.displayName) from \(asChildRef)")
                
                if let resolvedFamily = try await findAsChildFamily(for: parent) {
                    updatedNetwork.asChildFamilies[parent.name] = resolvedFamily
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: true, type: "as_child")
                    logInfo(.resolver, "  ✅ Found: \(resolvedFamily.familyId)")
                } else {
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: false, type: "as_child")
                    logWarn(.resolver, "  ⚠️ Not found: \(asChildRef)")
                }
            }
        }
        
        logInfo(.resolver, "  Resolved \(updatedNetwork.asChildFamilies.count) as-child families")
        return updatedNetwork
    }
    
    // MARK: - As-Parent Family Resolution (Children's Families)
    
    private func resolveAsParentFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        var updatedNetwork = network
        
        logInfo(.resolver, "👶 Resolving as-parent families for children")
        
        for child in family.children {
            if let asParentRef = child.asParent {
                logInfo(.resolver, "🔍 Attempting to resolve as_parent: \(child.displayName) to \(asParentRef)")
                
                if let resolvedFamily = try await findAsParentFamily(for: child) {
                    updatedNetwork.asParentFamilies[child.name] = resolvedFamily
                    debugLogResolutionResult(for: child.displayName, reference: asParentRef, success: true, type: "as_parent")
                    logInfo(.resolver, "  ✅ Found: \(resolvedFamily.familyId)")
                } else {
                    debugLogResolutionResult(for: child.displayName, reference: asParentRef, success: false, type: "as_parent")
                    logWarn(.resolver, "  ⚠️ Not found: \(asParentRef)")
                }
            }
        }
        
        logInfo(.resolver, "  Resolved \(updatedNetwork.asParentFamilies.count) as-parent families")
        return updatedNetwork
    }
    
    // MARK: - Spouse As-Child Family Resolution
    
    private func resolveSpouseAsChildFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        var updatedNetwork = network
        
        logInfo(.resolver, "💑 Resolving spouse as-child families")
        
        // For each married child, try to find their spouse's family of origin
        for child in family.marriedChildren {
            if let spouseName = child.spouse {
                logDebug(.resolver, "Looking for spouse family: \(spouseName)")
                
                if let spouseFamily = try await findSpouseAsChildFamily(spouseName: spouseName) {
                    updatedNetwork.spouseAsChildFamilies[spouseName] = spouseFamily
                    logInfo(.resolver, "  ✅ Found spouse family for: \(spouseName)")
                }
            }
        }
        
        logInfo(.resolver, "  Resolved \(updatedNetwork.spouseAsChildFamilies.count) spouse families")
        return updatedNetwork
    }
    
    // MARK: - Individual Family Finding Methods
    
    private func findAsChildFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-child family for: \(person.displayName)")
        
        // Method 1: Try family reference resolution first
        if let asChildRef = person.asChild {
            logDebug(.resolver, "Found as-child reference: \(asChildRef)")
            return try await resolveFamilyByReference(asChildRef)
        }
        
        // Method 2: Try birth date search (fallback)
        if let birthDate = person.birthDate {
            logDebug(.resolver, "Trying birth date search for: \(birthDate)")
            if let family = try await findFamilyByBirthDate(person: person) {
                return family
            }
        }
        
        logWarn(.resolver, "⚠️ No resolution method available for: \(person.displayName)")
        return nil
    }
    
    private func findAsParentFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-parent family for: \(person.displayName)")
        
        // Method 1: Try family reference resolution first
        if let asParentRef = person.asParent {
            logDebug(.resolver, "Found as-parent reference: \(asParentRef)")
            return try await resolveFamilyByReference(asParentRef)
        }
        
        // Method 2: Try spouse-based search
        if let spouse = person.spouse {
            logDebug(.resolver, "Trying spouse-based search for: \(spouse)")
            if let family = try await findFamilyBySpouse(person: person) {
                return family
            }
        }
        
        logWarn(.resolver, "⚠️ No resolution method available for: \(person.displayName)")
        return nil
    }
    
    private func findSpouseAsChildFamily(spouseName: String) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding spouse's as-child family for: \(spouseName)")
        
        // This would involve searching for the spouse as a child in some family
        // Implementation depends on the specific text format
        
        logWarn(.resolver, "⚠️ Spouse as-child family resolution not yet implemented")
        return nil
    }
    
    // MARK: - Resolution Methods
    
    private func resolveFamilyByReference(_ familyId: String) async throws -> Family? {
        logDebug(.resolver, "🔍 Resolving family by reference: \(familyId)")
        
        guard let fileContent = fileContent else {
            throw FamilyResolverError.noFileContent
        }
        
        // Extract family text for the referenced family ID
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let familyText = extractFamilyText(familyId: normalizedId, from: fileContent) {
            logDebug(.resolver, "Found family text for: \(normalizedId)")
            
            do {
                let family = try await aiParsingService.parseFamily(familyId: normalizedId, familyText: familyText)
                logInfo(.resolver, "✅ Successfully resolved family: \(normalizedId)")
                return family
            } catch {
                logError(.resolver, "❌ Failed to parse referenced family \(normalizedId): \(error)")
                throw FamilyResolverError.crossReferenceFailed("Failed to parse family \(normalizedId)")
            }
        } else {
            logWarn(.resolver, "⚠️ Family text not found for: \(normalizedId)")
            return nil
        }
    }
    
    // MARK: - Debug Logging Methods
    
    /// Enhanced debug logging for cross-reference resolution
    private func debugLogResolutionAttempt(_ family: Family) {
        logInfo(.resolver, "🎯 === STARTING RESOLUTION DEBUG ===")
        logInfo(.resolver, "📋 Resolving for family: \(family.familyId)")
        
        // Log what we're looking for
        logInfo(.resolver, "🔍 CROSS-REFERENCES TO RESOLVE:")
        
        // Parents as-child references (where they came from)
        let parentRefs = family.allParents.compactMap { parent in
            parent.asChild.map { ref in
                "\(parent.displayName) came from → \(ref)"
            }
        }
        
        if !parentRefs.isEmpty {
            logInfo(.resolver, "👨‍👩 PARENT ORIGINS (as_child):")
            for ref in parentRefs {
                logInfo(.resolver, "  - \(ref)")
            }
        } else {
            logWarn(.resolver, "  ⚠️ No parent as_child references found")
        }
        
        // Children as-parent references (where they went)
        let childRefs = family.children.compactMap { child in
            child.asParent.map { ref in
                "\(child.displayName) created family → \(ref)"
            }
        }
        
        if !childRefs.isEmpty {
            logInfo(.resolver, "👶 CHILDREN'S FAMILIES (as_parent):")
            for ref in childRefs {
                logInfo(.resolver, "  - \(ref)")
            }
        } else {
            logWarn(.resolver, "  ⚠️ No child as_parent references found")
        }
        
        logInfo(.resolver, "📊 Total references to resolve: \(parentRefs.count + childRefs.count)")
        logInfo(.resolver, "🎯 === END RESOLUTION DEBUG ===")
    }
 
    /// Debug log for each resolution attempt
    private func debugLogResolutionResult(for person: String, reference: String, success: Bool, type: String) {
        if success {
            logInfo(.resolver, "✅ RESOLVED: \(person) → \(reference) (\(type))")
        } else {
            logError(.resolver, "❌ FAILED: \(person) → \(reference) (\(type))")
        }
    }
    
    /// Debug log the final resolution summary
    private func debugLogResolutionSummary(_ network: FamilyNetwork) {
        logInfo(.resolver, "📊 === RESOLUTION SUMMARY ===")
        logInfo(.resolver, "Main Family: \(network.mainFamily.familyId)")
        logInfo(.resolver, "Total Resolved: \(network.totalResolvedFamilies) families")
        
        if !network.asChildFamilies.isEmpty {
            logInfo(.resolver, "👨‍👩 Parent Origins (as-child families): \(network.asChildFamilies.count)")
            for (person, family) in network.asChildFamilies {
                logInfo(.resolver, "  - \(person) from \(family.familyId)")
            }
        }
        
        if !network.asParentFamilies.isEmpty {
            logInfo(.resolver, "👶 Children's Families (as-parent families): \(network.asParentFamilies.count)")
            for (person, family) in network.asParentFamilies {
                logInfo(.resolver, "  - \(person) created \(family.familyId)")
            }
        }
        
        if !network.spouseAsChildFamilies.isEmpty {
            logInfo(.resolver, "💑 Spouse Origins: \(network.spouseAsChildFamilies.count)")
            for (spouse, family) in network.spouseAsChildFamilies {
                logInfo(.resolver, "  - \(spouse) from \(family.familyId)")
            }
        }
        
        logInfo(.resolver, "📊 === END SUMMARY ===")
    }
    
    // MARK: - Birth Date Search Methods
    
    private func findFamilyByBirthDate(person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding family by birth date for: \(person.displayName)")
        
        guard let birthDate = person.birthDate,
              let fileContent = fileContent else {
            return nil
        }
        
        // Search for birth date in file content
        let candidates = await searchForBirthDate(birthDate, in: fileContent)
        
        if candidates.isEmpty {
            logWarn(.resolver, "⚠️ No families found with birth date: \(birthDate)")
            return nil
        }
        
        // Score candidates and pick best match
        let scoredCandidates = scoreCandidates(candidates, for: person)
        
        if let bestCandidate = scoredCandidates.first {
            logInfo(.resolver, "✅ Found best candidate family: \(bestCandidate.family.familyId) (confidence: \(bestCandidate.confidence))")
            return bestCandidate.family
        }
        
        return nil
    }
    
    private func findFamilyBySpouse(person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding family by spouse for: \(person.displayName)")
        
        // Implementation would search for families where person appears as parent with their spouse
        logWarn(.resolver, "⚠️ Spouse-based family resolution not yet implemented")
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func extractFamilyText(familyId: String, from content: String) -> String? {
        // This should use the same family extraction logic as in FileManager
        // For now, return a simplified implementation
        
        let lines = content.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inFamily = false
        var foundFamily = false
        
        for line in lines {
            if line.uppercased().contains(familyId.uppercased()) {
                inFamily = true
                foundFamily = true
                familyLines.append(line)
            } else if inFamily {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && foundFamily {
                    // End of family section
                    break
                } else {
                    familyLines.append(line)
                }
            }
        }
        
        return foundFamily ? familyLines.joined(separator: "\n") : nil
    }
    
    private func searchForBirthDate(_ birthDate: String, in content: String) async -> [Family] {
        logDebug(.resolver, "Searching for birth date: \(birthDate)")
        var families: [Family] = []
        // Grep-like scan: collect family blocks that contain the birthDate string
        let lines = content.components(separatedBy: .newlines)
        var buffer: [String] = []
        var inFamily = false
        var currentHeader: String?

        func flushIfContainsDate() async {
            guard let header = currentHeader else { return }
            let block = buffer.joined(separator: "\n")
            if block.contains(birthDate) {
                // Extract ID from header, reuse main parser to build Family
                if let id = extractFamilyIdFromHeader(header), let text = extractFamilyText(familyId: id, from: content) {
                    if let fam = try? await awaitParse(familyId: id, text: text) { families.append(fam) }
                }
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let _ = extractFamilyIdFromHeader(trimmed) {
                if inFamily { await flushIfContainsDate() }
                inFamily = true
                currentHeader = trimmed
                buffer = [line]
            } else if inFamily {
                buffer.append(line)
                if trimmed.isEmpty { // family delimiter heuristic
                    await flushIfContainsDate()
                    inFamily = false
                    buffer.removeAll()
                    currentHeader = nil
                }
            }
        }
        if inFamily { await flushIfContainsDate() }
        return families
    }

    private func awaitParse(familyId: String, text: String) async -> Family? {
        do { return try await aiParsingService.parseFamily(familyId: familyId, familyText: text) }
        catch { return nil }
    }

    private func extractFamilyIdFromHeader(_ line: String) -> String? {
        let pattern = #"^([A-ZÄÖÅ-]+(?:\s+[IVX]+)?\s+\d+[A-Z]?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        let matchRange = Range(match.range(at: 1), in: line)!
        return String(line[matchRange])
    }
    
    private func scoreCandidates(_ candidates: [Family], for person: Person) -> [FamilyMatch] {
        // Score on: birth date match, name or name-equivalence, spouse (or variant), marriage year (last two digits)
        func lastTwo(_ year: String?) -> String? {
            guard let year = year, year.count >= 2 else { return nil }
            return String(year.suffix(2))
        }

        let scored: [FamilyMatch] = candidates.compactMap { family in
            var score: Double = 0.0
            var reasons: [String] = []
            
            // Check if person is a child in this family
            if let child = family.findChild(named: person.name) {
                score += 0.4; reasons.append("name match")
                
                if child.birthDate == person.birthDate {
                    score += 0.3; reasons.append("birth date match")
                }
                
                if let personSpouse = person.spouse, let childSpouse = child.spouse {
                    if nameEquivalenceManager.areNamesEquivalent(personSpouse, childSpouse) {
                        score += 0.2; reasons.append("spouse match")
                    }
                }
                
                // Check marriage year (last two digits)
                if let personMarriage = lastTwo(person.marriageDate),
                   let childMarriage = lastTwo(child.marriageDate),
                   personMarriage == childMarriage {
                    score += 0.15; reasons.append("marriage year match (yy)")
                }
            }

            return FamilyMatch(family: family, confidence: min(score, 1.0), reasons: reasons, warnings: [])
        }

        return scored.sorted { $0.confidence > $1.confidence }
    }
    
    // MARK: - Date Utilities
    
    private func extractYearFromDate(_ date: String) -> Int? {
        let components = date.components(separatedBy: ".")
        if components.count >= 3, let year = Int(components[2]) {
            return year
        }
        return nil
    }
}

// MARK: - Supporting Data Structures

/**
 * Complete family network with all cross-references resolved
 */
struct FamilyNetwork {
    let mainFamily: Family
    var asChildFamilies: [String: Family] = [:]      // Parent families
    var asParentFamilies: [String: Family] = [:]     // Children's families
    var spouseAsChildFamilies: [String: Family] = [:] // Spouse parent families
    
    init(mainFamily: Family) {
        self.mainFamily = mainFamily
    }
    
    var totalResolvedFamilies: Int {
        return asChildFamilies.count + asParentFamilies.count + spouseAsChildFamilies.count
    }
    
    func getAsChildFamily(for person: Person) -> Family? {
        return asChildFamilies[person.name]
    }
    
    func getAsParentFamily(for person: Person) -> Family? {
        return asParentFamilies[person.name]
    }
    
    func getSpouseAsChildFamily(for familyId: String) -> Family? {
        return spouseAsChildFamilies[familyId]
    }
}

/**
 * Family match with confidence scoring
 */
struct FamilyMatch {
    let family: Family
    let confidence: Double      // 0.0 to 1.0
    let reasons: [String]       // Match justifications
    let warnings: [String]      // Potential issues
}

/**
 * Resolution statistics for debugging and optimization
 */
struct ResolutionStatistics {
    private var attempts: Int = 0
    private var successes: Int = 0
    private var failures: Int = 0
    
    mutating func incrementAttempt() { attempts += 1 }
    mutating func incrementSuccess() { successes += 1 }
    mutating func incrementFailure() { failures += 1 }
    
    var successRate: Double {
        guard attempts > 0 else { return 0.0 }
        return Double(successes) / Double(attempts)
    }
}

/**
 * Family resolver specific errors
 */
enum FamilyResolverError: LocalizedError {
    case noFileContent
    case crossReferenceFailed(String)
    case ambiguousMatch([Family])
    case noMatchFound(String)
    
    var errorDescription: String? {
        switch self {
        case .noFileContent:
            return "No file content available for cross-reference resolution"
        case .crossReferenceFailed(let message):
            return "Cross-reference resolution failed: \(message)"
        case .ambiguousMatch(let families):
            return "Multiple families matched: \(families.map { $0.familyId }.joined(separator: ", "))"
        case .noMatchFound(let criteria):
            return "No family found matching: \(criteria)"
        }
    }
}
