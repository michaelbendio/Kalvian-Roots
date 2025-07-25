//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Updated with comprehensive debug logging and DeepSeek focus
//

import Foundation
import SwiftUI

/**
 * JuuretApp.swift - Main application coordinator with comprehensive debugging
 *
 * Updated to use DeepSeek as primary AI service with detailed logging throughout
 * the family extraction and cross-reference resolution workflow.
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
    var isResolvingCrossReferences = false
    
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
        self.aiParsingService = AIParsingService()
        self.familyResolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager
        )
        self.fileManager = FileManager()
        
        logInfo(.app, "✅ Core services initialized")
        logInfo(.app, "Current AI service: \(currentServiceName)")
        logDebug(.app, "Services available: \(availableServices.joined(separator: ", "))")
        
        // Switch to DeepSeek as primary service
        Task { @MainActor in
            do {
                try aiParsingService.switchToService(named: "DeepSeek")
                logInfo(.ai, "✅ Switched to DeepSeek as primary AI service")
            } catch {
                logError(.ai, "❌ Failed to switch to DeepSeek: \(error)")
            }
        }
        
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
    
    // MARK: - Family Extraction (Phase 1)
    
    /**
     * Extract family using AI parsing service
     */
    func extractFamily(familyId: String) async throws {
        logInfo(.app, "🔍 Starting family extraction for: \(familyId)")
        DebugLogger.shared.startTimer("family_extraction")
        
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
                let duration = DebugLogger.shared.endTimer("family_extraction")
                logInfo(.app, "Family extraction completed in \(String(format: "%.2f", duration))s")
            }
        }
        
        do {
            // Extract family text from file
            logDebug(.file, "Extracting family text for: \(normalizedId)")
            guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
                logError(.file, "❌ Family text not found in file for: \(normalizedId)")
                throw JuuretError.extractionFailed("Family text not found in file")
            }
            
            logInfo(.file, "✅ Extracted family text (\(familyText.count) characters)")
            logTrace(.file, "Family text preview: \(String(familyText.prefix(200)))...")
            
            // Parse with AI service
            logInfo(.ai, "🤖 Starting AI parsing with \(currentServiceName)")
            let family = try await aiParsingService.parseFamily(
                familyId: normalizedId,
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
            
            logInfo(.app, "✅ Family extraction successful: \(family.familyId)")
            logDebug(.parsing, "Father: \(family.father.displayName)")
            logDebug(.parsing, "Mother: \(family.mother?.displayName ?? "nil")")
            logDebug(.parsing, "Children: \(family.children.count)")
            logDebug(.parsing, "Cross-references needed: \(family.totalCrossReferencesNeeded)")
            
            DebugLogger.shared.logParsingSuccess(family)
            
        } catch {
            logError(.app, "❌ Family extraction failed: \(error)")
            DebugLogger.shared.logParsingFailure(error, familyId: normalizedId)
            
            await MainActor.run {
                self.errorMessage = "Failed to extract family: \(error.localizedDescription)"
            }
            throw error
        }
    }
    
    // MARK: - Cross-Reference Resolution (Phase 2)
    
    /**
     * Resolve cross-references for current family
     */
    func resolveCrossReferences() async throws {
        guard let family = currentFamily else {
            logError(.crossRef, "❌ No current family for cross-reference resolution")
            throw JuuretError.noCurrentFamily
        }
        
        logInfo(.crossRef, "🔗 Starting cross-reference resolution for: \(family.familyId)")
        DebugLogger.shared.startTimer("cross_reference_resolution")
        
        await MainActor.run {
            isResolvingCrossReferences = true
            extractionProgress = .resolvingCrossReferences
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isResolvingCrossReferences = false
                extractionProgress = .idle
                let duration = DebugLogger.shared.endTimer("cross_reference_resolution")
                logInfo(.crossRef, "Cross-reference resolution completed in \(String(format: "%.2f", duration))s")
            }
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
    
    /**
     * Complete extraction with cross-references (combined workflow)
     */
    func extractFamilyComplete(familyId: String) async throws {
        logInfo(.app, "🎯 Starting complete family extraction workflow for: \(familyId)")
        DebugLogger.shared.startTimer("complete_extraction")
        
        defer {
            let duration = DebugLogger.shared.endTimer("complete_extraction")
            logInfo(.app, "Complete extraction workflow finished in \(String(format: "%.2f", duration))s")
        }
        
        // Step 1: Extract basic family
        logInfo(.app, "Step 1: Basic family extraction")
        try await extractFamily(familyId: familyId)
        
        // Step 2: Resolve cross-references
        logInfo(.app, "Step 2: Cross-reference resolution")
        try await resolveCrossReferences()
        
        logInfo(.app, "✅ Complete family extraction workflow successful")
    }
    
    // MARK: - Citation Generation (Enhanced)
    
    /**
     * Generate citation for person using enhanced data
     */
    func generateCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "📄 Generating citation for: \(person.displayName)")
        DebugLogger.shared.startTimer("citation_generation")
        
        // Use enhanced family if available
        let targetFamily = enhancedFamily ?? family
        logDebug(.citation, "Using \(enhancedFamily != nil ? "enhanced" : "basic") family data")
        
        // Check for as_child family citation
        if let asChildRef = person.asChildReference,
           let network = familyNetwork,
           let asChildFamily = network.getAsChildFamily(for: person) {
            
            logDebug(.citation, "Generating as_child citation from family: \(asChildFamily.familyId)")
            let citation = CitationGenerator.generateAsChildCitation(for: person, in: asChildFamily)
            let duration = DebugLogger.shared.endTimer("citation_generation")
            logInfo(.citation, "✅ As_child citation generated (\(citation.count) chars) in \(String(format: "%.3f", duration))s")
            return citation
        }
        
        // Generate main family citation with enhanced data
        logDebug(.citation, "Generating main family citation")
        let citation = generateEnhancedMainFamilyCitation(family: targetFamily)
        let duration = DebugLogger.shared.endTimer("citation_generation")
        logInfo(.citation, "✅ Main family citation generated (\(citation.count) chars) in \(String(format: "%.3f", duration))s")
        return citation
    }
    
    /**
     * Generate spouse citation using cross-reference data
     */
    func generateSpouseCitation(spouseName: String, in family: Family) -> String {
        logInfo(.citation, "💑 Generating spouse citation for: \(spouseName)")
        
        // Check family network for spouse's as_child family
        if let network = familyNetwork,
           let spouseFamily = network.getSpouseAsChildFamily(for: spouseName) {
            
            logDebug(.citation, "Found spouse as_child family: \(spouseFamily.familyId)")
            
            // Find the spouse in their as_child family
            if let spouse = spouseFamily.findChild(named: extractGivenName(from: spouseName)) {
                logDebug(.citation, "Found spouse as child in family, generating citation")
                return CitationGenerator.generateAsChildCitation(for: spouse, in: spouseFamily)
            } else {
                logWarn(.citation, "Spouse not found as child in resolved family")
            }
        } else {
            logWarn(.citation, "No spouse as_child family found in network")
        }
        
        let fallbackCitation = "Citation for \(spouseName) not found in available records. Additional research needed."
        logInfo(.citation, "Returning fallback citation for spouse")
        return fallbackCitation
    }
    
    /**
     * Enhanced main family citation with cross-reference data
     */
    private func generateEnhancedMainFamilyCitation(family: Family) -> String {
        logTrace(.citation, "Building enhanced main family citation")
        
        var citation = "Information on \(family.pageReferenceString) includes:\n\n"
        
        // Father information
        citation += formatPersonForCitation(family.father)
        
        // Mother information
        if let mother = family.mother {
            citation += formatPersonForCitation(mother)
        }
        
        // Marriage date
        if let marriageDate = family.primaryMarriageDate {
            citation += "m \(normalizeDate(marriageDate))\n"
        }
        
        // Additional spouses
        if !family.additionalSpouses.isEmpty {
            citation += "\nAdditional spouse(s):\n"
            for spouse in family.additionalSpouses {
                citation += formatPersonForCitation(spouse)
            }
        }
        
        // Children
        if !family.children.isEmpty {
            citation += "\nChildren:\n"
            for child in family.children {
                citation += formatChildForCitation(child)
            }
        }
        
        // Enhanced information from cross-references
        if let network = familyNetwork {
            let additionalInfo = generateAdditionalInformation(from: network)
            if !additionalInfo.isEmpty {
                citation += "\n\(additionalInfo)"
                logDebug(.citation, "Added additional information from cross-references")
            }
        }
        
        // Notes
        if !family.notes.isEmpty {
            citation += "\nNotes:\n"
            for note in family.notes {
                citation += "• \(note)\n"
            }
        }
        
        // Child mortality
        if let childrenDied = family.childrenDiedInfancy, childrenDied > 0 {
            citation += "\nChildren died in infancy: \(childrenDied)\n"
        }
        
        logTrace(.citation, "Enhanced citation build complete (\(citation.count) characters)")
        return citation
    }
    
    /**
     * Generate additional information section from cross-references
     */
    private func generateAdditionalInformation(from network: FamilyNetwork) -> String {
        var additionalInfo: [String] = []
        
        logTrace(.citation, "Generating additional information from \(network.totalResolvedFamilies) resolved families")
        
        // Check for enhanced death dates
        for child in network.mainFamily.children {
            if let asParentFamily = network.getAsParentFamily(for: child),
               child.enhancedDeathDate != nil && child.deathDate == nil {
                let pages = asParentFamily.pageReferenceString
                additionalInfo.append("\(child.name)'s death date: \(pages)")
                logTrace(.citation, "Added death date info for \(child.name)")
            }
        }
        
        // Check for enhanced marriage dates
        for child in network.mainFamily.children {
            if let asParentFamily = network.getAsParentFamily(for: child),
               child.enhancedMarriageDate != nil && child.marriageDate != child.enhancedMarriageDate {
                let pages = asParentFamily.pageReferenceString
                additionalInfo.append("\(child.name)'s marriage date: \(pages)")
                logTrace(.citation, "Added marriage date info for \(child.name)")
            }
        }
        
        if additionalInfo.isEmpty {
            logTrace(.citation, "No additional information found from cross-references")
            return ""
        }
        
        logDebug(.citation, "Generated \(additionalInfo.count) additional information items")
        return "Additional information found elsewhere:\n" + additionalInfo.map { "• \($0)" }.joined(separator: "\n")
    }
    
    // MARK: - Citation Formatting Helpers
    
    private func formatPersonForCitation(_ person: Person) -> String {
        var line = person.displayName
        
        if let birthDate = person.birthDate {
            line += ", b \(normalizeDate(birthDate))"
        }
        
        if let deathDate = person.bestDeathDate {
            line += ", d \(normalizeDate(deathDate))"
        }
        
        line += "\n"
        return line
    }
    
    private func formatChildForCitation(_ child: Person) -> String {
        var line = child.name
        
        if let birthDate = child.birthDate {
            line += ", b \(normalizeDate(birthDate))"
        }
        
        if let marriageDate = child.bestMarriageDate, let spouse = child.spouse {
            line += ", m \(spouse) \(normalizeDate(marriageDate))"
        }
        
        if let deathDate = child.bestDeathDate {
            line += ", d \(normalizeDate(deathDate))"
        }
        
        line += "\n"
        return line
    }
    
    private func normalizeDate(_ date: String) -> String {
        return DateFormatter.formatGenealogyDate(date) ?? date
    }
    
    private func extractGivenName(from fullName: String) -> String {
        return fullName.components(separatedBy: " ").first ?? fullName
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
            return "Complete"
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
