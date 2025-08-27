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
class FamilyNetworkWorkflow {
    
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
        logInfo(.workflow, "🕸️ FamilyNetworkWorkflow initialization started")
        
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
        self.fileManager = fileManager
        
        logInfo(.workflow, "✅ FamilyNetworkWorkflow initialized")
    }
    
    // MARK: - Public Interface
    
    /**
     * Process complete family network with progressive updates
     */
    func updateCitationsFromNetwork(for familyId: String) async throws {
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
            
            // Step 2: Resolve cross-references and generate enhanced citations (80% progress)
            await updateProgress(step: "Resolving cross-references...", progress: 0.8)
            let network = try await resolveFamilyNetwork(nuclearFamily: nuclearFamily)
            
            // Store network for retrieval
            familyNetwork = network
            
            // Step 3: Complete (citations already generated in resolveFamilyNetwork)
            await updateProgress(step: "Complete", progress: 1.0)
            await MainActor.run {
                isProcessing = false
            }
            
            logInfo(.workflow, "✅ Family web processing completed successfully")
            logInfo(.workflow, "📄 Generated \(activeCitations.count) enhanced citations")
            
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
        
        switch type {
        case .nuclear:
            // Generate enhanced nuclear citation with network context
            if let network = familyNetwork {
                // First, enhance children with dates from asParent families
                let enhancedFamily = enhanceChildrenWithAsParentDates(family: family, network: network)
                
                let enhancedCitation = CitationGenerator.generateNuclearFamilyCitationWithSupplement(
                    family: enhancedFamily,
                    network: network
                )
                activeCitations[family.familyId] = enhancedCitation
            } else {
                // Fallback to standard citation
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                activeCitations[family.familyId] = citation
            }
            
        case .asChild, .asParent, .enhanced:
            let citation = CitationGenerator.generateMainFamilyCitation(family: family)
            activeCitations[family.familyId] = citation
        }
        
        logInfo(.citation, "✅ Activated citations for family: \(family.familyId)")
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
    
    private func updateCitationsFromNetwork(_ network: FamilyNetwork) {
        logInfo(.citation, "🔄 Updating citations from resolved network")
        
        // CORRECT: Generate parent citations from their asChild families (not main family)
        for parent in network.mainFamily.allParents {
            if let asChildFamily = network.getAsChildFamily(for: parent) {
                let citation = CitationGenerator.generateAsChildCitation(for: parent, in: asChildFamily)
                activeCitations[parent.name] = citation
            }
        }
        
        // Generate enhanced child citations with additional date information
        for child in network.mainFamily.children {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                let citation = generateEnhancedChildCitation(child: child, asParentFamily: asParentFamily, network: network)
                activeCitations[child.name] = citation
            }
        }
        
        logInfo(.citation, "✅ Updated citations from network - total active: \(activeCitations.count)")
    }
    
    private func generateEnhancedChildCitation(child: Person, asParentFamily: Family, network: FamilyNetwork) -> String {
        // FIXED: Start with regular nuclear family citation (not as-child style)
        // The child should see the family they grew up in, not be highlighted as the target person
        var citation = CitationGenerator.generateMainFamilyCitation(family: network.mainFamily)
        
        // Find additional date information from asParent family
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
        
        // Add Additional Information section if we have any
        if !additionalInfo.isEmpty {
            citation += "\nAdditional Information:\n"
            let infoList = additionalInfo.joined(separator: ", ")
            citation += "\(child.name)'s \(infoList) found on \(asParentFamily.pageReferenceString)\n"
        }
        
        return citation
    }
    
    // MARK: - Helper Methods
    
    private func findPersonInMainFamily(named name: String) -> Person? {
        guard let network = familyNetwork else { return nil }
        return network.mainFamily.findPerson(named: name)
    }
}

