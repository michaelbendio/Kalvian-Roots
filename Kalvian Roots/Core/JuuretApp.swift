// MARK: - Debug and Testing//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Updated for AI parsing architecture - Phase 1 + 2 implementation
//

import Foundation
import SwiftUI

/**
 * JuuretApp.swift - Main application coordinator for AI-based genealogical parsing
 *
 * Updated from Foundation Models Framework to flexible AI service architecture.
 * Supports OpenAI, Claude, DeepSeek, and mock implementations.
 * Includes cross-reference resolution and enhanced citation generation.
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
    var fileManager: JuuretFileManager
    
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
        fileManager.isFileLoaded && aiParsingService.isConfigured
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
        // Initialize services
        self.nameEquivalenceManager = NameEquivalenceManager()
        self.aiParsingService = AIParsingService()
        self.familyResolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager
        )
        self.fileManager = JuuretFileManager()
        
        print("🚀 JuuretApp initialized with AI parsing architecture")
        print("   Current AI service: \(currentServiceName)")
        print("   Services available: \(availableServices.joined(separator: ", "))")
        
        // Auto-load default file
        Task { @MainActor in
            await self.fileManager.autoLoadDefaultFile()
            if let fileContent = fileManager.currentFileContent {
                familyResolver.setFileContent(fileContent)
            }
        }
    }
    
    // MARK: - AI Service Configuration
    
    /**
     * Switch to a different AI service
     */
    func switchAIService(to serviceName: String) async {
        do {
            try aiParsingService.switchToService(named: serviceName)
            
            await MainActor.run {
                // Clear any error state since service changed
                if errorMessage?.contains("not configured") == true {
                    errorMessage = nil
                }
            }
            
            print("✅ Switched to AI service: \(serviceName)")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to switch AI service: \(error.localizedDescription)"
            }
        }
    }
    
    /**
     * Configure current AI service with API key
     */
    func configureAIService(apiKey: String) async {
        do {
            try aiParsingService.configureCurrentService(apiKey: apiKey)
            
            await MainActor.run {
                errorMessage = nil
            }
            
            print("✅ Configured \(currentServiceName) with API key")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to configure AI service: \(error.localizedDescription)"
            }
        }
    }
    
    /**
     * Get status of all available AI services
     */
    func getAIServiceStatus() -> [(name: String, configured: Bool)] {
        return aiParsingService.getServiceStatus()
    }
    
    // MARK: - File Management Integration
    
    /**
     * Update family resolver when file content changes
     */
    @MainActor
    func updateFileContent() {
        if let fileContent = fileManager.currentFileContent {
            familyResolver.setFileContent(fileContent)
            print("📄 Updated FamilyResolver with new file content")
        }
    }
    
    // MARK: - Family Extraction (Phase 1)
    
    /**
     * Extract family using AI parsing service
     */
    func extractFamily(familyId: String) async throws {
        print("🔍 Starting family extraction: \(familyId)")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard FamilyIDs.validFamilyIds.contains(normalizedId) else {
            throw JuuretError.invalidFamilyId(familyId)
        }
        
        guard aiParsingService.isConfigured else {
            throw JuuretError.aiServiceNotConfigured(currentServiceName)
        }
        
        await MainActor.run {
            isProcessing = true
            extractionProgress = .extractingFamily
            errorMessage = nil
            currentFamily = nil
            enhancedFamily = nil
            familyNetwork = nil
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
                extractionProgress = .idle
            }
        }
        
        do {
            // Extract family text from file
            guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
                throw JuuretError.extractionFailed("Family text not found in file")
            }
            
            print("📄 Extracted family text (\(familyText.count) characters)")
            
            // Parse with AI service
            let family = try await aiParsingService.parseFamily(
                familyId: normalizedId,
                familyText: familyText
            )
            
            // Validate extracted family
            let warnings = family.validateStructure()
            if !warnings.isEmpty {
                print("⚠️ Family validation warnings:")
                for warning in warnings {
                    print("   - \(warning)")
                }
            }
            
            await MainActor.run {
                self.currentFamily = family
                self.extractionProgress = .familyExtracted
            }
            
            print("✅ Family extraction successful: \(family.familyId)")
            print("   Father: \(family.father.displayName)")
            print("   Mother: \(family.mother?.displayName ?? "nil")")
            print("   Children: \(family.children.count)")
            print("   Cross-references needed: \(family.totalCrossReferencesNeeded)")
            
        } catch {
            print("❌ Family extraction failed: \(error)")
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
            throw JuuretError.noCurrentFamily
        }
        
        print("🔗 Starting cross-reference resolution for \(family.familyId)")
        
        await MainActor.run {
            isResolvingCrossReferences = true
            extractionProgress = .resolvingCrossReferences
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isResolvingCrossReferences = false
                extractionProgress = .idle
            }
        }
        
        do {
            // Resolve all cross-references
            let network = try await familyResolver.resolveCrossReferences(for: family)
            
            // Create enhanced family with integrated data
            let enhanced = network.createEnhancedFamily()
            
            await MainActor.run {
                self.familyNetwork = network
                self.enhancedFamily = enhanced
                self.extractionProgress = .crossReferencesResolved
            }
            
            print("✅ Cross-reference resolution complete")
            print("   Resolved families: \(network.totalResolvedFamilies)")
            print("   Success rate: \(familyResolver.getResolutionStatistics().successRate)")
            
        } catch {
            print("❌ Cross-reference resolution failed: \(error)")
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
        // Step 1: Extract basic family
        try await extractFamily(familyId: familyId)
        
        // Step 2: Resolve cross-references
        try await resolveCrossReferences()
    }
    
    // MARK: - Citation Generation (Enhanced)
    
    /**
     * Generate citation for person using enhanced data
     */
    func generateCitation(for person: Person, in family: Family) -> String {
        print("📄 Generating citation for: \(person.displayName)")
        
        // Use enhanced family if available
        let targetFamily = enhancedFamily ?? family
        
        // Check for as_child family citation
        if let asChildRef = person.asChildReference,
           let network = familyNetwork,
           let asChildFamily = network.getAsChildFamily(for: person) {
            return CitationGenerator.generateAsChildCitation(for: person, in: asChildFamily)
        }
        
        // Generate main family citation with enhanced data
        return generateEnhancedMainFamilyCitation(family: targetFamily)
    }
    
    /**
     * Generate spouse citation using cross-reference data
     */
    func generateSpouseCitation(spouseName: String, in family: Family) -> String {
        print("💑 Generating spouse citation for: \(spouseName)")
        
        // Check family network for spouse's as_child family
        if let network = familyNetwork,
           let spouseFamily = network.getSpouseAsChildFamily(for: spouseName) {
            
            // Find the spouse in their as_child family
            if let spouse = spouseFamily.findChild(named: extractGivenName(from: spouseName)) {
                return CitationGenerator.generateAsChildCitation(for: spouse, in: spouseFamily)
            }
        }
        
        return "Citation for \(spouseName) not found in available records. Additional research needed."
    }
    
    /**
     * Enhanced main family citation with cross-reference data
     */
    private func generateEnhancedMainFamilyCitation(family: Family) -> String {
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
        
        return citation
    }
    
    /**
     * Generate additional information section from cross-references
     */
    private func generateAdditionalInformation(from network: FamilyNetwork) -> String {
        var additionalInfo: [String] = []
        
        // Check for enhanced death dates
        for child in network.mainFamily.children {
            if let asParentFamily = network.getAsParentFamily(for: child),
               child.enhancedDeathDate != nil && child.deathDate == nil {
                let pages = asParentFamily.pageReferenceString
                additionalInfo.append("\(child.name)'s death date: \(pages)")
            }
        }
        
        // Check for enhanced marriage dates
        for child in network.mainFamily.children {
            if let asParentFamily = network.getAsParentFamily(for: child),
               child.enhancedMarriageDate != nil && child.marriageDate != child.enhancedMarriageDate {
                let pages = asParentFamily.pageReferenceString
                additionalInfo.append("\(child.name)'s marriage date: \(pages)")
            }
        }
        
        if additionalInfo.isEmpty {
            return ""
        }
        
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
        print("🔍 Generating Hiski query for: \(date) (\(eventType))")
        
        // For now, return mock URLs - real implementation would integrate with hiski.genealogia.fi
        let cleanDate = date.replacingOccurrences(of: " ", with: "_")
        let personParam = person?.name.replacingOccurrences(of: " ", with: "_") ?? "unknown"
        
        return "https://hiski.genealogia.fi/hiski?en+mock_query_\(eventType)_\(personParam)_\(cleanDate)"
    }
    
    // MARK: - Statistics and Monitoring
    
    /**
     * Get resolution statistics
     */
    func getResolutionStatistics() -> ResolutionStatistics {
        return familyResolver.getResolutionStatistics()
    }
    
    /**
     * Get name equivalence report
     */
    func getNameEquivalenceReport() -> EquivalenceReport {
        return nameEquivalenceManager.getEquivalenceReport()
    }
    
    /**
     * Reset all statistics
     */
    func resetStatistics() {
        familyResolver.resetStatistics()
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /**
     * Extract sample family for testing
     */
    func loadSampleFamily() async {
        await MainActor.run {
            currentFamily = Family.sampleFamily()
            extractionProgress = .familyExtracted
            errorMessage = nil
        }
        
        print("📋 Loaded sample family: KORPI 6")
    }
    
    /**
     * Load complex sample family for testing
     */
    func loadComplexSampleFamily() async {
        await MainActor.run {
            currentFamily = Family.complexSampleFamily()
            extractionProgress = .familyExtracted
            errorMessage = nil
        }
        
        print("📋 Loaded complex sample family: PIENI-PORKOLA 5")
    }
}

// MARK: - Supporting Enums and Structures

/**
 * Extraction progress tracking
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
