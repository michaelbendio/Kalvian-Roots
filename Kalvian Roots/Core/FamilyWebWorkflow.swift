//
//  FamilyWebWorkflow.swift
//  Kalvian Roots
//
//  Coordinates family web processing with progressive UI updates and debug logging
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
    private let fileManager: FileManager
    
    // MARK: - Published State
    
    var isProcessing = false
    var currentStep = "Ready"
    var progress: Double = 0.0
    var activeCitations: [String: String] = [:]  // PersonName -> CitationText
    var processingErrors: [String] = []
    
    // MARK: - Private State
    
    private var familyNetwork: FamilyNetwork?
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService, familyResolver: FamilyResolver, fileManager: FileManager) {
        logInfo(.workflow, "🕸️ FamilyWebWorkflow initialization started")
        
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
        self.fileManager = fileManager
        
        logInfo(.workflow, "✅ FamilyWebWorkflow initialized")
    }
    
    // MARK: - Public Interface
    
    /**
     * Process complete family web with progressive updates
     */
    func processFamilyWeb(for familyId: String) async throws {
        logInfo(.workflow, "🚀 Starting family web processing for: \(familyId)")
        
        await MainActor.run {
            isProcessing = true
            currentStep = "Initializing..."
            progress = 0.0
            activeCitations.removeAll()
            processingErrors.removeAll()
        }
        
        do {
            // Step 1: Parse nuclear family (20% progress)
            await updateProgress(step: "Parsing nuclear family...", progress: 0.2)
            let nuclearFamily = try await parseNuclearFamily(familyId: familyId)
            
            // Generate initial citations
            generateAndActivateCitations(for: nuclearFamily, type: .nuclear)
            
            // Step 2: Resolve cross-references (60% progress)
            await updateProgress(step: "Resolving cross-references...", progress: 0.6)
            let network = try await resolveFamilyNetwork(nuclearFamily: nuclearFamily)
            
            // Store network for retrieval
            familyNetwork = network
            
            // Step 3: Generate enhanced citations (90% progress)
            await updateProgress(step: "Generating enhanced citations...", progress: 0.9)
            generateEnhancedCitations()
            
            // Complete
            await updateProgress(step: "Complete", progress: 1.0)
            await MainActor.run {
                isProcessing = false
            }
            
            logInfo(.workflow, "✅ Family web processing completed successfully")
            
        } catch {
            await MainActor.run {
                processingErrors.append("Processing failed: \(error.localizedDescription)")
                currentStep = "Failed"
                isProcessing = false
            }
            
            logError(.workflow, "❌ Family web processing failed: \(error)")
            throw error
        }
    }
    
    /**
     * Get the resolved family network
     */
    func getFamilyNetwork() -> FamilyNetwork? {
        return familyNetwork
    }
    
    /**
     * Get active citations
     */
    func getActiveCitations() -> [String: String] {
        return activeCitations
    }
    
    // MARK: - Private Implementation
    
    private func updateProgress(step: String, progress: Double) async {
        await MainActor.run {
            currentStep = step
            self.progress = progress
        }
        logDebug(.workflow, "Progress: \(Int(progress * 100))% - \(step)")
    }
    
    private func parseNuclearFamily(familyId: String) async throws -> Family {
        logInfo(.parsing, "🔍 Parsing nuclear family: \(familyId)")
        
        // Extract family text before parsing
        guard let fileContent = fileManager.currentFileContent else {
            logError(.parsing, "❌ No file content available")
            throw JuuretError.noFileLoaded
        }
        
        // Extract family text using FileManager's method
        guard let familyText = fileManager.extractFamilyText(familyId: familyId, from: fileContent) else {
            logError(.parsing, "❌ Family \(familyId) not found in file")
            throw JuuretError.familyNotFound(familyId)
        }
        
        logDebug(.parsing, "📝 Extracted family text (\(familyText.count) characters)")
        
        // Parse the family with actual text
        return try await aiParsingService.parseFamily(familyId: familyId, familyText: familyText)
    }
    
    private func resolveFamilyNetwork(nuclearFamily: Family) async throws -> FamilyNetwork {
        logInfo(.resolver, "🕸️ Building family network for: \(nuclearFamily.familyId)")
        
        // Use correct method name from FamilyResolver
        let network = try await familyResolver.resolveCrossReferences(for: nuclearFamily)
        
        // Update UI progressively as families are resolved
        updateCitationsFromNetwork(network)
        
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
        
        // Use static methods that actually exist
        let mainCitation = CitationGenerator.generateMainFamilyCitation(family: family)
        
        // Generate citations for each person in family based on type
        switch type {
        case .nuclear:
            // For nuclear family, use main family citation for the family unit
            activeCitations[family.familyId] = mainCitation
            
            // FIXED: Generate as-child citations for parents who have references
            for parent in family.allParents {
                if parent.asChild != nil {
                    let asChildCitation = CitationGenerator.generateAsChildCitation(for: parent, in: family)
                    activeCitations[parent.name] = asChildCitation
                }
            }
            
        case .asChild:
            // Generate as-child citations for specific person
            for person in family.allPersons {
                let citation = CitationGenerator.generateAsChildCitation(for: person, in: family)
                activeCitations[person.name] = citation
            }
            
        case .asParent:
            // Generate main family citations (this person as parent)
            activeCitations[family.familyId] = mainCitation
            
        case .enhanced:
            // Generate enhanced citations with cross-reference data
            activeCitations[family.familyId] = mainCitation
        }
        
        logInfo(.citation, "✅ Activated citations for family: \(family.familyId)")
    }
    
    private func updateCitationsFromNetwork(_ network: FamilyNetwork) {
        logInfo(.citation, "🔄 Updating citations from resolved network")
        
        // Use static methods that return String directly
        
        // Update citations for as-child families (where parents came from)
        for (personName, asChildFamily) in network.asChildFamilies {
            if let person = findPersonInMainFamily(named: personName) {
                let citation = CitationGenerator.generateAsChildCitation(for: person, in: asChildFamily)
                activeCitations[personName] = citation
            }
        }
        
        // Update citations for as-parent families (where children are parents)
        for (personName, asParentFamily) in network.asParentFamilies {
            let citation = CitationGenerator.generateMainFamilyCitation(family: asParentFamily)
            activeCitations[personName] = citation
        }
        
        // Update citations for spouse as-child families
        for (spouseName, spouseFamily) in network.spouseAsChildFamilies {
            // Check if this spouse exists in our main family
            if network.mainFamily.children.contains(where: { $0.spouse == spouseName }) {
                // Generate citation for the spouse's family
                let citation = CitationGenerator.generateMainFamilyCitation(family: spouseFamily)
                activeCitations[spouseName] = citation
            }
        }
        
        logInfo(.citation, "✅ Updated citations from network - total active: \(activeCitations.count)")
    }
    
    private func generateEnhancedCitations() {
        guard let network = familyNetwork else { return }
        
        logInfo(.citation, "✨ Generating enhanced citations with cross-reference data")
        
        // FIXED: Use actual methods that exist
        for child in network.mainFamily.marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                // Generate enhanced citation using the as-parent family where child is a parent
                let enhancedCitation = CitationGenerator.generateMainFamilyCitation(family: asParentFamily)
                activeCitations[child.name] = enhancedCitation
            }
            
            // FIXED: Also generate as-child citation if the child has cross-reference data
            if child.asChildReference != nil {
                let asChildCitation = CitationGenerator.generateAsChildCitation(for: child, in: network.mainFamily)
                activeCitations["\(child.name)_asChild"] = asChildCitation
            }
        }
        
        // FIXED: Generate enhanced citations for parents with resolved as-child families
        for parent in network.mainFamily.allParents {
            if let asChildFamily = network.asChildFamilies[parent.name] {
                let asChildCitation = CitationGenerator.generateAsChildCitation(for: parent, in: asChildFamily)
                activeCitations["\(parent.name)_asChild"] = asChildCitation
            }
        }
        
        logInfo(.citation, "✅ Enhanced citations complete")
    }
    
    // MARK: - Helper Methods
    
    private func findPersonInMainFamily(named name: String) -> Person? {
        guard let network = familyNetwork else { return nil }
        return network.mainFamily.findPerson(named: name)
    }
}
