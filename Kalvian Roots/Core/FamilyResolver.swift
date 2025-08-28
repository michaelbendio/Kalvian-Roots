//
//  FamilyResolver.swift
//  Kalvian Roots
//
//  Cross-reference resolution with enhanced debug logging - MEMORY EFFICIENT VERSION
//

import Foundation

// MARK: - ResolutionStatistics

/**
 * Tracks success rates for cross-reference resolution
 */
struct ResolutionStatistics {
    private var attempts = 0
    private var successes = 0
    private var failures = 0
    
    mutating func incrementAttempt() {
        attempts += 1
    }
    
    mutating func incrementSuccess() {
        successes += 1
    }
    
    mutating func incrementFailure() {
        failures += 1
    }
    
    var successRate: Double {
        return attempts > 0 ? Double(successes) / Double(attempts) : 0.0
    }
    
    var summary: String {
        return "Attempts: \(attempts), Successes: \(successes), Failures: \(failures), Rate: \(String(format: "%.1f", successRate * 100))%"
    }
}

// MARK: - FamilyResolver

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
    
    // MARK: - Dependencies (Memory Efficient)
    
    private let aiParsingService: AIParsingService
    private let nameEquivalenceManager: NameEquivalenceManager
    private let fileManager: Kalvian_Roots.FileManager  // Reference instead of content copy
    
    // MARK: - State Properties
    
    private var resolutionStatistics = ResolutionStatistics()
    
    // MARK: - Computed Properties
    
    var hasFileContent: Bool {
        fileManager.isFileLoaded
    }
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService,
         nameEquivalenceManager: NameEquivalenceManager,
         fileManager: Kalvian_Roots.FileManager) {
        logInfo(.resolver, "🔗 FamilyResolver initialization started")
        
        self.aiParsingService = aiParsingService
        self.nameEquivalenceManager = nameEquivalenceManager
        self.fileManager = fileManager
        
        logInfo(.resolver, "✅ FamilyResolver initialized with FileManager reference")
        logDebug(.resolver, "AI Service: \(aiParsingService.currentServiceName)")
        logDebug(.resolver, "Name Equivalence Manager ready")
        logDebug(.resolver, "FileManager reference attached - no content stored in memory")
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
            throw JuuretError.noFileContent
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
                    // FIXED: Use trimmed name as consistent key
                    let storageKey = parent.name.trimmingCharacters(in: .whitespaces)
                    updatedNetwork.asChildFamilies[storageKey] = resolvedFamily
                    
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: true, type: "as_child")
                    logInfo(.resolver, "  ✅ Resolved: \(asChildRef) - stored with key '\(storageKey)'")
                } else {
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: false, type: "as_child")
                    logWarn(.resolver, "  ⚠️ Not found: \(asChildRef)")
                }
            }
        }
        
        logInfo(.resolver, "  Resolved \(updatedNetwork.asChildFamilies.count) as-child families")
        logInfo(.resolver, "  Storage keys: \(Array(updatedNetwork.asChildFamilies.keys))")
        return updatedNetwork
    }
    
    // MARK: - As-Parent Family Resolution (Children's Families)
    
    private func resolveAsParentFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        var updatedNetwork = network
        
        logInfo(.resolver, "👶 Resolving as-parent families for married children")
        
        for child in family.marriedChildren {
            if let asParentRef = child.asParent {
                logInfo(.resolver, "🔍 Attempting to resolve as_parent: \(child.displayName) in \(asParentRef)")
                
                if let resolvedFamily = try await findAsParentFamily(for: child) {
                    // FIXED: Use trimmed name as consistent key
                    let storageKey = child.name.trimmingCharacters(in: .whitespaces)
                    updatedNetwork.asParentFamilies[storageKey] = resolvedFamily
                    
                    debugLogResolutionResult(for: child.displayName, reference: asParentRef, success: true, type: "as_parent")
                    logInfo(.resolver, "  ✅ Resolved: \(asParentRef) - stored with key '\(storageKey)'")
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
        // FIXED: Use correct property name
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
        // FIXED: Use correct property name
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
    
    // MARK: - Resolution Methods (Using FileManager - MEMORY EFFICIENT)
    
    private func resolveFamilyByReference(_ familyId: String) async throws -> Family? {
        logDebug(.resolver, "🔍 Resolving family by reference: \(familyId)")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // FIXED: Use FileManager instead of keeping content in memory
        if let familyText = fileManager.extractFamilyText(familyId: normalizedId) {
            logDebug(.resolver, "Found family text for: \(normalizedId)")
            
            do {
                let family = try await aiParsingService.parseFamily(familyId: normalizedId, familyText: familyText)
                logInfo(.resolver, "✅ Successfully resolved family: \(normalizedId)")
                return family
            } catch {
                logError(.resolver, "❌ Failed to parse referenced family \(normalizedId): \(error)")
                throw JuuretError.crossReferenceFailed("Failed to parse family \(normalizedId)")
            }
        } else {
            logWarn(.resolver, "⚠️ Family text not found for: \(normalizedId)")
            return nil
        }
    }
    
    private func findFamilyByBirthDate(person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding family by birth date for: \(person.displayName)")
        
        guard let birthDate = person.birthDate,
              let fileContent = fileManager.currentFileContent else {
            return nil
        }
        
        let families = await searchForBirthDate(birthDate, in: fileContent)
        
        // Filter families that could match this person
        let candidates = families.filter { family in
            return validatePersonMatch(person: person, inFamily: family)
        }
        
        if candidates.count == 1 {
            logInfo(.resolver, "✅ Found unique family match by birth date")
            return candidates.first
        } else if candidates.count > 1 {
            logWarn(.resolver, "⚠️ Multiple families match birth date - need more criteria")
            return nil
        } else {
            logWarn(.resolver, "⚠️ No families match birth date")
            return nil
        }
    }
    
    private func findFamilyBySpouse(person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding family by spouse for: \(person.displayName)")
        
        // Implementation would search for families where person appears as parent with their spouse
        logWarn(.resolver, "⚠️ Spouse-based family resolution not yet implemented")
        return nil
    }
    
    // MARK: - Helper Methods (Using FileManager)
    
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
                // Extract ID from header, use FileManager to get clean family text
                if let id = extractFamilyIdFromHeader(header),
                   let text = fileManager.extractFamilyText(familyId: id) {
                    if let fam = try? await aiParsingService.parseFamily(familyId: id, familyText: text) {
                        families.append(fam)
                    }
                }
            }
            buffer.removeAll()
        }

        for line in lines {
            if let familyId = extractFamilyIdFromHeader(line) {
                // New family starts
                await flushIfContainsDate()
                currentHeader = line
                inFamily = true
                buffer.append(line)
            } else if inFamily {
                buffer.append(line)
            }
        }

        await flushIfContainsDate() // Don't forget the last family
        
        logDebug(.resolver, "Found \(families.count) families containing birth date")
        return families
    }

    private func extractFamilyIdFromHeader(_ line: String) -> String? {
        // Extract family ID from header line like "KORPI 6, pages 105-106"
        let pattern = #"^([A-ZÄÖÅ-]+(?:\s+(?:II|III|IV|V|VI))?\s+\d+[A-Z]?)"#
        
        if let range = line.range(of: pattern, options: .regularExpression) {
            return String(line[range])
        }
        return nil
    }
    
    private func validatePersonMatch(person: Person, inFamily family: Family) -> Bool {
        // SIMPLIFIED: Check name matches in all family members
        let allNames = family.allParents.map { $0.name.lowercased() } +
                       family.children.map { $0.name.lowercased() }
        
        if allNames.contains(person.name.lowercased()) {
            return true
        }
        
        // Check birth date matches
        if let personBirthDate = person.birthDate {
            let allBirthDates = family.allPersons.compactMap { $0.birthDate }
            if allBirthDates.contains(personBirthDate) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Debug Logging Methods
    
    /// Enhanced debug logging for cross-reference resolution
    private func debugLogResolutionAttempt(_ family: Family) {
        logInfo(.resolver, "🎯 === STARTING RESOLUTION DEBUG ===")
        logInfo(.resolver, "📋 Resolving for family: \(family.familyId)")
        
        // FIXED: Log what we're looking for
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
            logWarn(.resolver, "❌ FAILED: \(person) → \(reference) (\(type))")
        }
    }
    
    /// Final summary of resolution results
    private func debugLogResolutionSummary(_ network: FamilyNetwork) {
        logInfo(.resolver, "📊 === RESOLUTION SUMMARY ===")
        logInfo(.resolver, "Main family: \(network.mainFamily.familyId)")
        logInfo(.resolver, "As-child families: \(network.asChildFamilies.count)")
        logInfo(.resolver, "As-parent families: \(network.asParentFamilies.count)")
        logInfo(.resolver, "Spouse as-child families: \(network.spouseAsChildFamilies.count)")
        logInfo(.resolver, "Total resolved: \(network.totalResolvedFamilies)")
        logInfo(.resolver, "Success rate: \(String(format: "%.1f", resolutionStatistics.successRate * 100))%")
    }
    
    private func extractYearFromDate(_ date: String) -> Int? {
        let components = date.components(separatedBy: ".")
        if components.count >= 3, let year = Int(components[2]) {
            return year
        }
        return nil
    }
}
