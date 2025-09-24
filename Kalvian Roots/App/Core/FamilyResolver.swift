//
//  FamilyResolver.swift
//  Kalvian Roots
//
//  Family cross-reference resolution for genealogical connections
//  FIXED: Enhanced storage keys to prevent name collisions
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
    
    // Track resolution statistics
    private var resolutionStatistics = ResolutionStatistics()
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService,
         nameEquivalenceManager: NameEquivalenceManager,
         fileManager: RootsFileManager) {
        self.aiParsingService = aiParsingService
        self.nameEquivalenceManager = nameEquivalenceManager
        self.fileManager = fileManager
        
        logInfo(.resolver, "🔗 FamilyResolver initialized")
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
                    // Generate unique storage keys for this parent
                    let storageKeys = generateStorageKeys(for: parent, familyId: family.familyId)
                    
                    for key in storageKeys {
                        updatedNetwork.asChildFamilies[key] = resolvedFamily
                        logDebug(.citation, "  📝 Stored asChild family under key: '\(key)'")
                    }
                    
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: true, type: "as_child")
                    logInfo(.resolver, "  ✅ Resolved: \(asChildRef) - stored with keys: \(storageKeys)")
                } else {
                    debugLogResolutionResult(for: parent.displayName, reference: asChildRef, success: false, type: "as_child")
                    logWarn(.resolver, "  ⚠️ Not found: \(asChildRef)")
                }
            }
        }
        
        logInfo(.resolver, "  Resolved \(Set(updatedNetwork.asChildFamilies.values).count) unique as-child families")
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
                    // Generate unique storage keys for this child
                    let storageKeys = generateStorageKeys(for: child, familyId: family.familyId)
                    
                    for key in storageKeys {
                        updatedNetwork.asParentFamilies[key] = resolvedFamily
                        logDebug(.citation, "  📝 Stored asParent family under key: '\(key)'")
                    }
                    
                    logInfo(.resolver, "✅ Resolved: \(asParentRef) - stored with keys: \(storageKeys)")
                    
                    // Immediately capture spouse information from this asParent family
                    await captureSpouseFromAsParentFamily(
                        childName: child.name,
                        childDisplayName: child.displayName,
                        asParentFamily: resolvedFamily,
                        network: &updatedNetwork,
                        nuclearFamilyId: family.familyId
                    )
                }
            }
        }
        
        logInfo(.resolver, "✅ Resolved \(Set(updatedNetwork.asParentFamilies.values).count) unique as-parent families")
        logInfo(.resolver, "✅ Resolved \(Set(updatedNetwork.spouseAsChildFamilies.values).count) unique spouse families")
        return updatedNetwork
    }
    
    /**
     * Generate multiple storage keys for robust lookup with disambiguation
     * FIXED: Uses birth dates and family IDs to prevent name collisions
     */
    private func generateStorageKeys(for person: Person, familyId: String) -> [String] {
        var keys: [String] = []
        
        // 1. Most specific: Name with birth year (if available)
        if let birthDate = person.birthDate {
            let birthYear = extractBirthYear(from: birthDate)
            if birthYear != "unknown" {
                let keyWithYear = "\(person.displayName):\(birthYear)"
                keys.append(keyWithYear)
                logDebug(.resolver, "📌 Generated birth-year key: '\(keyWithYear)'")
            }
        }
        
        // 2. Family-specific key (helps when same name appears in multiple families)
        let familyKey = "\(person.displayName)@\(familyId)"
        keys.append(familyKey)
        logDebug(.resolver, "📌 Generated family key: '\(familyKey)'")
        
        // 3. Standard displayName (backwards compatibility)
        keys.append(person.displayName)
        
        // 4. Simple name (last resort, only if name is substantial)
        if person.name.count > 3 && person.name != person.displayName {
            keys.append(person.name)
            keys.append(person.name.trimmingCharacters(in: .whitespaces))
        }
        
        // Remove duplicates while preserving order
        let uniqueKeys = Array(NSOrderedSet(array: keys)) as! [String]
        
        logDebug(.resolver, "🔑 Generated \(uniqueKeys.count) storage keys for '\(person.displayName)': \(uniqueKeys)")
        return uniqueKeys
    }
    
    /**
     * Extract birth year from various date formats
     */
    private func extractBirthYear(from dateString: String) -> String {
        // Handle DD.MM.YYYY format
        if dateString.contains(".") {
            let components = dateString.components(separatedBy: ".")
            if components.count >= 3 {
                return components[2].trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Handle plain year format
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 4, Int(trimmed) != nil {
            return trimmed
        }
        
        return "unknown"
    }
    
    private func captureSpouseFromAsParentFamily(
        childName: String,
        childDisplayName: String,
        asParentFamily: Family,
        network: inout FamilyNetwork,
        nuclearFamilyId: String
    ) async {
        // Find spouse in the asParent family using the Family extension
        // Try both displayName and simple name to find the spouse
        var spouse: Person? = asParentFamily.findSpouseInFamily(for: childDisplayName)
        if spouse == nil {
            spouse = asParentFamily.findSpouseInFamily(for: childName)
        }
        
        guard let spouse = spouse else { return }
        
        // Try to resolve spouse's asChild family
        // Method 1: asChild reference (preferred)
        if let asChildRef = spouse.asChild,
           let family = try? await resolveFamilyByReference(asChildRef) {
            // Generate unique storage keys for spouse
            let storageKeys = generateStorageKeys(for: spouse, familyId: nuclearFamilyId)
            
            for key in storageKeys {
                network.spouseAsChildFamilies[key] = family
                logDebug(.resolver, "  📝 Stored spouse family under key: '\(key)'")
            }
            
            logInfo(.resolver, "✅ Resolved spouse family via reference: \(spouse.displayName)")
            return
        }
        
        // Method 2: birth date search (fallback)
        if let family = try? await findFamilyByBirthDate(person: spouse) {
            // Generate unique storage keys for spouse
            let storageKeys = generateStorageKeys(for: spouse, familyId: nuclearFamilyId)
            
            for key in storageKeys {
                network.spouseAsChildFamilies[key] = family
                logDebug(.resolver, "  📝 Stored spouse family under key: '\(key)'")
            }
            
            logInfo(.resolver, "✅ Resolved spouse family via birth date: \(spouse.displayName)")
        }
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
        // Clean and validate the family ID
        let cleanedRef = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        
        // This would require searching through all families in the file
        // For now, this is a placeholder - actual implementation would
        // need to scan the file or maintain an index
        
        return nil
    }
    
    private func findFamilyByBirthDateAsParent(person: Person) async throws -> Family? {
        guard let birthDate = person.birthDate else { return nil }
        
        logDebug(.resolver, "🔍 Searching for person as parent by birth date: \(birthDate)")
        
        // This would require searching through all families in the file
        // For now, this is a placeholder
        
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
     * Note: There's also a findSpouse method in Family.swift
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
