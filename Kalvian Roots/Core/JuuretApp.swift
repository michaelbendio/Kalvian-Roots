//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Unified family processing with comprehensive cross-reference resolution
//

import Foundation
import SwiftUI

/**
 * JuuretApp.swift - Main application coordinator with unified workflow
 *
 * Single "Process" button workflow that:
 * 1. Extracts nuclear family with AI
 * 2. Automatically resolves all cross-references
 * 3. Provides appropriate citations based on person's role
 */

@Observable
class JuuretApp {
    
    // MARK: - Core Services
    
    /// AI parsing service with configurable providers
    let aiParsingService: AIParsingService
    
    /// Cross-reference resolution service
    let familyResolver: FamilyResolver
    
    /// Name equivalence learning service
    let nameEquivalenceManager: NameEquivalenceManager
    
    /// File management service
    var fileManager: FileManager
    
    // MARK: - State Properties
    
    /// Currently extracted family
    var currentFamily: Family?
    
    /// Enhanced family with cross-reference data
    var enhancedFamily: Family?
    
    /// Family network with all resolved cross-references
    var familyNetwork: FamilyNetwork?
    
    /// Processing state
    var isProcessing = false
    
    /// Error state
    var errorMessage: String? = nil
    
    /// Progress tracking
    var extractionProgress: ExtractionProgress = .idle
    
    // MARK: - Computed Properties
    
    var isReady: Bool {
        let ready = fileManager.isFileLoaded && aiParsingService.isConfigured
        logTrace(.app, "App ready state: \(ready) (file: \(fileManager.isFileLoaded), ai: \(aiParsingService.isConfigured))")
        return ready
    }
    
    var hasCurrentFamily: Bool {
        currentFamily != nil
    }
    
    var hasEnhancedFamily: Bool {
        enhancedFamily != nil
    }
    
    var currentServiceName: String {
        aiParsingService.currentServiceName
    }
    
    var availableServices: [String] {
        aiParsingService.availableServiceNames
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.app, "🚀 JuuretApp initialization started")
        
        // Initialize services
        self.nameEquivalenceManager = NameEquivalenceManager()
        #if os(macOS)
        if MLXService.isAvailable() {
            logInfo(.ai, "🚀 Apple Silicon detected - enabling MLX services")
            self.aiParsingService = AIParsingService() // Will auto-detect and add MLX services
            
            // Set recommended model based on hardware
            let recommendedModel = MLXService.getRecommendedModel()
            try? aiParsingService.switchToService(named: recommendedModel.name)
        } else {
            logInfo(.ai, "🖥️ Intel Mac detected - using cloud services")
            self.aiParsingService = AIParsingService()
        }
        #else
        // iOS/iPadOS - DeepSeek only for simplicity
        logInfo(.ai, "📱 iOS detected - using DeepSeek only")
        self.aiParsingService = AIParsingService()
        try? aiParsingService.switchToService(named: "DeepSeek")
        #endif
        self.familyResolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager
        )
        self.fileManager = FileManager()
        
        logInfo(.app, "✅ Core services initialized")
        logInfo(.app, "Current AI service: \(currentServiceName)")
        logDebug(.app, "Services available: \(availableServices.joined(separator: ", "))")
        
        // Auto-load default file
        Task { @MainActor in
            logDebug(.file, "Attempting auto-load of default file")
            await self.fileManager.autoLoadDefaultFile()
            if let fileContent = fileManager.currentFileContent {
                familyResolver.setFileContent(fileContent)
                logInfo(.file, "✅ Auto-loaded file and updated FamilyResolver")
            } else {
                logDebug(.file, "No default file found for auto-loading")
            }
        }
        
        logInfo(.app, "🎉 JuuretApp initialization complete")
    }
    
    // MARK: - AI Service Configuration
    
    /**
     * Switch to a different AI service
     */
    func switchAIService(to serviceName: String) async {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        do {
            try aiParsingService.switchToService(named: serviceName)
            
            await MainActor.run {
                // Clear any error state since service changed
                if errorMessage?.contains("not configured") == true {
                    errorMessage = nil
                    logDebug(.app, "Cleared configuration error after service switch")
                }
            }
            
            logInfo(.ai, "✅ Successfully switched to: \(serviceName)")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to switch AI service: \(error.localizedDescription)"
            }
            logError(.ai, "❌ Failed to switch AI service: \(error)")
        }
    }
    
    /**
     * Configure current AI service with API key
     */
    func configureAIService(apiKey: String) async {
        logInfo(.ai, "🔧 Configuring \(currentServiceName) with API key")
        logTrace(.ai, "API key length: \(apiKey.count) characters")
        
        do {
            try aiParsingService.configureCurrentService(apiKey: apiKey)
            
            await MainActor.run {
                errorMessage = nil
            }
            
            logInfo(.ai, "✅ Successfully configured \(currentServiceName)")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to configure AI service: \(error.localizedDescription)"
            }
            logError(.ai, "❌ Failed to configure AI service: \(error)")
        }
    }
    
    /**
     * Get status of all available AI services
     */
    func getAIServiceStatus() -> [(name: String, configured: Bool)] {
        let status = aiParsingService.getServiceStatus()
        logTrace(.ai, "AI service status requested: \(status.map { "\($0.name)=\($0.configured)" }.joined(separator: ", "))")
        return status
    }
    
    // MARK: - File Management Integration
    
    /**
     * Update family resolver when file content changes
     */
    @MainActor
    func updateFileContent() {
        logDebug(.file, "Updating FamilyResolver with new file content")
        
        if let fileContent = fileManager.currentFileContent {
            familyResolver.setFileContent(fileContent)
            logInfo(.file, "✅ FamilyResolver updated with file content (\(fileContent.count) characters)")
        } else {
            logWarn(.file, "No file content available for FamilyResolver update")
        }
    }
    
    // MARK: - Unified Family Processing (Main Workflow)
    
    /**
     * Complete family processing: extraction + cross-reference resolution
     * This is the main workflow triggered by the "Process" button
     */
    func processFamily(familyId: String) async throws {
        logInfo(.app, "🎯 Starting complete family processing for: \(familyId)")
        DebugLogger.shared.startTimer("complete_processing")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        logDebug(.parsing, "Normalized family ID: \(normalizedId)")
        
        guard FamilyIDs.validFamilyIds.contains(normalizedId) else {
            logError(.parsing, "❌ Invalid family ID: \(familyId)")
            throw JuuretError.invalidFamilyId(familyId)
        }
        
        guard aiParsingService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentServiceName)")
            throw JuuretError.aiServiceNotConfigured(currentServiceName)
        }
        
        await MainActor.run {
            isProcessing = true
            extractionProgress = .extractingFamily
            errorMessage = nil
            currentFamily = nil
            enhancedFamily = nil
            familyNetwork = nil
            logDebug(.app, "Set processing state and cleared previous data")
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
                extractionProgress = .idle
                let duration = DebugLogger.shared.endTimer("complete_processing")
                logInfo(.app, "Complete family processing finished in \(String(format: "%.2f", duration))s")
            }
        }
        
        do {
            // Step 1: Extract nuclear family
            logInfo(.app, "Step 1: Nuclear family extraction")
            try await extractNuclearFamily(familyId: normalizedId)
            
            // Step 2: Resolve cross-references
            logInfo(.app, "Step 2: Cross-reference resolution")
            try await resolveCrossReferences()
            
            await MainActor.run {
                extractionProgress = .complete
            }
            
            logInfo(.app, "✅ Complete family processing successful")
            
        } catch {
            logError(.app, "❌ Family processing failed: \(error)")
            
            await MainActor.run {
                self.errorMessage = "Failed to process family: \(error.localizedDescription)"
            }
            throw error
        }
    }
    
    // MARK: - Nuclear Family Extraction
    
    /**
     * Extract nuclear family using AI parsing service
     */
    private func extractNuclearFamily(familyId: String) async throws {
        logInfo(.parsing, "🔍 Starting nuclear family extraction for: \(familyId)")
        DebugLogger.shared.startTimer("nuclear_extraction")
        
        defer {
            let duration = DebugLogger.shared.endTimer("nuclear_extraction")
            logDebug(.parsing, "Nuclear extraction completed in \(String(format: "%.2f", duration))s")
        }
        
        // Extract family text from file
        logDebug(.file, "Extracting family text for: \(familyId)")
        guard let familyText = fileManager.extractFamilyText(familyId: familyId) else {
            logError(.file, "❌ Family text not found in file for: \(familyId)")
            throw JuuretError.extractionFailed("Family text not found in file")
        }
        
        logInfo(.file, "✅ Extracted family text (\(familyText.count) characters)")
        logTrace(.file, "Family text preview: \(String(familyText.prefix(200)))...")
        
        // Parse with AI service
        logInfo(.ai, "🤖 Starting AI parsing with \(currentServiceName)")
        let family = try await aiParsingService.parseFamily(
            familyId: familyId,
            familyText: familyText
        )
        
        // Validate extracted family
        logDebug(.parsing, "Validating extracted family structure")
        let warnings = family.validateStructure()
        DebugLogger.shared.logFamilyValidation(family, warnings: warnings)
        
        await MainActor.run {
            self.currentFamily = family
            self.extractionProgress = .familyExtracted
        }
        
        logInfo(.app, "✅ Nuclear family extraction successful: \(family.familyId)")
        logDebug(.parsing, "Father: \(family.father.displayName)")
        logDebug(.parsing, "Mother: \(family.mother?.displayName ?? "nil")")
        logDebug(.parsing, "Children: \(family.children.count)")
        logDebug(.parsing, "Cross-references needed: \(family.totalCrossReferencesNeeded)")
        
        DebugLogger.shared.logParsingSuccess(family)
    }
    
    // MARK: - Cross-Reference Resolution (Public for testing)
    
    /**
     * Resolve cross-references for current family (public for debug/testing)
     */
    func resolveCrossReferences() async throws {
        guard let family = currentFamily else {
            logError(.crossRef, "❌ No current family for cross-reference resolution")
            throw JuuretError.noCurrentFamily
        }
        
        logInfo(.crossRef, "🔗 Starting cross-reference resolution for: \(family.familyId)")
        DebugLogger.shared.startTimer("cross_reference_resolution")
        
        await MainActor.run {
            extractionProgress = .resolvingCrossReferences
        }
        
        defer {
            let duration = DebugLogger.shared.endTimer("cross_reference_resolution")
            logInfo(.crossRef, "Cross-reference resolution completed in \(String(format: "%.2f", duration))s")
        }
        
        do {
            // Resolve all cross-references
            logDebug(.crossRef, "Initiating cross-reference resolution with FamilyResolver")
            let network = try await familyResolver.resolveCrossReferences(for: family)
            
            // Create enhanced family with integrated data
            logDebug(.crossRef, "Creating enhanced family with integrated cross-reference data")
            let enhanced = network.createEnhancedFamily()
            
            await MainActor.run {
                self.familyNetwork = network
                self.enhancedFamily = enhanced
                self.extractionProgress = .crossReferencesResolved
            }
            
            let stats = familyResolver.getResolutionStatistics()
            logInfo(.crossRef, "✅ Cross-reference resolution complete")
            logDebug(.crossRef, "Resolved families: \(network.totalResolvedFamilies)")
            logDebug(.crossRef, "Success rate: \(String(format: "%.1f", stats.successRate * 100))%")
            logDebug(.crossRef, "As-child families: \(network.asChildFamilies.count)")
            logDebug(.crossRef, "As-parent families: \(network.asParentFamilies.count)")
            logDebug(.crossRef, "Spouse as-child families: \(network.spouseAsChildFamilies.count)")
            
        } catch {
            logError(.crossRef, "❌ Cross-reference resolution failed: \(error)")
            await MainActor.run {
                self.errorMessage = "Cross-reference resolution failed: \(error.localizedDescription)"
            }
            throw error
        }
    }
    
    // MARK: - Citation Generation (Role-Based)
    
    /**
     * Generate as_child citation for parents
     */
    func generateAsChildCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "👨‍👩‍👧‍👦 Generating as_child citation for: \(person.displayName)")
        DebugLogger.shared.startTimer("as_child_citation")
        
        // Check family network for person's as_child family
        if let network = familyNetwork,
           let asChildFamily = network.getAsChildFamily(for: person) {
            
            logDebug(.citation, "Found as_child family: \(asChildFamily.familyId)")
            let citation = EnhancedCitationGenerator.generateAsChildCitation(for: person, in: asChildFamily)
            let duration = DebugLogger.shared.endTimer("as_child_citation")
            logInfo(.citation, "✅ As_child citation generated (\(citation.count) chars) in \(String(format: "%.3f", duration))s")
            return citation
            
        } else {
            logWarn(.citation, "No as_child family found for \(person.displayName)")
            let duration = DebugLogger.shared.endTimer("as_child_citation")
            return "As_child citation for \(person.displayName) not found. Cross-reference resolution may be incomplete."
        }
    }
    
    /**
     * Generate as_parent citation for children
     */
    func generateAsParentCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "👨‍👩‍👧‍👦 Generating as_parent citation for: \(person.displayName)")
        DebugLogger.shared.startTimer("as_parent_citation")
        
        // Check family network for person's as_parent family
        if let network = familyNetwork,
           let asParentFamily = network.getAsParentFamily(for: person) {
            
            logDebug(.citation, "Found as_parent family: \(asParentFamily.familyId)")
            let citation = EnhancedCitationGenerator.generateMainFamilyCitation(family: asParentFamily)
            let duration = DebugLogger.shared.endTimer("as_parent_citation")
            logInfo(.citation, "✅ As_parent citation generated (\(citation.count) chars) in \(String(format: "%.3f", duration))s")
            return citation
            
        } else {
            logWarn(.citation, "No as_parent family found for \(person.displayName)")
            let duration = DebugLogger.shared.endTimer("as_parent_citation")
            return "As_parent citation for \(person.displayName) not found. This person may not be married or cross-reference resolution may be incomplete."
        }
    }
    
    /**
     * Generate spouse as_child citation
     */
    func generateSpouseCitation(spouseName: String, in family: Family) -> String {
        logInfo(.citation, "💑 Generating spouse as_child citation for: \(spouseName)")
        DebugLogger.shared.startTimer("spouse_citation")
        
        // Check family network for spouse's as_child family
        if let network = familyNetwork,
           let spouseFamily = network.getSpouseAsChildFamily(for: spouseName) {
            
            logDebug(.citation, "Found spouse as_child family: \(spouseFamily.familyId)")
            
            // Find the spouse in their as_child family
            if let spouse = spouseFamily.findChild(named: extractGivenName(from: spouseName)) {
                logDebug(.citation, "Found spouse as child in family, generating citation")
                let citation = EnhancedCitationGenerator.generateAsChildCitation(for: spouse, in: spouseFamily)
                let duration = DebugLogger.shared.endTimer("spouse_citation")
                logInfo(.citation, "✅ Spouse citation generated (\(citation.count) chars) in \(String(format: "%.3f", duration))s")
                return citation
            } else {
                logWarn(.citation, "Spouse not found as child in resolved family")
            }
        } else {
            logWarn(.citation, "No spouse as_child family found in network")
        }
        
        let duration = DebugLogger.shared.endTimer("spouse_citation")
        let fallbackCitation = "Citation for \(spouseName) not found in available records. Additional research needed for spouse's parents' family."
        logInfo(.citation, "Returning fallback citation for spouse")
        return fallbackCitation
    }
    
    // MARK: - Hiski Query Generation
    
    /**
     * Generate Hiski query URL for a specific event
     */
    func generateHiskiQuery(for date: String, eventType: EventType, person: Person? = nil) -> String {
        logInfo(.citation, "🔍 Generating Hiski query for: \(date) (\(eventType))")
        
        // For now, return mock URLs - real implementation would integrate with hiski.genealogia.fi
        let cleanDate = date.replacingOccurrences(of: " ", with: "_")
        let personParam = person?.name.replacingOccurrences(of: " ", with: "_") ?? "unknown"
        
        let url = "https://hiski.genealogia.fi/hiski?en+mock_query_\(eventType)_\(personParam)_\(cleanDate)"
        
        logDebug(.citation, "Generated Hiski URL: \(url)")
        return url
    }
    
    // MARK: - Helper Methods
    
    private func extractGivenName(from fullName: String) -> String {
        return fullName.components(separatedBy: " ").first ?? fullName
    }
    
    // MARK: - Statistics and Monitoring
    
    /**
     * Get resolution statistics
     */
    func getResolutionStatistics() -> ResolutionStatistics {
        let stats = familyResolver.getResolutionStatistics()
        logTrace(.app, "Resolution statistics requested: \(stats.totalAttempts) attempts, \(String(format: "%.1f", stats.successRate * 100))% success")
        return stats
    }
    
    /**
     * Get name equivalence report
     */
    func getNameEquivalenceReport() -> EquivalenceReport {
        let report = nameEquivalenceManager.getEquivalenceReport()
        logTrace(.app, "Name equivalence report requested: \(report.learnedCount) learned equivalences")
        return report
    }
    
    /**
     * Reset all statistics
     */
    func resetStatistics() {
        familyResolver.resetStatistics()
        logInfo(.app, "Statistics reset")
    }
    
    // MARK: - Debug and Testing
    
    /**
     * Load sample family for testing
     */
    @MainActor
    func loadSampleFamily() {
        logInfo(.app, "📋 Loading sample family (KORPI 6)")
        
        currentFamily = Family.sampleFamily()
        extractionProgress = .familyExtracted
        errorMessage = nil
        
        logDebug(.app, "Sample family loaded successfully")
    }
    
    /**
     * Load complex sample family for testing
     */
    @MainActor
    func loadComplexSampleFamily() {
        logInfo(.app, "📋 Loading complex sample family (PIENI-PORKOLA 5)")
        
        currentFamily = Family.complexSampleFamily()
        extractionProgress = .familyExtracted
        errorMessage = nil
        
        logDebug(.app, "Complex sample family loaded successfully")
    }
    
    // MARK: - Cleanup
    
    deinit {
        logInfo(.app, "JuuretApp deinitializing")
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Supporting Enums and Structures

/**
 * Extraction progress tracking with debug logging
 */
enum ExtractionProgress {
    case idle
    case extractingFamily
    case familyExtracted
    case resolvingCrossReferences
    case crossReferencesResolved
    case complete
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .extractingFamily:
            return "Extracting family..."
        case .familyExtracted:
            return "Family extracted"
        case .resolvingCrossReferences:
            return "Resolving cross-references..."
        case .crossReferencesResolved:
            return "Cross-references resolved"
        case .complete:
            return "Complete - ready for citations"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .extractingFamily, .resolvingCrossReferences:
            return true
        default:
            return false
        }
    }
}
