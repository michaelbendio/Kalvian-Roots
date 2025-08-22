//
//  FamilyWebWorkflow.swift
//  Kalvian Roots
//
//  Coordinates family web processing with progressive UI updates and debug logging
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
    private let fileManager: FileManager
    
    // MARK: - Published State
    
    var isProcessing = false
    var currentStep = "Ready"
    var progress: Double = 0.0
    var activeCitations: [String: String] = [:]  // PersonName -> CitationText
    var processingErrors: [String] = []
    
    // MARK: - Private State
    
    private var familyNetwork: FamilyNetwork?
    
    // MARK: - Initializer
    
    init(aiParsingService: AIParsingService, familyResolver: FamilyResolver, fileManager: FileManager) {
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
        self.fileManager = fileManager
    }
    
    // MARK: - Main Workflow
    
    /**
     * Process complete family web with progressive UI updates
     */
    func processFamilyWeb(for familyId: String) async throws {
        isProcessing = true
        progress = 0.0
        activeCitations.removeAll()
        processingErrors.removeAll()
        
        defer {
            isProcessing = false
        }
        
        do {
            // Step 1: Parse nuclear family (20% progress)
            currentStep = "Parsing nuclear family..."
            let nuclearFamily = try await parseNuclearFamily(familyId: familyId)
            progress = 0.2
            debugLogWorkflowState("Nuclear family parsed")
            
            // Generate initial citations for nuclear family
            generateAndActivateCitations(for: nuclearFamily, type: .nuclear)
            
            // Step 2: Resolve cross-references (60% progress total)
            currentStep = "Resolving family relationships..."
            familyNetwork = try await resolveFamilyNetwork(nuclearFamily: nuclearFamily)
            progress = 0.8
            debugLogWorkflowState("Cross-references resolved")
            
            // Step 3: Generate enhanced citations (100% progress)
            currentStep = "Generating enhanced citations..."
            generateEnhancedCitations()
            progress = 1.0
            debugLogWorkflowState("Citations generated")
            
            currentStep = "Complete"
            debugLogWorkflowState("Workflow complete")
            
        } catch {
            processingErrors.append("Family web processing failed: \(error.localizedDescription)")
            currentStep = "Failed"
            debugLogWorkflowState("Workflow failed")
            throw error
        }
    }
    
    // MARK: - Step Implementations
    
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
    
    private func generateAndActivateCitations(for family: Family, type: CitationType) {
        logInfo(.citation, "📄 Generating \(type) citations for: \(family.familyId)")
        
        // Use static methods that actually exist
        let mainCitation = CitationGenerator.generateMainFamilyCitation(family: family)
        
        // Generate citations for each person in family based on type
        switch type {
        case .nuclear:
            // For nuclear family, use main family citation for the family unit
            activeCitations[family.familyId] = mainCitation
            
            // Generate as-child citations for parents who have references
            for parent in family.allParents {
                if parent.asChildReference != nil {
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
        
        // Use actual methods that exist
        for child in network.mainFamily.marriedChildren {
            if let asParentFamily = network.getAsParentFamily(for: child) {
                // Generate enhanced citation using the as-parent family where child is a parent
                let enhancedCitation = CitationGenerator.generateMainFamilyCitation(family: asParentFamily)
                activeCitations[child.name] = enhancedCitation
            }
            
            // Also generate as-child citation if the child has cross-reference data
            if child.asChildReference != nil {
                let asChildCitation = CitationGenerator.generateAsChildCitation(for: child, in: network.mainFamily)
                activeCitations["\(child.name)_asChild"] = asChildCitation
            }
        }
        
        // Generate enhanced citations for parents with resolved as-child families
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
        guard let family = familyNetwork?.mainFamily else { return nil }
        
        // Check all persons in the family
        return family.allPersons.first { $0.name.lowercased() == name.lowercased() }
    }
    
    // MARK: - Debug Logging
    
    /// Debug the workflow state after each major step
    private func debugLogWorkflowState(_ step: String) {
        logInfo(.app, "🔄 === WORKFLOW STATE: \(step) ===")
        logInfo(.app, "  Progress: \(Int(progress * 100))%")
        logInfo(.app, "  Current Step: \(currentStep)")
        logInfo(.app, "  Active Citations: \(activeCitations.count)")
        
        if let network = familyNetwork {
            logInfo(.app, "  📊 Network Stats:")
            logInfo(.app, "    - As-child families: \(network.asChildFamilies.count)")
            logInfo(.app, "    - As-parent families: \(network.asParentFamilies.count)")
            logInfo(.app, "    - Spouse families: \(network.spouseAsChildFamilies.count)")
            logInfo(.app, "    - Total resolved: \(network.totalResolvedFamilies)")
            
            // Log specific families for KORPI 6
            if network.mainFamily.familyId.uppercased().contains("KORPI 6") {
                logInfo(.app, "  🎯 KORPI 6 Specific Results:")
                logInfo(.app, "    Expected: 2 parent origins + 5 child families = 7 total")
                logInfo(.app, "    Found: \(network.totalResolvedFamilies) families")
                
                if network.totalResolvedFamilies < 7 {
                    logWarn(.app, "    ⚠️ Missing \(7 - network.totalResolvedFamilies) expected families!")
                } else if network.totalResolvedFamilies == 7 {
                    logInfo(.app, "    ✅ All expected families resolved!")
                }
            }
        }
        
        if !processingErrors.isEmpty {
            logError(.app, "  ❌ Errors: \(processingErrors.joined(separator: ", "))")
        }
        
        logInfo(.app, "🔄 === END WORKFLOW STATE ===")
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
    
    init(aiParsingService: AIParsingService, familyResolver: FamilyResolver, fileManager: FileManager) {
        // Pass fileManager to workflow
        self.workflow = FamilyWebWorkflow(
            aiParsingService: aiParsingService,
            familyResolver: familyResolver,
            fileManager: fileManager
        )
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
