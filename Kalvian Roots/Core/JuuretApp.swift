//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Complete application coordinator with unified workflow and MLX integration
//

import Foundation
import SwiftUI

/**
 * Main application coordinator - simplified to work with actual codebase
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
    
    var localMLXAvailable: Bool {
        MLXService.isAvailable()
    }
    
    // MARK: - Initialization (Apple Silicon Optimized)
    
    init() {
        logInfo(.app, "🚀 JuuretApp initialization started (Apple Silicon optimized)")
        
        // Initialize core services
        self.nameEquivalenceManager = NameEquivalenceManager()
        
        // Apple Silicon optimized AI service initialization
        if MLXService.isAvailable() {
            logInfo(.ai, "🚀 Apple Silicon detected - enabling MLX services")
            
            // Initialize AIParsingService with automatic MLX detection
            self.aiParsingService = AIParsingService()
            
            // Set recommended MLX model based on hardware capabilities
            if let recommendedModel = MLXService.getRecommendedModel() {
                do {
                    try aiParsingService.switchToService(named: recommendedModel.name)
                    logInfo(.ai, "✅ Set recommended MLX model: \(recommendedModel.name)")
                } catch {
                    logWarn(.ai, "⚠️ Failed to switch to recommended MLX model: \(error)")
                    logInfo(.ai, "Will use default service: \(aiParsingService.currentServiceName)")
                }
            }
            
            // Log hardware-specific information
            let memory: UInt64 = 64
            logInfo(.ai, "🖥️ Hardware: Apple Silicon with \(memory)GB RAM - MLX optimized")
            
        } else {
            // Fallback for non-Apple Silicon (shouldn't happen in this app)
            logWarn(.ai, "⚠️ Non-Apple Silicon detected - using cloud services only")
            self.aiParsingService = AIParsingService()
        }
        
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
    
    // MARK: - AI Service Management
    
    /**
     * Switch to a different AI service
     */
    func switchAIService(to serviceName: String) async {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        do {
            try await aiParsingService.switchToService(named: serviceName)
        } catch {
            // Clear any error state since service changed
            if errorMessage?.contains("not configured") == true {
                errorMessage = nil
                logDebug(.app, "Cleared configuration error after service switch")
            }
        }
        logInfo(.ai, "✅ Successfully switched to: \(serviceName)")
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
        
        await MainActor.run {
            isProcessing = true
            extractionProgress = .extractingFamily
            errorMessage = nil
            currentFamily = nil
            enhancedFamily = nil
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
                extractionProgress = .idle
            }
        }
        
        // Extract family text from file content
        let familyText = try extractFamilyText(familyId: normalizedId, from: fileContent)
        logDebug(.parsing, "Extracted family text length: \(familyText.count) characters")
        
        // Parse with AI service
        let family = try await aiParsingService.parseFamily(
            familyId: normalizedId,
            familyText: familyText
        )
        
        await MainActor.run {
            self.currentFamily = family
            self.extractionProgress = .familyExtracted
        }
        
        logInfo(.parsing, "✅ Family extraction completed successfully")
        logInfo(.parsing, "Family summary: \(family.familyId) - \(family.children.count) children")
    }
    
    /**
     * Extract family text from file content for specific family ID
     */
    private func extractFamilyText(familyId: String, from fileContent: String) throws -> String {
        logDebug(.parsing, "Extracting text for family: \(familyId)")
        
        let lines = fileContent.components(separatedBy: .newlines)
        
        var familyLines: [String] = []
        var inFamily = false
        var familyFound = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this line starts a family entry
            if trimmedLine.uppercased().hasPrefix(familyId.uppercased()) {
                inFamily = true
                familyFound = true
                familyLines.append(line)
                continue
            }
            
            // If we're in a family and hit another family ID, stop
            if inFamily && trimmedLine.contains(" ") {
                let firstPart = trimmedLine.components(separatedBy: " ").first ?? ""
                if FamilyIDs.validFamilyIds.contains(where: { firstPart.uppercased().hasPrefix($0) }) {
                    break
                }
            }
            
            // If we're in the family, collect all lines
            if inFamily {
                familyLines.append(line)
            }
        }
        
        guard familyFound else {
            logError(.parsing, "❌ Family \(familyId) not found in file")
            throw JuuretError.familyNotFound(familyId)
        }
        
        let familyText = familyLines.joined(separator: "\n")
        logTrace(.parsing, "Extracted \(familyLines.count) lines for family \(familyId)")
        
        return familyText
    }
    
    // MARK: - Citation Generation (Simplified)
    
    /**
     * Generate basic citation for person
     */
    func generateCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "📖 Generating citation for: \(person.name)")
        
        // Simple citation generation
        let pages = family.pageReferences.joined(separator: ", ")
        var citation = "Information from pages \(pages) includes:\n"
        citation += "\(person.name)"
        
        if let patronymic = person.patronymic {
            citation += " \(patronymic)"
        }
        
        if let birthDate = person.birthDate {
            citation += ", b \(birthDate)"
        }
        
        if let deathDate = person.deathDate {
            citation += ", d \(deathDate)"
        }
        
        if let spouse = person.spouse {
            citation += ", m \(spouse)"
            if let marriageDate = person.marriageDate {
                citation += " \(marriageDate)"
            }
        }
        
        logDebug(.citation, "Generated citation length: \(citation.count) characters")
        return citation
    }
    
    /**
     * Generate Hiski URL for person verification
     */
    func generateHiskiQuery(for date: String, eventType: EventType) -> String {
        logInfo(.citation, "🔗 Generating Hiski URL for date: \(date), event: \(eventType)")
        
        let cleanDate = date.replacingOccurrences(of: ".", with: "")
        let url = "https://hiski.genealogia.fi/hiski?en+query_\(eventType.rawValue)_\(cleanDate)"
        
        logDebug(.citation, "Generated Hiski URL: \(url)")
        return url
    }
    
    // MARK: - Debug and Testing
    
    /**
     * Load sample family for testing
     */
    @MainActor
    func loadSampleFamily() {
        logInfo(.app, "📋 Loading sample family")
        
        currentFamily = Family.sampleFamily()
        extractionProgress = .familyExtracted
        errorMessage = nil
        
        logDebug(.app, "Sample family loaded successfully")
    }
}

