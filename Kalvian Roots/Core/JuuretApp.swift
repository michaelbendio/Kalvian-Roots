//
//  JuuretApp.swift
//  Kalvian Roots
//
//

import Foundation

/**
 * JuuretApp.swift - Main application coordinator for genealogical research
 *
 * Single-user application for Michael's Finnish genealogy research.
 * Coordinates AI parsing, file management, and family resolution.
 */

@Observable
class JuuretApp {
    
    // MARK: - Core Services
    
    let aiParsingService: AIParsingService
    let familyResolver: FamilyResolver
    let fileManager: FileManager
    let nameEquivalenceManager = NameEquivalenceManager()
    
    // MARK: - Application State
    
    private(set) var currentFamily: Family?
    private(set) var enhancedFamily: FamilyNetwork?
    private(set) var extractionProgress: ExtractionProgress = .idle
    private(set) var errorMessage: String?
    
    // MARK: - Computed Properties
    
    var isReady: Bool {
        fileManager.isFileLoaded && aiParsingService.isConfigured
    }
    
    var isProcessing: Bool {
        extractionProgress != .idle
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
        logDebug(.app, "Platform: Apple Silicon Mac (Michael's genealogy research)")
        
        // Initialize AI parsing service (handles its own platform detection)
        self.aiParsingService = AIParsingService()
        
        // Initialize dependent services
        self.familyResolver = FamilyResolver(
            aiParsingService: aiParsingService,
            nameEquivalenceManager: nameEquivalenceManager
        )
        self.fileManager = FileManager()
        
        logInfo(.app, "✅ Core services initialized")
        logInfo(.app, "Current AI service: \(currentServiceName)")
        logDebug(.app, "Available services: \(availableServices.joined(separator: ", "))")
        
        // Auto-load default file
        Task { @MainActor in
            logDebug(.file, "Attempting auto-load of default file")
            
            await fileManager.autoLoadDefaultFile()
            
            if let fileContent = fileManager.currentFileContent {
                familyResolver.setFileContent(fileContent)
                logInfo(.file, "✅ Auto-loaded file and updated FamilyResolver")
                logDebug(.file, "File content length: \(fileContent.count) characters")
            } else {
                logDebug(.file, "No default file found for auto-loading")
                logInfo(.file, "💡 Use File menu to open JuuretKälviällä.txt")
            }
        }
        
        logInfo(.app, "🎉 JuuretApp initialization complete")
        logDebug(.app, "Ready state: \(isReady)")
    }
    
    // MARK: - AI Service Management (Fixed Method Signatures)
    
    /**
     * Switch to a different AI service
     */
    func switchAIService(to serviceName: String) async {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        do {
            try await aiParsingService.switchToService(named: serviceName)
            // Clear any error state since service changed
            if errorMessage?.contains("not configured") == true {
                errorMessage = nil
                logDebug(.app, "Cleared configuration error after service switch")
            }
        } catch {
            logError(.ai, "❌ Failed to switch AI service: \(error)")
            errorMessage = "Failed to switch AI service: \(error.localizedDescription)"
        }
        
        logInfo(.ai, "✅ AI service switch completed")
    }
    
    /**
     * Configure current AI service with API key
     */
    func configureAIService(apiKey: String) async throws {
        logInfo(.ai, "🔧 Configuring \(currentServiceName) with API key")
        
        try await aiParsingService.configureCurrentService(apiKey: apiKey)
        
        errorMessage = nil
        logDebug(.app, "Cleared error state after successful AI configuration")
        
        logInfo(.ai, "✅ Successfully configured \(currentServiceName)")
    }
    
    // MARK: - File Management
    
    /**
     * Load file via file picker
     */
    @MainActor
    func loadFile() async {
        logInfo(.file, "📁 User initiated file loading")
        do {
            let content = try await fileManager.openFile()
            familyResolver.setFileContent(content)

            // Clear any previous family data when new file loaded
            currentFamily = nil
            enhancedFamily = nil
            extractionProgress = .idle
            errorMessage = nil

            logInfo(.file, "✅ File loaded successfully")
            logDebug(.file, "File content length: \(content.count) characters")
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
            logError(.file, "❌ Failed to load file: \(error)")
        }
    }
    
    // MARK: - Basic Family Processing
    
    /**
     * Extract family using AI parsing
     */
    func extractFamily(familyId: String) async throws {
        logInfo(.app, "🚀 Starting family extraction for: \(familyId)")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        logDebug(.parsing, "Normalized family ID: \(normalizedId)")
        
        guard aiParsingService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentServiceName)")
            throw JuuretError.aiServiceNotConfigured(currentServiceName)
        }
        
        guard let fileContent = fileManager.currentFileContent else {
            logError(.file, "❌ No file content available")
            throw JuuretError.noFileLoaded
        }
        
        // Update state
        extractionProgress = .extractingFamily
        errorMessage = nil
        currentFamily = nil
        enhancedFamily = nil
        
        do {
            // Extract family text
            guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
                throw JuuretError.familyNotFound(normalizedId)
            }
            
            logDebug(.parsing, "Family text extracted (\(familyText.count) characters)")
            
            // Parse family with AI
            extractionProgress = .familyExtracted
            let family = try await aiParsingService.parseFamily(familyId: normalizedId, familyText: familyText)
            
            // Update state with successful result
            currentFamily = family
            extractionProgress = .complete
            
            logInfo(.app, "✅ Family extraction completed: \(family.familyId)")
            logDebug(.app, "Family contains: \(family.children.count) children, \(family.additionalSpouses.count) additional spouses")
            
        } catch {
            extractionProgress = .idle
            errorMessage = "Family extraction failed: \(error.localizedDescription)"
            logError(.app, "❌ Family extraction failed: \(error)")
            throw error
        }
    }
    
    /**
     * Extract family with complete cross-reference resolution
     */
    func extractFamilyComplete(familyId: String) async throws {
        logInfo(.app, "🚀 Starting complete family extraction for: \(familyId)")
        
        // First extract the basic family
        try await extractFamily(familyId: familyId)
        
        guard let family = currentFamily else {
            throw JuuretError.noCurrentFamily
        }
        
        // Then resolve cross-references
        extractionProgress = .resolvingCrossReferences
        
        do {
            let network = try await familyResolver.resolveCrossReferences(for: family)
            
            enhancedFamily = network
            extractionProgress = .complete
            
            logInfo(.app, "✅ Complete family extraction finished")
            logInfo(.app, "Network contains: \(network.totalResolvedFamilies) cross-referenced families")
            
        } catch {
            extractionProgress = .complete // Keep the basic family even if cross-references fail
            logWarn(.app, "⚠️ Cross-reference resolution failed: \(error)")
            // Don't throw - partial success is still useful
        }
    }
    
    // MARK: - Citation Generation
    
    /**
     * Generate citation for current family
     */
    func generateCitation() -> String? {
        guard let family = currentFamily else {
            logWarn(.citation, "⚠️ No current family for citation generation")
            return nil
        }
        
        logInfo(.citation, "📝 Generating citation for family: \(family.familyId)")
        
        // Use enhanced family if available, otherwise basic family
        let citationFamily = enhancedFamily?.mainFamily ?? family
        
        let citation = CitationGenerator.generateMainFamilyCitation(family: family)
        
        logInfo(.citation, "✅ Citation generated (\(citation.count) characters)")
        logTrace(.citation, "Citation preview: \(String(citation.prefix(100)))...")
        
        return citation
    }
    
    /**
     * Generate citation for specific person in family context
     */
    func generatePersonCitation(for person: Person) -> String? {
        guard let family = currentFamily else {
            logWarn(.citation, "⚠️ No current family for person citation")
            return nil
        }
        
        logInfo(.citation, "📝 Generating person citation for: \(person.displayName)")
        
        // Find the appropriate family context for this person
        let contextFamily = findAppropriateFamily(for: person)
        
        let citation = CitationGenerator.generateAsChildCitation(for: person, in: contextFamily)
        
        logInfo(.citation, "✅ Person citation generated")
        return citation
    }
    
    private func findAppropriateFamily(for person: Person) -> Family {
        // If we have an enhanced family network, try to find the best context
        if let network = enhancedFamily {
            // Logic to determine which family provides the best context for this person
            // For now, return the main family
            return network.mainFamily
        }
        
        return currentFamily!
    }
    
    // MARK: - State Management
    
    /**
     * Clear current family and reset state
     */
    func clearCurrentFamily() {
        logInfo(.app, "🧹 Clearing current family state")
        
        currentFamily = nil
        enhancedFamily = nil
        extractionProgress = .idle
        errorMessage = nil
        
        logDebug(.app, "Family state cleared")
    }
    
    /**
     * Check if a specific family ID is valid
     */
    func isValidFamilyId(_ familyId: String) -> Bool {
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation - could be enhanced with actual family ID list
        let pattern = #"^[A-ZÄÖÅ-]+(?:\s+[IVX]+)?\s+\d+[A-Z]?$"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(normalizedId.startIndex..<normalizedId.endIndex, in: normalizedId)
            return regex.firstMatch(in: normalizedId, options: [], range: range) != nil
        } catch {
            logWarn(.app, "⚠️ Regex validation failed: \(error)")
            return false
        }
    }
}
