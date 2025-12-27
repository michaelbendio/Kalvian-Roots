//
//  FamilyResolver.swift
//  Kalvian Roots
//
//  Builds family networks through cross-reference (asChild, asParent) resolution
//

import Foundation

/**
 * FamilyResolver handles cross-reference resolution for genealogical families
 *
 * This class resolves:
 * - as_child references (where parents appear as children in their birth families)
 * - as_parent references (where children appear as parents in their own families)
 * - spouse families (where spouses appear in their birth families)
 *
 * The resolution process uses multiple strategies:
 * 1. Direct family ID lookup
 * 2. Birth date matching
 * 3. Name equivalence checking
 * 4. Marriage date validation
 */
@MainActor
class FamilyResolver {
    
    // MARK: - Properties
    
    private let fileManager: RootsFileManager
    private let nameEquivalenceManager: NameEquivalenceManager
    private let aiParsingService: AIParsingService
    private weak var familyNetworkCache: FamilyNetworkCache?

    // Track resolution statistics
    private var resolutionStatistics = ResolutionStatistics()
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService,
         nameEquivalenceManager: NameEquivalenceManager,
         fileManager: RootsFileManager,
         familyNetworkCache: FamilyNetworkCache? = nil) {
        self.aiParsingService = aiParsingService
        self.nameEquivalenceManager = nameEquivalenceManager
        self.fileManager = fileManager
        self.familyNetworkCache = familyNetworkCache
        
        logInfo(.resolver, "🔗 FamilyResolver initialized \(familyNetworkCache != nil ? "WITH cache" : "without cache")")
    }
    // MARK: - Main Resolution Method
    
    /**
     * Resolve all cross-references for a nuclear family
     * Returns a FamilyNetwork containing the nuclear family and all resolved references
     */
    func resolveCrossReferences(for family: Family) async throws -> FamilyNetwork {
        logInfo(.resolver, "")
        logInfo(.resolver, String(repeating: "=", count: 70))
        logInfo(.resolver, "🎯 Starting cross-reference resolution for: \(family.familyId)")
        logInfo(.resolver, String(repeating: "=", count: 70))
        
        DebugLogger.shared.startTimer("family_network_resolution")
        
        // Log what we're looking for
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
        
        // Create initial network
        var network = FamilyNetwork(mainFamily: family)
        resolutionStatistics = ResolutionStatistics()
        
        logInfo(.resolver, "🔗 Storing nuclear family as asParent family for parents")
        logInfo(.resolver, "🔗 Storing nuclear family as asParent family for parents")
        for parent in family.allParents {
            // All parents are in couples by definition, so they all need asParent family stored
            network.asParentFamilies[parent.displayName] = family
            if parent.displayName != parent.name {
                network.asParentFamilies[FamilyNetwork.makePersonKey(for: parent)] = family
                network.asParentFamilies[parent.name] = family
            }
            logInfo(.resolver, "  ✅ Stored '\(family.familyId)' as asParent for parent '\(parent.displayName)'")
        }
        
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
                    // Store under displayName and simple name
                    updatedNetwork.asChildFamilies[parent.displayName] = resolvedFamily
                    if parent.displayName != parent.name {
                        updatedNetwork.asChildFamilies[parent.name] = resolvedFamily
                    }
                    
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: true, type: "as_child")
                    logInfo(.resolver, "  ✅ Resolved: \(asChildRef) - stored as '\(parent.displayName)'")
                } else {
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: false, type: "as_child")
                    logWarn(.resolver, "  ⚠️ Not found: \(asChildRef)")
                }
            }
        }
        
        logInfo(.resolver, "  Resolved \(Set(updatedNetwork.asChildFamilies.values).count) unique as-child families")
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
                    // Store under displayName and simple name
                    updatedNetwork.asParentFamilies[FamilyNetwork.makePersonKey(for: child)] = resolvedFamily
                    updatedNetwork.asParentFamilies[child.displayName] = resolvedFamily
                    if child.displayName != child.name {
                        updatedNetwork.asParentFamilies[child.name] = resolvedFamily
                    }
                    
                    logInfo(.resolver, "✅ Resolved: \(asParentRef) - stored as '\(child.displayName)'")
                    
                    // Immediately capture spouse information from this asParent family
                    await captureSpouseFromAsParentFamily(
                        childName: child.name,
                        childDisplayName: child.displayName,
                        asParentFamily: resolvedFamily,
                        childNuclearFamilyId: family.familyId,  // NEW: Pass the nuclear family ID
                        network: &updatedNetwork
                    )                }
            }
        }
        
        logInfo(.resolver, "✅ Resolved \(Set(updatedNetwork.asParentFamilies.values).count) unique as-parent families")
        logInfo(.resolver, "✅ Resolved \(Set(updatedNetwork.spouseAsChildFamilies.values).count) unique spouse families")
        return updatedNetwork
    }
    
    private func captureSpouseFromAsParentFamily(
        childName: String,
        childDisplayName: String,
        asParentFamily: Family,
        childNuclearFamilyId: String,  // NEW: Pass the child's nuclear family ID
        network: inout FamilyNetwork
    ) async {
        // Find spouse in the asParent family using the Family extension
        // Try both displayName and simple name to find the spouse
        var spouse: Person? = asParentFamily.findSpouseInFamily(for: childDisplayName)
        if spouse == nil {
            spouse = asParentFamily.findSpouseInFamily(for: childName)
        }
        
        guard let spouse = spouse else { return }
        
        // CRITICAL FIX: Also store the asParent family under the SPOUSE's name
        // This allows the spouse's citation to be enhanced with death/marriage dates
        // from the asParent family where they are a parent
        network.asParentFamilies[FamilyNetwork.makePersonKey(for: spouse)] = asParentFamily
        network.asParentFamilies[spouse.displayName] = asParentFamily
        if spouse.displayName != spouse.name {
            network.asParentFamilies[spouse.name] = asParentFamily
        }
        logInfo(.resolver, "✅ Stored asParent family '\(asParentFamily.familyId)' under spouse key '\(spouse.displayName)'")
        
        // Try to resolve spouse's asChild family
        // Method 1: asChild reference (preferred)
        if let asChildRef = spouse.asChild,
           let family = try? await resolveFamilyByReference(asChildRef) {
            
            // CRITICAL: Store under MULTIPLE keys to handle different name formats
            // The spouse might be referenced as "Kalle", "Kalle Kallenp.", or "Kalle Kleemola"
            
            // Key 1: displayName (e.g., "Kalle Kallenp.")
            network.spouseAsChildFamilies[spouse.displayName] = family
            
            // Key 2: simple name (e.g., "Kalle")
            if spouse.displayName != spouse.name {
                network.spouseAsChildFamilies[spouse.name] = family
            }
            
            // Key 3: firstname + CHILD'S NUCLEAR FAMILY surname (e.g., "Kalle Kleemola")
            // CRITICAL FIX: Use the child's nuclear family surname, NOT the asParent family surname
            // This is because the spouse is referenced in the nuclear family (e.g., "Kalle Kleemola" in Maria's family)
            let nuclearFamilySurname = extractSurname(from: childNuclearFamilyId)
            if let surname = nuclearFamilySurname {
                let firstName = extractFirstName(from: spouse.name)
                let fullNameWithSurname = "\(firstName) \(surname)"
                network.spouseAsChildFamilies[fullNameWithSurname] = family
                logInfo(.resolver, "✅ Also stored spouse asChild under: '\(fullNameWithSurname)' (using nuclear family surname)")
            }
            
            logInfo(.resolver, "✅ Resolved spouse family via reference: \(spouse.displayName) -> \(family.familyId)")
            return
        }
        
        // Method 2: birth date search (fallback)
        if let family = try? await findFamilyByBirthDate(person: spouse) {
            // Store under the same multiple keys
            network.spouseAsChildFamilies[spouse.displayName] = family
            if spouse.displayName != spouse.name {
                network.spouseAsChildFamilies[spouse.name] = family
            }
            
            // Also store with child's nuclear family surname
            let nuclearFamilySurname = extractSurname(from: childNuclearFamilyId)
            if let surname = nuclearFamilySurname {
                let firstName = extractFirstName(from: spouse.name)
                let fullNameWithSurname = "\(firstName) \(surname)"
                network.spouseAsChildFamilies[fullNameWithSurname] = family
                logInfo(.resolver, "✅ Also stored spouse asChild under: '\(fullNameWithSurname)' (using nuclear family surname)")
            }
            
            logInfo(.resolver, "✅ Resolved spouse family via birth date: \(spouse.displayName) -> \(family.familyId)")
        }
    }
    
    // MARK: - Helper Methods for Name Extraction

    /// Extract surname from family ID (e.g., "RITA 9" -> "Rita")
    private func extractSurname(from familyId: String) -> String? {
        let components = familyId.components(separatedBy: " ")
        guard let firstComponent = components.first else { return nil }
        
        // Capitalize first letter, lowercase rest
        return firstComponent.prefix(1).uppercased() + firstComponent.dropFirst().lowercased()
    }

    /// Extract first name from a person's name (handles patronymic)
    /// "Kalle Kallenp." -> "Kalle"
    /// "Maria Matint." -> "Maria"
    private func extractFirstName(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        return components.first ?? name
    }
    
    // MARK: - Family Finding Methods
    
    private func findAsChildFamily(for parent: Person) async throws -> Family? {
        guard let asChildRef = parent.asChild else { return nil }
        
        logDebug(.resolver, "Looking for as_child family: \(asChildRef)")
        
        // Step 1: Try direct family ID resolution
        if let family = try await resolveFamilyByReference(asChildRef) {
            // Validate this is the right family by checking if parent appears as child
            if validateParentInFamily(parent, family: family) {
                resolutionStatistics.resolvedByFamilyId += 1
                return family
            }
        }
        
        // Step 2: Try birth date search
        if let family = try await findFamilyByBirthDate(person: parent) {
            resolutionStatistics.resolvedByBirthDate += 1
            return family
        }
        
        resolutionStatistics.unresolved += 1
        return nil
    }
    
    private func findAsParentFamily(for child: Person) async throws -> Family? {
        guard let asParentRef = child.asParent else { return nil }
        
        logDebug(.resolver, "Looking for as_parent family: \(asParentRef)")
        
        // Step 1: Try direct family ID resolution
        if let family = try await resolveFamilyByReference(asParentRef) {
            // Validate this is the right family by checking if child appears as parent
            if validateChildAsParentInFamily(child, family: family) {
                resolutionStatistics.resolvedByFamilyId += 1
                return family
            }
        }
        
        // Step 2: Try birth date search
        if let family = try await findFamilyByBirthDateAsParent(person: child) {
            resolutionStatistics.resolvedByBirthDate += 1
            return family
        }
        
        resolutionStatistics.unresolved += 1
        return nil
    }
    
    // MARK: - Resolution Strategies
    
    private func resolveFamilyByReference(_ reference: String) async throws -> Family? {
        // Clean and validate the family ID - remove curly braces that AI includes
        var cleanedRef = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanedRef = cleanedRef.replacingOccurrences(of: "{", with: "")
        cleanedRef = cleanedRef.replacingOccurrences(of: "}", with: "")
        cleanedRef = cleanedRef.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // NEW: Check cache first to avoid redundant AI calls!
        if let cache = familyNetworkCache,
           let cachedFamily = cache.getCachedNuclearFamily(familyId: cleanedRef) {
            logInfo(.resolver, "⚡ Using cached family (avoiding AI call): \(cleanedRef)")
            return cachedFamily
        }
        
        // Cache miss - parse from file with AI
        logInfo(.resolver, "💨 Cache miss, parsing with AI: \(cleanedRef)")
        
        // Try to extract and parse the family
        if let familyText = fileManager.extractFamilyText(familyId: cleanedRef) {
            let family = try await aiParsingService.parseFamily(
                familyId: cleanedRef,
                familyText: familyText
            )
            logDebug(.resolver, "✅ Successfully parsed family: \(cleanedRef)")
            return family
        }
        
        logDebug(.resolver, "❌ Could not find/parse family: \(cleanedRef)")
        return nil
    }
    
    private func findFamilyByBirthDate(person: Person) async throws -> Family? {
        guard let birthDate = person.birthDate else { return nil }
        
        logDebug(.resolver, "🔍 Searching for person by birth date: \(birthDate)")
        
        // Placeholder - actual implementation would search through all families
        return nil
    }
    
    private func findFamilyByBirthDateAsParent(person: Person) async throws -> Family? {
        guard let birthDate = person.birthDate else { return nil }
        
        logDebug(.resolver, "🔍 Searching for person as parent by birth date: \(birthDate)")
        
        // Placeholder - actual implementation would search through all families
        return nil
    }
    
    // MARK: - Validation Methods
    
    private func validateParentInFamily(_ parent: Person, family: Family) -> Bool {
        // Check if parent appears as a child in this family
        for couple in family.couples {
            for child in couple.children {
                if arePersonsEqual(parent, child) {
                    logDebug(.resolver, "✅ Found parent as child in family: \(family.familyId)")
                    return true
                }
            }
        }
        
        logDebug(.resolver, "❌ Parent not found as child in family: \(family.familyId)")
        return false
    }
    
    private func validateChildAsParentInFamily(_ child: Person, family: Family) -> Bool {
        // Check if child appears as a parent in this family
        for couple in family.couples {
            if arePersonsEqual(child, couple.husband) || arePersonsEqual(child, couple.wife) {
                logDebug(.resolver, "✅ Found child as parent in family: \(family.familyId)")
                return true
            }
        }
        
        logDebug(.resolver, "❌ Child not found as parent in family: \(family.familyId)")
        return false
    }
    
    private func arePersonsEqual(_ person1: Person, _ person2: Person) -> Bool {
        // First check birth date if available (most reliable)
        if let birth1 = person1.birthDate, let birth2 = person2.birthDate {
            if birth1 == birth2 {
                return true
            }
        }
        
        // Check name equivalence
        if nameEquivalenceManager.areNamesEquivalent(person1.name, person2.name) {
            return true
        }
        
        // Check exact name match
        if person1.name.lowercased() == person2.name.lowercased() {
            return true
        }
        
        return false
    }
    
    // MARK: - Debug Logging
    
    private func debugLogResolutionResult(for person: String, reference: String, success: Bool, type: String) {
        if success {
            logDebug(.resolver, "✅ \(type) resolution SUCCESS: \(person) -> \(reference)")
        } else {
            logDebug(.resolver, "❌ \(type) resolution FAILED: \(person) -> \(reference)")
        }
    }
}

// MARK: - Resolution Statistics

private struct ResolutionStatistics {
    var resolvedByFamilyId = 0
    var resolvedByBirthDate = 0
    var unresolved = 0
    
    var total: Int {
        resolvedByFamilyId + resolvedByBirthDate + unresolved
    }
    
    var summary: String {
        "Total: \(total), By ID: \(resolvedByFamilyId), By Birth: \(resolvedByBirthDate), Unresolved: \(unresolved)"
    }
}

// MARK: - Family Extensions for Finding People

extension Family {
    /**
     * Find the spouse of a person in this family (FamilyResolver-specific version)
     */
    func findSpouseInFamily(for personName: String) -> Person? {
        for couple in couples {
            if areNamesEqual(couple.husband.name, personName) ||
               areNamesEqual(couple.husband.displayName, personName) {
                return couple.wife
            }
            if areNamesEqual(couple.wife.name, personName) ||
               areNamesEqual(couple.wife.displayName, personName) {
                return couple.husband
            }
        }
        return nil
    }
    
    private func areNamesEqual(_ name1: String, _ name2: String) -> Bool {
        return name1.lowercased().trimmingCharacters(in: .whitespaces) ==
               name2.lowercased().trimmingCharacters(in: .whitespaces)
    }
}
