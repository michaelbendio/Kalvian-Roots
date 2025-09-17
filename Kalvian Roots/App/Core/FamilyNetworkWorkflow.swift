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
        
        // Generate enhanced asChild citations for parents
        for parent in family.allParents {
            logInfo(.citation, "🔍 DEBUG: Processing parent '\(parent.displayName)' with asChild='\(parent.asChild ?? "nil")'")
            
            if let asChildFamily = network.getAsChildFamily(for: parent) {
                logInfo(.citation, "✅ Found asChild family: \(asChildFamily.familyId)")
                
                // Create a modified network that includes parent's asParent family
                let modifiedNetwork = createNetworkWithParentAsParent(for: parent, network: network)
                
                // Use enhanced citation that includes asParent information from nuclear family
                let citation = CitationGenerator.generateAsChildCitation(
                    for: parent,
                    in: asChildFamily,
                    network: modifiedNetwork
                )
                
                // Store with displayName (includes patronymic) to avoid ambiguity
                activeCitations[parent.displayName] = citation
                // Also store with just name for backward compatibility
                activeCitations[parent.name] = citation
                
                logInfo(.citation, "🔍 STORED enhanced asChild citation for '\(parent.displayName)'")
                logInfo(.citation, "📝 Added additional information from nuclear family where '\(parent.displayName)' is a parent")
            } else {
                logWarn(.citation, "❌ NO asChild family found for '\(parent.displayName)'")
                logInfo(.citation, "🔍 Available asChild families: \(Array(network.asChildFamilies.keys))")
                
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                activeCitations[parent.displayName] = citation
                activeCitations[parent.name] = citation
            }
        }
        
        // Generate enhanced citations for children across all couples
        for couple in family.couples {
            for child in couple.children {
                logInfo(.citation, "🔍 Processing child: \(child.displayName)")
                
                if let asParentFamily = network.getAsParentFamily(for: child) {
                    logInfo(.citation, "✅ Found asParent family: \(asParentFamily.familyId)")
                    
                    if let spouse = asParentFamily.findSpouse(for: child.name) {
                        logInfo(.citation, "✅ Found spouse: \(spouse.displayName) (name: \(spouse.name))")
                        
                        // DEBUG: Check what spouse families are available
                        logInfo(.citation, "🔍 Available spouseAsChildFamilies keys: \(Array(network.spouseAsChildFamilies.keys))")
                        
                        if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spouse.name) {
                            logInfo(.citation, "✅ Found spouse asChild family: \(spouseAsChildFamily.familyId)")
                            
                            // ENHANCEMENT FIX: Create a modified network that includes spouse's asParent family
                            let enhancedNetwork = createNetworkWithSpouseAsParent(
                                for: spouse,
                                asParentFamily: asParentFamily,
                                network: network
                            )
                            
                            // ENHANCED FIX: Use the full spouse data and enhanced network WITH NAME EQUIVALENCE
                            let citation = CitationGenerator.generateAsChildCitation(
                                for: spouse,  // Use the full spouse Person, not just the name
                                in: spouseAsChildFamily,
                                network: enhancedNetwork,  // Pass the enhanced network with spouse's asParent data
                                nameEquivalenceManager: NameEquivalenceManager()  // ADD NAME EQUIVALENCE SUPPORT
                            )
                            
                            // CRITICAL FIX: Store citation under the key the UI will use
                            if let nuclearSpouseName = child.spouse {
                                activeCitations[nuclearSpouseName] = citation
                                logInfo(.citation, "🔑 CRITICAL: Stored spouse citation under UI key: '\(nuclearSpouseName)'")
                            }
                            
                            // Also store under asParent family names for backup
                            activeCitations[spouse.displayName] = citation
                            activeCitations[spouse.name] = citation
                            
                            logInfo(.citation, "✅ Generated ENHANCED spouse citation: \(spouse.displayName)")
                        } else {
                            logInfo(.citation, "❌ NO spouse asChild family found for: \(spouse.name)")
                            logInfo(.citation, "🔍 Tried key: '\(spouse.name)'")
                            logInfo(.citation, "🔍 Available spouse family keys: \(Array(network.spouseAsChildFamilies.keys))")
                            
                            // Try alternative keys
                            let alternativeKeys = [
                                spouse.displayName,
                                spouse.name.trimmingCharacters(in: .whitespaces)
                            ]
                            
                            for altKey in alternativeKeys {
                                if let altFamily = network.getSpouseAsChildFamily(for: altKey) {
                                    logInfo(.citation, "✅ Found spouse family with alternative key: '\(altKey)' -> \(altFamily.familyId)")
                                    
                                    // ENHANCEMENT FIX: Create enhanced network
                                    let enhancedNetwork = createNetworkWithSpouseAsParent(
                                        for: spouse,
                                        asParentFamily: asParentFamily,
                                        network: network
                                    )
                                    
                                    // ENHANCED FIX: Use full spouse data and enhanced network WITH NAME EQUIVALENCE
                                    let citation = CitationGenerator.generateAsChildCitation(
                                        for: spouse,  // Use the full spouse Person
                                        in: altFamily,
                                        network: enhancedNetwork,  // Pass the enhanced network
                                        nameEquivalenceManager: NameEquivalenceManager()  // ADD NAME EQUIVALENCE SUPPORT
                                    )
                                    
                                    // CRITICAL FIX: Store under UI key
                                    if let nuclearSpouseName = child.spouse {
                                        activeCitations[nuclearSpouseName] = citation
                                        logInfo(.citation, "🔑 CRITICAL: Stored spouse citation under UI key: '\(nuclearSpouseName)'")
                                    }
                                    
                                    // Also store under asParent family names for backup
                                    activeCitations[spouse.displayName] = citation
                                    activeCitations[spouse.name] = citation
                                    
                                    logInfo(.citation, "✅ Generated ENHANCED spouse citation: \(spouse.displayName)")
                                    break
                                } else {
                                    logInfo(.citation, "❌ Alternative key '\(altKey)' also not found")
                                }
                            }
                        }
                    } else {
                        logInfo(.citation, "❌ NO spouse found in asParent family for child: \(child.name)")
                    }
                } else {
                    logInfo(.citation, "⚠️ No asParent family found for child: \(child.name)")
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
