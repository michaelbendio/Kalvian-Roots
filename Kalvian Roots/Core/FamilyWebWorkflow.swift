//
//  FamilyWebWorkflow.swift
//  Kalvian Roots
//
//  Coordinates family web processing with progressive UI updates
//
//  Created by Michael Bendio on 8/7/25.
//

import Foundation
import SwiftUI

/**
 * Orchestrates the complete family web processing workflow
 * Using existing FamilyResolver and CitationGenerator components
 */
@Observable
class FamilyWebWorkflow {
    
    // MARK: - Dependencies
    
    private let aiParsingService: AIParsingService
    private let familyResolver: FamilyResolver
    private let citationGenerator: CitationGenerator
    
    // MARK: - Published State
    
    var isProcessing = false
    var currentStep = "Ready"
    var progress: Double = 0.0
    var activeCitations: [String: String] = [:]  // PersonName -> CitationText
    var processingErrors: [String] = []
    
    // MARK: - Private State
    
    private var familyNetwork: FamilyNetwork?
    
    // MARK: - Initializer
    
    init(aiParsingService: AIParsingService, familyResolver: FamilyResolver) {
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
        self.citationGenerator = CitationGenerator()
    }
    
    // MARK: - Main Workflow
    
    /**
     * Process complete family web with progressive UI updates
     */
    func processFamilyWeb(for familyId: String) async throws {
        isProcessing = true
        progress = 0.0
        activeCitations.clear()
        processingErrors.clear()
        
        defer {
            isProcessing = false
        }
        
        do {
            // Step 1: Parse nuclear family (20% progress)
            currentStep = "Parsing nuclear family..."
            let nuclearFamily = try await parseNuclearFamily(familyId: familyId)
            progress = 0.2
            
            // Generate initial citations for nuclear family
            await generateAndActivateCitations(for: nuclearFamily, type: .nuclear)
            
            // Step 2: Resolve cross-references (60% progress total)
            currentStep = "Resolving family relationships..."
            familyNetwork = try await resolveFamilyNetwork(nuclearFamily: nuclearFamily)
            progress = 0.8
            
            // Step 3: Generate enhanced citations (100% progress)
            currentStep = "Generating enhanced citations..."
            await generateEnhancedCitations()
            progress = 1.0
            
            currentStep = "Complete"
            
        } catch {
            processingErrors.append("Family web processing failed: \(error.localizedDescription)")
            currentStep = "Failed"
            throw error
        }
    }
    
    // MARK: - Step Implementations
    
    private func parseNuclearFamily(familyId: String) async throws -> Family {
        logInfo(.parsing, "🔍 Parsing nuclear family: \(familyId)")
        return try await aiParsingService.parseFamily(familyId: familyId, familyText: "")  // You'll need to extract family text
    }
    
    private func resolveFamilyNetwork(nuclearFamily: Family) async throws -> FamilyNetwork {
        logInfo(.resolver, "🕸️ Building family network for: \(nuclearFamily.familyId)")
        
        let network = try await familyResolver.resolveFamilyNetwork(for: nuclearFamily)
        
        // Update UI progressively as families are resolved
        await updateCitationsFromNetwork(network)
        
        return network
    }
    
    @MainActor
    private func generateAndActivateCitations(for family: Family, type: CitationType) {
        logInfo(.citation, "📄 Generating \(type) citations for: \(family.familyId)")
        
        // Generate citations using existing CitationGenerator
        let familyCitations = citationGenerator.generateFamilyCitations(family: family)
        
        // Activate citations in UI
        for (personName, citation) in familyCitations {
            activeCitations[personName] = citation.displayText
        }
        
        logInfo(.citation, "✅ Activated \(familyCitations.count) citations")
    }
    
    @MainActor
    private func updateCitationsFromNetwork(_ network: FamilyNetwork) {
        logInfo(.citation, "🔄 Updating citations from resolved network")
        
        // Update citations for as_child families
        for (personName, asChildFamily) in network.asChildFamilies {
            let citations = citationGenerator.generateFamilyCitations(family: asChildFamily)
            for (citationPersonName, citation) in citations {
                activeCitations[citationPersonName] = citation.displayText
            }
        }
        
        // Update citations for as_parent families
        for (personName, asParentFamily) in network.asParentFamilies {
            let citations = citationGenerator.generateFamilyCitations(family: asParentFamily)
            for (citationPersonName, citation) in citations {
                activeCitations[citationPersonName] = citation.displayText
            }
        }
        
        // Update citations for spouse as_child families
        for (spouseName, spouseFamily) in network.spouseAsChildFamilies {
            let citations = citationGenerator.generateFamilyCitations(family: spouseFamily)
            for (citationPersonName, citation) in citations {
                activeCitations[citationPersonName] = citation.displayText
            }
        }
        
        logInfo(.citation, "✅ Updated citations from network - total active: \(activeCitations.count)")
    }
    
    @MainActor
    private func generateEnhancedCitations() {
        guard let network = familyNetwork else { return }
        
        logInfo(.citation, "✨ Generating enhanced citations with cross-reference data")
        
        // Generate enhanced citations for married children who have as_parent families
        for child in network.mainFamily.marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                // Generate enhanced citation with death/marriage dates from as_parent family
                let enhancedCitation = citationGenerator.generateEnhancedChildCitation(
                    child: child,
                    nuclearFamily: network.mainFamily,
                    asParentFamily: asParentFamily
                )
                activeCitations[child.displayName] = enhancedCitation.displayText
            }
        }
        
        logInfo(.citation, "✅ Enhanced citations complete")
    }
    
    // MARK: - Public Access Methods
    
    func getFamilyNetwork() -> FamilyNetwork? {
        return familyNetwork
    }
    
    func getCitationText(for personName: String) -> String? {
        return activeCitations[personName]
    }
    
    func getAllActiveCitations() -> [String: String] {
        return activeCitations
    }
    
    // MARK: - Helper Types
    
    enum CitationType {
        case nuclear
        case asChild
        case asParent
        case enhanced
    }
}

// MARK: - Extensions

extension Dictionary where Key == String, Value == String {
    mutating func clear() {
        removeAll()
    }
}

// MARK: - SwiftUI Integration Helper

/**
 * SwiftUI view model that wraps FamilyWebWorkflow
 */
@Observable
class FamilyWebViewModel {
    private let workflow: FamilyWebWorkflow
    
    var isProcessing: Bool { workflow.isProcessing }
    var currentStep: String { workflow.currentStep }
    var progress: Double { workflow.progress }
    var activeCitations: [String: String] { workflow.activeCitations }
    var processingErrors: [String] { workflow.processingErrors }
    
    init(aiParsingService: AIParsingService, familyResolver: FamilyResolver) {
        self.workflow = FamilyWebWorkflow(aiParsingService: aiParsingService, familyResolver: familyResolver)
    }
    
    func startProcessing(familyId: String) {
        Task {
            do {
                try await workflow.processFamilyWeb(for: familyId)
            } catch {
                // Error handling is managed by workflow
            }
        }
    }
    
    func isCitationActive(for personName: String) -> Bool {
        return activeCitations[personName] != nil
    }
    
    func getCitationText(for personName: String) -> String {
        return activeCitations[personName] ?? ""
    }
}
