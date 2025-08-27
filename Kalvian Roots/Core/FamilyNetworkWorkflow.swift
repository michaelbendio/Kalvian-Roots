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
     * Process complete family network with enhanced citations
     */
    func processFamilyNetwork(for familyId: String) async throws {
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
            
            // Step 2: Resolve cross-references (60% progress)
            await updateProgress(step: "Resolving cross-references...", progress: 0.6)
            let network = try await resolveFamilyNetwork(nuclearFamily: nuclearFamily)
            
            // Store network for retrieval
            familyNetwork = network
            
            // Step 3: Generate all citations (90% progress)
            await updateProgress(step: "Generating enhanced citations...", progress: 0.9)
            generateAndActivateCitations(for: nuclearFamily, type: .nuclear)
            
            // Complete
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
        for parent in family.allParents {
            activeCitations[parent.name] = basicCitation
        }
        
        for child in family.children {
            activeCitations[child.name] = basicCitation
        }
        
        logInfo(.citation, "✅ Generated \(activeCitations.count) basic person citations")
    }
    
    private func generatePersonSpecificCitations(for family: Family, network: FamilyNetwork) {
        logInfo(.citation, "👥 Generating person-specific citations")
        
        for parent in family.allParents {
            logInfo(.citation, "🔍 DEBUG: Processing parent '\(parent.name)' with asChild='\(parent.asChild ?? "nil")'")
            
            if let asChildFamily = network.getAsChildFamily(for: parent) {
                logInfo(.citation, "✅ Found asChild family: \(asChildFamily.familyId)")
                let citation = CitationGenerator.generateAsChildCitation(for: parent, in: asChildFamily)
                activeCitations[parent.name] = citation
                // DEBUG: Verify what we just stored
                logInfo(.citation, "🔍 STORED citation for '\(parent.name)': \(citation.prefix(100))...")
                logInfo(.citation, "🔍 VERIFY retrieval: \(activeCitations[parent.name]?.prefix(100) ?? "NOT FOUND")...")
            } else {
                logWarn(.citation, "❌ NO asChild family found for '\(parent.name)'")
                logInfo(.citation, "🔍 Available asChild families: \(Array(network.asChildFamilies.keys))")
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                activeCitations[parent.name] = citation
            }
        }
        
        for child in family.children {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                // FIXED: Enhanced citation for married children only
                let citation = generateEnhancedChildCitation(child: child, asParentFamily: asParentFamily, network: network)
                activeCitations[child.name] = citation
                logDebug(.citation, "Generated enhanced citation for married child: \(child.name)")
            } else {
                // Regular nuclear family citation for unmarried children
                let citation = CitationGenerator.generateMainFamilyCitation(family: family)
                activeCitations[child.name] = citation
                logDebug(.citation, "Generated nuclear citation for unmarried child: \(child.name)")
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
        logDebug(.citation, "Generating enhanced citation for child: \(child.name) using asParent family: \(asParentFamily.familyId)")
        
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

