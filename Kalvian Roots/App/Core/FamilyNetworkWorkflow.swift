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
     * Activate precomputed network and citations (e.g., when loading from cache)
     */
    func activateCachedResults(network: FamilyNetwork, citations: [String: String]) {
        logInfo(.citation, "📦 Activating cached results for: \(network.mainFamily.familyId)")
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
        case asParent
        case enhanced
    }
    
    /**
     * Generate and activate citations for the family
     */
    private func generateAndActivateCitations(for family: Family, type: CitationType) {
        logInfo(.citation, "📝 Generating citations for family: \(family.familyId) (type: \(type))")
        
        // Clear any existing citations
        activeCitations.removeAll()
        
        if let network = familyNetwork {
            // Generate person-specific citations with network enhancement
            generatePersonSpecificCitations(for: family, network: network)
        } else {
            // Generate basic citations without network
            generateBasicPersonCitations(for: family)
        }
        
        logInfo(.citation, "✅ Generated \(activeCitations.count) citations for \(family.familyId)")
    }
    
    private func generateBasicPersonCitations(for family: Family) {
        logInfo(.citation, "📝 Generating basic person citations (no network)")
        
        let basicCitation = CitationGenerator.generateMainFamilyCitation(family: family)
        
        // Give everyone the same basic family citation as fallback
        // Use displayName for storage key to avoid ambiguity
        for parent in family.allParents {
            activeCitations[parent.displayName] = basicCitation
            activeCitations[parent.name] = basicCitation  // Also store by name for compatibility
        }
        
        // Generate citations for all children across all couples
        for couple in family.couples {
            for child in couple.children {
                activeCitations[child.displayName] = basicCitation
                activeCitations[child.name] = basicCitation
            }
        }
        
        logInfo(.citation, "✅ Generated \(activeCitations.count) basic person citations")
    }
    
    private func generatePersonSpecificCitations(for family: Family, network: FamilyNetwork) {
        logInfo(.citation, "📋 Family: \(family.familyId)")
        logInfo(.citation, "👥 Couples: \(family.couples.count)")
        
        // Debug logging for couples and children
        for (coupleIndex, couple) in family.couples.enumerated() {
            logInfo(.citation, "--- Couple \(coupleIndex + 1) ---")
            logInfo(.citation, "👨 Husband: \(couple.husband.displayName)")
            logInfo(.citation, "👩 Wife: \(couple.wife.displayName)")
            logInfo(.citation, "👶 Children: \(couple.children.count)")
            
            for (childIndex, child) in couple.children.enumerated() {
                logInfo(.citation, "  [\(childIndex + 1)] \(child.displayName)")
                logInfo(.citation, "      Birth: \(child.birthDate ?? "none")")
                logInfo(.citation, "      Spouse: \(child.spouse ?? "none")")
                logInfo(.citation, "      AsParent: \(child.asParent ?? "none")")
                logInfo(.citation, "      IsMarried: \(child.isMarried)")
            }
        }
        
        logInfo(.citation, "📊 Married children count: \(family.marriedChildren.count)")
        for marriedChild in family.marriedChildren {
            logInfo(.citation, "  - \(marriedChild.displayName) -> spouse: \(marriedChild.spouse ?? "none"), asParent: \(marriedChild.asParent ?? "none")")
        }
        
        logInfo(.citation, "🔑 AsParent families in network: \(Array(network.asParentFamilies.keys))")
        logInfo(.citation, "👥 Generating person-specific citations")
        
        // SECTION 1: Generate enhanced asChild citations for parents
        for parent in family.allParents {
            logInfo(.citation, "🔍 Processing parent '\(parent.displayName)' with asChild='\(parent.asChild ?? "nil")'")
            
            if let asChildFamily = network.getAsChildFamily(for: parent) {
                logInfo(.citation, "✅ Found asChild family: \(asChildFamily.familyId)")
                
                // Create a modified network that includes parent's asParent family
                let modifiedNetwork = createNetworkWithParentAsParent(for: parent, network: network)
                
                // Generate enhanced citation with parent as target (for arrow)
                let citation = CitationGenerator.generateAsChildCitation(
                    for: parent,
                    in: asChildFamily,
                    network: modifiedNetwork,
                    nameEquivalenceManager: nil  // Add if you have name equivalence manager
                )
                
                // Store with displayName and name for compatibility
                activeCitations[parent.displayName] = citation
                activeCitations[parent.name] = citation
                
                logInfo(.citation, "✅ Stored enhanced asChild citation for '\(parent.displayName)'")
            } else {
                logWarn(.citation, "❌ NO asChild family found for '\(parent.displayName)'")
                
                // Fallback to main family citation
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                activeCitations[parent.displayName] = citation
                activeCitations[parent.name] = citation
            }
        }
        
        // SECTION 2: Generate enhanced citations for children
        for couple in family.couples {
            for child in couple.children {
                logInfo(.citation, "🔍 Processing child: \(child.displayName)")
                
                if let asParentFamily = network.getAsParentFamily(for: child) {
                    logInfo(.citation, "✅ Found asParent family: \(asParentFamily.familyId)")
                    
                    // FIX: Pass child as targetPerson so arrow appears for them
                    let citation = CitationGenerator.generateMainFamilyCitation(
                        family: asParentFamily,
                        targetPerson: child  // ← THIS IS THE KEY FIX FOR THE ARROW
                    )
                    
                    activeCitations[child.displayName] = citation
                    activeCitations[child.name] = citation
                    
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
                                
                                // Store under multiple keys for robust lookup
                                if let nuclearSpouseName = child.spouse {
                                    activeCitations[nuclearSpouseName] = citation
                                    logInfo(.citation, "✅ Stored spouse citation under UI key: '\(nuclearSpouseName)'")
                                }
                                activeCitations[spouse.displayName] = citation
                                activeCitations[spouse.name] = citation
                                
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
                                        
                                        if let nuclearSpouseName = child.spouse {
                                            activeCitations[nuclearSpouseName] = citation
                                        }
                                        activeCitations[spouse.displayName] = citation
                                        activeCitations[spouse.name] = citation
                                        
                                        break
                                    }
                                }
                            }
                        } else {
                            logInfo(.citation, "❌ NO spouse found in asParent family for child: \(child.name)")
                        }
                    }
                    
                } else {
                    logWarn(.citation, "⚠️ No asParent family found for child: \(child.name)")
                    
                    // Fallback: Use main family citation with child as target for arrow
                    let citation = CitationGenerator.generateMainFamilyCitation(
                        family: family,
                        targetPerson: child  // ← ALSO PASS TARGET HERE FOR ARROW
                    )
                    activeCitations[child.displayName] = citation
                    activeCitations[child.name] = citation
                }
            }
        }

        logInfo(.citation, "✅ Generated \(activeCitations.count) person-specific citations")
    }
    
    private func createNetworkWithParentAsParent(for parent: Person, network: FamilyNetwork) -> FamilyNetwork {
        logInfo(.citation, "🔧 Creating network with parent asParent for: '\(parent.displayName)' (name: '\(parent.name)')")
        
        var modifiedNetwork = network
        
        // Store under multiple keys for robust lookup
        let storageKeys = [
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
        let storageKeys = [
            spouse.displayName,  // "Antti Antinp."
            spouse.name,         // "Antti"
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

