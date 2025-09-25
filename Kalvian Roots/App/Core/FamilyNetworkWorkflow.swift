//
//  FamilyNetworkWorkflow.swift
//  Kalvian Roots
//
//  Simplified workflow for building family networks only
//  REMOVED: All citation generation - citations are now generated on-demand
//

import Foundation

/**
 * Simplified workflow for processing a nuclear family
 *
 * This workflow handles:
 * 1. Optional cross-reference resolution (as_child, as_parent, spouse families)
 * 2. Building the complete family network
 *
 * Citations are NO LONGER generated here - they're created on-demand when needed
 */
class FamilyNetworkWorkflow {
    
    // MARK: - Properties
    
    private let nuclearFamily: Family
    private let familyResolver: FamilyResolver
    private let shouldResolveCrossReferences: Bool
    
    private var familyNetwork: FamilyNetwork?
    
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
     * Process the workflow - builds network only, no citations
     */
    func process() async throws {
        logInfo(.resolver, "🎯 Starting workflow processing for: \(nuclearFamily.familyId)")
        
        if shouldResolveCrossReferences {
            // Build the complete family network
            familyNetwork = try await buildFamilyNetwork(for: nuclearFamily)
            
            logInfo(.resolver, "✅ Family network built successfully")
            logDebugNetworkSummary()
        } else {
            // Create basic network without cross-references
            familyNetwork = FamilyNetwork(mainFamily: nuclearFamily)
            logInfo(.resolver, "✅ Basic network created (no cross-references)")
        }
        
        logInfo(.resolver, "✅ Workflow processing complete for: \(nuclearFamily.familyId)")
    }
    
    /**
     * Get the family network (if resolved)
     */
    func getFamilyNetwork() -> FamilyNetwork? {
        return familyNetwork
    }
    
    /**
     * Activate cached network (used when loading from cache)
     */
    func activateCachedNetwork(_ network: FamilyNetwork) {
        self.familyNetwork = network
        logInfo(.resolver, "✅ Activated cached network for: \(network.mainFamily.familyId)")
        logDebugNetworkSummary()
    }
    
    // MARK: - Private Methods
    
    private func buildFamilyNetwork(for nuclearFamily: Family) async throws -> FamilyNetwork {
        logInfo(.resolver, "🕸️ Building family network for: \(nuclearFamily.familyId)")
        
        // Use FamilyResolver to resolve all cross-references
        let network = try await familyResolver.resolveCrossReferences(for: nuclearFamily)
        
        return network
    }
    
    private func logDebugNetworkSummary() {
        guard let network = familyNetwork else { return }
        
        logInfo(.resolver, "📊 Network Summary:")
        logInfo(.resolver, "  - Nuclear family: \(network.mainFamily.familyId)")
        logInfo(.resolver, "  - Parents: \(network.mainFamily.allParents.count)")
        logInfo(.resolver, "  - Children: \(network.mainFamily.allChildren.count)")
        
        // Log cross-reference families
        let asChildFamilies = Set(network.asChildFamilies.values)
        let asParentFamilies = Set(network.asParentFamilies.values)
        let spouseFamilies = Set(network.spouseAsChildFamilies.values)
        
        logInfo(.resolver, "  - Unique asChild families: \(asChildFamilies.count)")
        for family in asChildFamilies {
            logDebug(.resolver, "    • \(family.familyId)")
        }
        
        logInfo(.resolver, "  - Unique asParent families: \(asParentFamilies.count)")
        for family in asParentFamilies {
            logDebug(.resolver, "    • \(family.familyId)")
        }
        
        logInfo(.resolver, "  - Unique spouse families: \(spouseFamilies.count)")
        for family in spouseFamilies {
            logDebug(.resolver, "    • \(family.familyId)")
        }
        
        // Log storage keys for debugging
        logDebug(.resolver, "  - AsChild keys: \(Array(network.asChildFamilies.keys).sorted())")
        logDebug(.resolver, "  - AsParent keys: \(Array(network.asParentFamilies.keys).sorted())")
        logDebug(.resolver, "  - Spouse keys: \(Array(network.spouseAsChildFamilies.keys).sorted())")
    }
}
