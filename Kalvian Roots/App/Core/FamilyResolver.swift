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
    private let fileManager: RootsFileManager  // No module prefix - using local RootsFileManager class
    
    // MARK: - State Properties
    
    private var resolutionStatistics = ResolutionStatistics()
    
    // MARK: - Computed Properties
    
    var hasFileContent: Bool {
        fileManager.isFileLoaded
    }
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService,
         nameEquivalenceManager: NameEquivalenceManager,
         fileManager: RootsFileManager) {
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
        logDebug(.resolver, "Parents to resolve:")
        for parent in family.allParents {
            if let asChild = parent.asChild {
                logDebug(.resolver, "  - \(parent.displayName): as_child = \(asChild)")
            }
        }
        
        logDebug(.resolver, "Children to resolve:")
        for child in family.marriedChildren {
            if let asParent = child.asParent {
                logDebug(.resolver, "  - \(child.displayName): as_parent = \(asParent)")
            }
        }
        
        // Create initial network - FIX: Use correct parameter name 'mainFamily'
        var network = FamilyNetwork(mainFamily: family)
        resolutionStatistics = ResolutionStatistics()
        
        // Resolve as-child families (parents' birth families)
        network = try await resolveAsChildFamilies(for: family, network: network)
        
        // Resolve as-parent families (children's families)
        network = try await resolveAsParentFamilies(for: family, network: network)
        
        // Log summary
        let elapsed = DebugLogger.shared.endTimer("family_network_resolution")
        logInfo(.resolver, "✅ Cross-reference resolution complete in \(elapsed)")
        logInfo(.resolver, "📊 Statistics: \(resolutionStatistics.summary)")
        logInfo(.resolver, "📚 Network Summary:")
        logInfo(.resolver, "  - Nuclear family: \(family.familyId)")
        logInfo(.resolver, "  - As-child families: \(network.asChildFamilies.count)")
        logInfo(.resolver, "  - As-parent families: \(network.asParentFamilies.count)")
        logInfo(.resolver, "  - Spouse families: \(network.spouseAsChildFamilies.count)")
        
        return network
    }
    
    // MARK: - As-Child Family Resolution (Parents' Families)
    
    private func resolveAsChildFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        var updatedNetwork = network
        
        logInfo(.resolver, "👨‍👩 Resolving as-child families for parents")
        
        for parent in family.allParents {
            if let asChildRef = parent.asChild {
                logInfo(.resolver, "🔍 Attempting to resolve as_child: \(parent.displayName) from \(asChildRef)")
                
                if let resolvedFamily = try await findAsChildFamily(for: parent) {
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
                    let storageKey = child.name.trimmingCharacters(in: .whitespaces)
                    updatedNetwork.asParentFamilies[storageKey] = resolvedFamily
                    
                    logInfo(.resolver, "✅ Resolved: \(asParentRef)")
                    
                    // Immediately capture spouse information from this asParent family
                    await captureSpouseFromAsParentFamily(
                        childName: child.name,
                        asParentFamily: resolvedFamily,
                        network: &updatedNetwork
                    )
                }
            }
        }
        
        logInfo(.resolver, "✅ Resolved \(updatedNetwork.asParentFamilies.count) as-parent families")
        logInfo(.resolver, "✅ Resolved \(updatedNetwork.spouseAsChildFamilies.count) spouse families")
        return updatedNetwork
    }
    
    private func captureSpouseFromAsParentFamily(
        childName: String,
        asParentFamily: Family,
        network: inout FamilyNetwork
    ) async {
        // Find spouse in the asParent family using the Family extension
        guard let spouse = asParentFamily.findSpouse(for: childName) else { return }
        
        // Try to resolve spouse's asChild family
        // Method 1: asChild reference (preferred)
        if let asChildRef = spouse.asChild,
           let family = try? await resolveFamilyByReference(asChildRef) {
            network.spouseAsChildFamilies[spouse.name] = family
            logInfo(.resolver, "✅ Resolved spouse family via reference: \(spouse.displayName)")
            return
        }
        
        // Method 2: birth date search (fallback)
        if let family = try? await findFamilyByBirthDate(person: spouse) {
            network.spouseAsChildFamilies[spouse.name] = family
            logInfo(.resolver, "✅ Resolved spouse family via birth date: \(spouse.displayName)")
        }
    }
    
    // MARK: - Individual Family Finding Methods
    
    private func findAsChildFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-child family for: \(person.displayName)")
        
        // Method 1: Direct reference (preferred)
        if let asChildRef = person.asChild {
            logDebug(.resolver, "Trying direct reference: \(asChildRef)")
            if let family = try await resolveFamilyByReference(asChildRef) {
                return family
            }
        }
        
        // Method 2: Birth date search (fallback)
        logDebug(.resolver, "Trying birth date search")
        return try await findFamilyByBirthDate(person: person)
    }
    
    private func findAsParentFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-parent family for: \(person.displayName)")
        
        // Method 1: Direct reference (preferred)
        if let asParentRef = person.asParent {
            logDebug(.resolver, "Trying direct reference: \(asParentRef)")
            if let family = try await resolveFamilyByReference(asParentRef) {
                return family
            }
        }
        
        // Method 2: Spouse search if married
        if person.spouse != nil {
            logDebug(.resolver, "Trying spouse search")
            return try await findFamilyBySpouse(person: person)
        }
        
        logWarn(.resolver, "⚠️ No method available to find as-parent family")
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
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        
        guard let spouseName = person.spouse,
              let fileContent = fileManager.currentFileContent else {
            return nil
        }
        
        // Search for families where this person and their spouse appear as parents
        let searchPatterns = [
            "\(person.name).*\(spouseName)",
            "\(spouseName).*\(person.name)"
        ]
        
        for pattern in searchPatterns {
            if let familyText = findFamilyTextMatching(pattern: pattern, in: fileContent) {
                // Extract family ID from the found text
                if let familyId = extractFamilyId(from: familyText) {
                    return try await resolveFamilyByReference(familyId)
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Search Helpers
    
    private func searchForBirthDate(_ birthDate: String, in content: String) async -> [Family] {
        // Implementation would search through the file content for the birth date
        // and parse matching families
        logDebug(.resolver, "Searching for birth date: \(birthDate)")
        
        var families: [Family] = []
        
        // This is a simplified implementation
        // Real implementation would be more sophisticated
        
        return families
    }
    
    private func validatePersonMatch(person: Person, inFamily family: Family) -> Bool {
        // Check if this person could be a child in this family
        // Consider name equivalences, dates, etc.
        
        // FIX: Use the correct computed property from Family
        let allChildren = family.couples.flatMap { $0.children }
        
        for child in allChildren {
            if nameEquivalenceManager.areNamesEquivalent(person.name, child.name) {
                // Additional validation could check dates, locations, etc.
                return true
            }
        }
        
        return false
    }
    
    private func findFamilyTextMatching(pattern: String, in content: String) -> String? {
        // Implementation to find family text matching a pattern
        return nil
    }
    
    private func extractFamilyId(from familyText: String) -> String? {
        // Extract the family ID from the family text
        // Look for pattern like "FAMILYNAME number"
        return nil
    }
    
    // MARK: - Debug Helpers
    
    private func debugLogResolutionResult(for person: String, reference: String, success: Bool, type: String) {
        if success {
            logDebug(.resolver, "✅ \(type) resolution succeeded for \(person): \(reference)")
        } else {
            logDebug(.resolver, "❌ \(type) resolution failed for \(person): \(reference)")
        }
        
        resolutionStatistics.incrementAttempt()
        if success {
            resolutionStatistics.incrementSuccess()
        } else {
            resolutionStatistics.incrementFailure()
        }
    }
}

