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
    
    private func generateAndActivateCitations(for family: Family, type: CitationType) {
        logInfo(.citation, "📄 Generating \(type) citations for: \(family.familyId)")
        
        switch type {
        case .nuclear:
            // Generate enhanced nuclear citation for family-level citation
            if let network = familyNetwork {
                // Family-level citation (for clicking on family ID)
                let enhancedFamily = enhanceChildrenWithAsParentDates(family: family, network: network)
                let enhancedCitation = CitationGenerator.generateNuclearFamilyCitationWithSupplement(
                    family: enhancedFamily,
                    network: network
                )
                activeCitations[family.familyId] = enhancedCitation
                
                generatePersonSpecificCitations(for: family, network: network)
            } else {
                // Fallback: standard citation for family
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                activeCitations[family.familyId] = citation
                
                // Give everyone the same fallback citation
                generateBasicPersonCitations(for: family)
            }
            
        case .asChild, .asParent, .enhanced:
            let citation = CitationGenerator.generateMainFamilyCitation(family: family)
            activeCitations[family.familyId] = citation
        }
        
        logInfo(.citation, "✅ Activated citations for family: \(family.familyId)")
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
        
        for child in family.children {
            activeCitations[child.displayName] = basicCitation
            activeCitations[child.name] = basicCitation
        }
        
        logInfo(.citation, "✅ Generated \(activeCitations.count) basic person citations")
    }
    
    private func generatePersonSpecificCitations(for family: Family, network: FamilyNetwork) {
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
        
        // Generate enhanced citations for children
        for child in family.children {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                // Enhanced citation for married children
                let citation = generateEnhancedChildCitation(
                    child: child,
                    asParentFamily: asParentFamily,
                    network: network
                )
                // Children typically don't have patronymics, so displayName == name
                activeCitations[child.displayName] = citation
                activeCitations[child.name] = citation
                
                logDebug(.citation, "Generated enhanced citation for married child: \(child.displayName)")
            } else {
                // Regular nuclear family citation for unmarried children
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                activeCitations[child.displayName] = citation
                activeCitations[child.name] = citation
                
                logDebug(.citation, "Generated nuclear citation for unmarried child: \(child.displayName)")
            }
        }
        
        logInfo(.citation, "✅ Generated \(activeCitations.count) person-specific citations")
    }
    
    private func enhanceChildrenWithAsParentDates(family: Family, network: FamilyNetwork) -> Family {
        // Create enhanced copies of children with additional date information
        var enhancedCouples: [Couple] = []
        
        for couple in family.couples {
            var enhancedChildren: [Person] = []
            
            for child in couple.children {
                var enhancedChild = child
                
                // Get additional dates from asParent family
                if let asParentFamily = network.getAsParentFamily(for: child) {
                    // Find this child as a parent in their asParent family
                    if let childAsParent = asParentFamily.allParents.first(where: { $0.name.lowercased() == child.name.lowercased() }) {
                        
                        // Enhance with death date if missing in nuclear family
                        if enhancedChild.deathDate == nil && childAsParent.deathDate != nil {
                            enhancedChild.deathDate = childAsParent.deathDate
                        }
                        
                        // Enhance with full marriage date if nuclear only has partial
                        if childAsParent.fullMarriageDate != nil {
                            enhancedChild.fullMarriageDate = childAsParent.fullMarriageDate
                        } else if enhancedChild.marriageDate == nil && childAsParent.marriageDate != nil {
                            enhancedChild.marriageDate = childAsParent.marriageDate
                        }
                    }
                }
                
                enhancedChildren.append(enhancedChild)
            }
            
            let enhancedCouple = Couple(
                husband: couple.husband,
                wife: couple.wife,
                marriageDate: couple.marriageDate,
                children: enhancedChildren,
                childrenDiedInfancy: couple.childrenDiedInfancy,
                coupleNotes: couple.coupleNotes
            )
            
            enhancedCouples.append(enhancedCouple)
        }
        
        return Family(
            familyId: family.familyId,
            pageReferences: family.pageReferences,
            couples: enhancedCouples,
            notes: family.notes,
            noteDefinitions: family.noteDefinitions
        )
    }
    
    private func generateEnhancedChildCitation(child: Person, asParentFamily: Family, network: FamilyNetwork) -> String {
        // VERIFICATION: This should only be called for children, never parents
        logDebug(.citation, "Generating enhanced citation for child: \(child.displayName) using asParent family: \(asParentFamily.familyId)")
        
        // Start with nuclear family citation (where the child grew up)
        var citation = CitationGenerator.generateMainFamilyCitation(family: network.mainFamily)
        
        // Find additional date information from asParent family (where child became parent)
        var additionalInfo: [String] = []
        
        if let childAsParent = asParentFamily.allParents.first(where: { $0.name.lowercased() == child.name.lowercased() }) {
            
            // Check for death date not in nuclear family
            if childAsParent.deathDate != nil && child.deathDate == nil {
                additionalInfo.append("death date \(childAsParent.deathDate!)")
            }
            
            // Check for enhanced marriage date not in nuclear family
            if let fullMarriage = childAsParent.fullMarriageDate, child.fullMarriageDate == nil {
                additionalInfo.append("marriage date \(fullMarriage)")
            } else if let basicMarriage = childAsParent.marriageDate, child.marriageDate == nil {
                additionalInfo.append("marriage date \(basicMarriage)")
            }
        }
        
        // Add Additional Information section ONLY if we have additional info
        if !additionalInfo.isEmpty {
            citation += "\nAdditional Information:\n"
            let infoList = additionalInfo.joined(separator: ", ")
            citation += "\(child.displayName)'s \(infoList) found on \(asParentFamily.pageReferenceString)\n"
        }
        
        return citation
    }
    
    /**
     * Create a modified network that includes the parent's asParent family information
     * For a parent in the nuclear family, their asParent family is the nuclear family itself
     */
    private func createNetworkWithParentAsParent(for parent: Person, network: FamilyNetwork) -> FamilyNetwork {
        // Create a modified network that includes the parent's asParent family
        var modifiedNetwork = network
        
        // The parent's asParent family is the main nuclear family where they appear as a parent
        // We add this to the asParentFamilies dictionary so the citation generator can find it
        // Use displayName as key for disambiguation
        modifiedNetwork.asParentFamilies[parent.displayName] = network.mainFamily
        modifiedNetwork.asParentFamilies[parent.name] = network.mainFamily  // Also store by name
        
        return modifiedNetwork
    }
    
    // MARK: - Helper Methods
    
    private func findPersonInMainFamily(named name: String) -> Person? {
        guard let network = familyNetwork else { return nil }
        return network.mainFamily.findPerson(named: name)
    }
}
