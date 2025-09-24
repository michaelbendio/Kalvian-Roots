//
//  FamilyNetworkWorkflow.swift
//  Kalvian Roots
//
//  Workflow for building family networks and generating enhanced citations
//

import Foundation

/**
 * Complete workflow for processing a nuclear family
 *
 * This workflow handles:
 * 1. Optional cross-reference resolution (as_child, as_parent, spouse families)
 * 2. Citation generation for all family members
 * 3. Enhanced citations that include cross-referenced data
 */
class FamilyNetworkWorkflow {
    
    // MARK: - Properties
    
    private let nuclearFamily: Family
    private let familyResolver: FamilyResolver
    private let shouldResolveCrossReferences: Bool
    
    private var familyNetwork: FamilyNetwork?
    private var activeCitations: [String: String] = [:]
    
    // Track names to detect duplicates for disambiguation
    private var nameTracker: Set<String> = []
    
    // MARK: - Initialization
    
    init(nuclearFamily: Family,
         familyResolver: FamilyResolver,
         resolveCrossReferences: Bool = true) {
        self.nuclearFamily = nuclearFamily
        self.familyResolver = familyResolver
        self.shouldResolveCrossReferences = resolveCrossReferences
        
        logInfo(.resolver, "📋 FamilyNetworkWorkflow initialized for: \(nuclearFamily.familyId)")
        logInfo(.resolver, "  Cross-reference resolution: \(resolveCrossReferences ? "ENABLED" : "DISABLED")")
    }
    
    // MARK: - Public Methods
    
    /**
     * Process the workflow
     */
    func process() async throws {
        logInfo(.resolver, "🎯 Starting workflow processing for: \(nuclearFamily.familyId)")
        
        if shouldResolveCrossReferences {
            // Build the complete family network
            familyNetwork = try await buildFamilyNetwork(for: nuclearFamily)
            
            // Generate enhanced citations using the network
            generateAndActivateCitations(for: nuclearFamily, type: .nuclear)
        } else {
            // Generate basic citations without network
            generateAndActivateCitations(for: nuclearFamily, type: .nuclear)
        }
        
        logInfo(.resolver, "✅ Workflow processing complete for: \(nuclearFamily.familyId)")
        logInfo(.citation, "📚 Generated \(activeCitations.count) citations")
    }
    
    /**
     * Get the family network (if resolved)
     */
    func getFamilyNetwork() -> FamilyNetwork? {
        return familyNetwork
    }
    
    /**
     * Get the active citations
     */
    func getActiveCitations() -> [String: String] {
        return activeCitations
    }
    
    /**
     * Activate cached results (used when loading from cache)
     */
    func activateCachedResults(network: FamilyNetwork, citations: [String: String]) {
        self.familyNetwork = network
        self.activeCitations = citations
        logInfo(.citation, "✅ Activated cached network and \(citations.count) citations")
    }
    
    // MARK: - Private Methods
    
    private func buildFamilyNetwork(for nuclearFamily: Family) async throws -> FamilyNetwork {
        logInfo(.resolver, "🕸️ Building family network for: \(nuclearFamily.familyId)")
        
        // Use correct method name from FamilyResolver
        let network = try await familyResolver.resolveCrossReferences(for: nuclearFamily)
        
        return network
    }
    
    private enum CitationType {
        case nuclear
        case asChild
    }
    
    /**
     * Main citation generation workflow
     */
    private func generateAndActivateCitations(for family: Family, type: CitationType) {
        guard let network = familyNetwork else {
            logWarn(.citation, "⚠️ No network available for enhanced citations")
            return
        }
        
        logInfo(.citation, "***************************************************************")
        logInfo(.citation, "🔍 DEBUG: FAMILY CONTENT ANALYSIS")
        logInfo(.citation, "***************************************************************")
        logInfo(.citation, "📋 Family: \(family.familyId)")
        logInfo(.citation, "👥 Couples: \(family.couples.count)")
        
        for (index, couple) in family.couples.enumerated() {
            logInfo(.citation, "--- Couple \(index + 1) ---")
            logInfo(.citation, "👨 Husband: \(couple.husband.displayName)")
            logInfo(.citation, "👩 Wife: \(couple.wife.displayName)")
            logInfo(.citation, "💑 Marriage: \(couple.marriageDate ?? "none")")
            logInfo(.citation, "👶 Children: \(couple.children.count)")
            
            for child in couple.children {
                logInfo(.citation, "    - \(child.displayName): birthDate: \(child.birthDate ?? "none")")
                logInfo(.citation, "      Spouse: \(child.spouse ?? "none")")
                logInfo(.citation, "      AsParent: \(child.asParent ?? "none")")
                logInfo(.citation, "      IsMarried: \(child.isMarried)")
            }
        }
        
        logInfo(.citation, "📊 Married children count: \(family.marriedChildren.count)")
        for marriedChild in family.marriedChildren {
            logInfo(.citation, "  - \(marriedChild.displayName) -> spouse: \(marriedChild.spouse ?? "none"), asParent: \(marriedChild.asParent ?? "none")")
        }
        
        // Detect duplicate names before generating citations
        detectDuplicateNames(in: family, network: network)
        
        logInfo(.citation, "🔑 AsParent families in network: \(Array(network.asParentFamilies.keys))")
        logInfo(.citation, "👥 Generating person-specific citations")
        
        // Generate citations for all family members
        generatePersonSpecificCitations(for: family, network: network)
    }
    
    /**
     * Detect duplicate names in the family for disambiguation
     */
    private func detectDuplicateNames(in family: Family, network: FamilyNetwork) {
        nameTracker.removeAll()
        
        // Collect all names
        var allNames: [String] = []
        
        // Add parents
        for parent in family.allParents {
            allNames.append(parent.displayName)
        }
        
        // Add children
        for couple in family.couples {
            for child in couple.children {
                allNames.append(child.displayName)
            }
        }
        
        // Find duplicates
        var seen: Set<String> = []
        for name in allNames {
            if seen.contains(name) {
                nameTracker.insert(name)  // This name has duplicates
            }
            seen.insert(name)
        }
        
        if !nameTracker.isEmpty {
            logInfo(.citation, "⚠️ Found duplicate names requiring disambiguation: \(nameTracker)")
        }
    }
    
    /**
     * Generate a unique citation key for a person
     * Uses displayName as primary, with birth date fallback for duplicates
     */
    private func generateCitationKey(for person: Person) -> String {
        let primaryKey = person.displayName
        
        // Check if this displayName needs disambiguation
        if nameTracker.contains(primaryKey) {
            // Create composite key with birth year
            let birthYear = extractBirthYear(from: person.birthDate)
            let uniqueKey = "\(primaryKey):\(birthYear)"
            logDebug(.citation, "📝 Using disambiguated key: '\(uniqueKey)' for duplicate name '\(primaryKey)'")
            return uniqueKey
        }
        
        return primaryKey
    }
    
    /**
     * Extract birth year from various date formats
     */
    private func extractBirthYear(from dateString: String?) -> String {
        guard let dateString = dateString else { return "unknown" }
        
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
    
    /**
     * Store citation with all necessary keys for robust retrieval
     */
    private func storeCitation(_ citation: String, for person: Person) {
        // Primary key using our unique key generation
        let primaryKey = generateCitationKey(for: person)
        activeCitations[primaryKey] = citation
        
        // Also store under displayName for normal cases
        activeCitations[person.displayName] = citation
        
        // Backwards compatibility - store under simple name
        activeCitations[person.name] = citation
        
        logDebug(.citation, "✅ Stored citation under keys: '\(primaryKey)', '\(person.displayName)', '\(person.name)'")
    }
    
    /**
     * Generate person-specific citations for all family members
     */
    private func generatePersonSpecificCitations(for family: Family, network: FamilyNetwork) {
        // SECTION 1: Generate enhanced asChild citations for parents
        for parent in family.allParents {
            logInfo(.citation, "🔍 Processing parent '\(parent.displayName)' with asChild='\(parent.asChild ?? "none")'")
            
            if let asChildFamily = network.getAsChildFamily(for: parent) {
                logInfo(.citation, "✅ Found asChild family: \(asChildFamily.familyId)")
                
                // Create a modified network that includes parent's asParent info
                let modifiedNetwork = createNetworkWithParentAsParent(for: parent, network: network)
                
                // Generate enhanced citation with arrow support for parent
                let citation = CitationGenerator.generateAsChildCitation(
                    for: parent,
                    in: asChildFamily,
                    network: modifiedNetwork,
                    nameEquivalenceManager: NameEquivalenceManager()
                )
                storeCitation(citation, for: parent)
                
            } else {
                logWarn(.citation, "⚠️ No asChild family found for parent: \(parent.displayName)")
                // Fallback: Use regular family citation for parents without asChild families
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                storeCitation(citation, for: parent)
            }
        }
        
        // SECTION 2: Generate enhanced citations for children
        for couple in family.couples {
            for child in couple.children {
                logInfo(.citation, "🔍 Processing child '\(child.displayName)' with asParent='\(child.asParent ?? "none")'")
                
                // FIXED: Only process children with explicit asParent references
                if child.asParent != nil, let asParentFamily = network.getAsParentFamily(for: child) {
                    logInfo(.citation, "✅ Found asParent family: \(asParentFamily.familyId)")
                    
                    // Generate enhanced citation with arrow support
                    // Use generateMainFamilyCitation with targetPerson for enhancement
                    let citation = CitationGenerator.generateMainFamilyCitation(
                        family: family,
                        targetPerson: child,
                        network: network
                    )
                    
                    storeCitation(citation, for: child)
                    
                    logInfo(.citation, "✅ Generated asParent citation for child: \(child.displayName)")
                    
                    // SECTION 3: Generate spouse citations if child has a spouse
                    if child.spouse != nil {
                        logInfo(.citation, "👰 Processing spouse for child: \(child.name)")
                        
                        if let spouse = asParentFamily.findSpouse(for: child.name) {
                            logInfo(.citation, "✅ Found spouse: \(spouse.displayName)")
                            
                            if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spouse.name) {
                                logInfo(.citation, "✅ Found spouse asChild family: \(spouseAsChildFamily.familyId)")
                                
                                // Create enhanced network for spouse
                                let enhancedNetwork = createNetworkWithSpouseAsParent(
                                    for: spouse,
                                    asParentFamily: asParentFamily,
                                    network: network
                                )
                                
                                // Generate enhanced spouse citation with arrow support
                                let citation = CitationGenerator.generateAsChildCitation(
                                    for: spouse,
                                    in: spouseAsChildFamily,
                                    network: enhancedNetwork,
                                    nameEquivalenceManager: NameEquivalenceManager()
                                )
                                
                                // Store spouse citation
                                storeCitation(citation, for: spouse)
                                
                                // Also store under the spouse name from nuclear family if available
                                if let nuclearSpouseName = child.spouse {
                                    activeCitations[nuclearSpouseName] = citation
                                    logInfo(.citation, "✅ Also stored spouse citation under nuclear family key: '\(nuclearSpouseName)'")
                                }
                                
                            } else {
                                logInfo(.citation, "❌ NO spouse asChild family found for: \(spouse.name)")
                                
                                // Try alternative keys for spouse family
                                let alternativeKeys = [
                                    spouse.displayName,
                                    spouse.name.trimmingCharacters(in: .whitespaces)
                                ]
                                
                                for altKey in alternativeKeys {
                                    if let altFamily = network.getSpouseAsChildFamily(for: altKey) {
                                        logInfo(.citation, "✅ Found spouse family with alternative key: '\(altKey)'")
                                        
                                        let enhancedNetwork = createNetworkWithSpouseAsParent(
                                            for: spouse,
                                            asParentFamily: asParentFamily,
                                            network: network
                                        )
                                        
                                        let citation = CitationGenerator.generateAsChildCitation(
                                            for: spouse,
                                            in: altFamily,
                                            network: enhancedNetwork,
                                            nameEquivalenceManager: NameEquivalenceManager()
                                        )
                                        
                                        storeCitation(citation, for: spouse)
                                        
                                        if let nuclearSpouseName = child.spouse {
                                            activeCitations[nuclearSpouseName] = citation
                                        }
                                        
                                        break
                                    }
                                }
                            }
                        } else {
                            logInfo(.citation, "❌ NO spouse found in asParent family for child: \(child.name)")
                        }
                    }
                    
                } else {
                    logWarn(.citation, "⚠️ No asParent family found or no asParent reference for child: \(child.name)")
                    
                    // Fallback: Use main family citation with child as target for arrow
                    let citation = CitationGenerator.generateMainFamilyCitation(
                        family: family,
                        targetPerson: child,  // Pass target for arrow
                        network: network
                    )
                    storeCitation(citation, for: child)
                }
            }
        }

        logInfo(.citation, "✅ Generated \(activeCitations.count) person-specific citations")
    }
    
    private func createNetworkWithParentAsParent(for parent: Person, network: FamilyNetwork) -> FamilyNetwork {
        logInfo(.citation, "🔧 Creating network with parent asParent for: '\(parent.displayName)' (name: '\(parent.name)')")
        
        var modifiedNetwork = network
        
        // Store under multiple keys for robust lookup
        // Use the same unique key generation for consistency
        let uniqueKey = generateCitationKey(for: parent)
        let storageKeys = [
            uniqueKey,                    // Unique key with disambiguation if needed
            parent.displayName,           // "Erik Matinp."
            parent.name,                  // "Erik"
            parent.name.trimmingCharacters(in: .whitespaces)  // "Erik" (trimmed)
        ]
        
        for key in storageKeys {
            modifiedNetwork.asParentFamilies[key] = network.mainFamily
            logDebug(.citation, "  📝 Stored nuclear family under key: '\(key)'")
        }
        
        logInfo(.citation, "  📊 Total asParent families in modified network: \(modifiedNetwork.asParentFamilies.count)")
        logInfo(.citation, "  🔑 asParent keys: \(Array(modifiedNetwork.asParentFamilies.keys))")
        
        return modifiedNetwork
    }
    
    // NEW HELPER METHOD: Creates enhanced network with spouse's asParent family for enhancement
    private func createNetworkWithSpouseAsParent(
        for spouse: Person,
        asParentFamily: Family,
        network: FamilyNetwork
    ) -> FamilyNetwork {
        logInfo(.citation, "🔧 Creating enhanced network with spouse asParent for: '\(spouse.displayName)'")
        
        var enhancedNetwork = network
        
        // Store the asParent family under the spouse's name so the enhancement logic can find it
        // Use the same unique key generation for consistency
        let uniqueKey = generateCitationKey(for: spouse)
        let storageKeys = [
            uniqueKey,                   // Unique key with disambiguation if needed
            spouse.displayName,          // "Antti Antinp."
            spouse.name,                 // "Antti"
            spouse.name.trimmingCharacters(in: .whitespaces)  // "Antti" (trimmed)
        ]
        
        for key in storageKeys {
            enhancedNetwork.asParentFamilies[key] = asParentFamily
            logDebug(.citation, "  📝 Stored spouse asParent family under key: '\(key)'")
        }
        
        logInfo(.citation, "  📊 Enhanced network now has \(enhancedNetwork.asParentFamilies.count) asParent families")
        logInfo(.citation, "  🔑 Enhanced asParent keys: \(Array(enhancedNetwork.asParentFamilies.keys))")
        
        return enhancedNetwork
    }
}
