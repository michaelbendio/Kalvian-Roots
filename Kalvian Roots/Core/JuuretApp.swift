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
    var errorMessage: String?
    
    /// Extraction progress tracking
    var extractionProgress: ExtractionProgress = .idle
    
    // MARK: - Computed Properties
    
    /// Check if app is ready for family extraction
    var isReady: Bool {
        fileManager.isFileLoaded && aiParsingService.isConfigured
    }
    
    /// Available AI services for switching
    var availableServices: [String] {
        aiParsingService.availableServiceNames
    }
    
    /// Current AI service name for display
    var currentServiceName: String {
        return aiParsingService.currentServiceName
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.app, "🚀 JuuretApp initialization started")
        
        // Initialize core services
        self.nameEquivalenceManager = NameEquivalenceManager()
        
        #if os(macOS) && arch(arm64)
        // Apple Silicon Mac - use enhanced service with MLX support
        logInfo(.ai, "🧠 Initializing AI services with MLX support (Apple Silicon)")
        self.aiParsingService = AIParsingService()
        logInfo(.ai, "✅ Enhanced AI parsing service initialized")
        
        logDebug(.ai, "Available services: \(aiParsingService.availableServiceNames.joined(separator: ", "))")
        
        #else
        // Fallback for non-Apple Silicon (shouldn't happen in this app)
        logWarn(.ai, "⚠️ Non-Apple Silicon detected - using cloud services only")
        self.aiParsingService = AIParsingService()
        #endif
        
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
    func switchAIService(to serviceName: String) async throws {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        try await aiParsingService.switchToService(named: serviceName)
        
        // Clear any error state since service changed
        if errorMessage?.contains("not configured") == true {
            errorMessage = nil
            logDebug(.app, "Cleared configuration error after service switch")
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
        
        // Clear previous state
        await MainActor.run {
            currentFamily = nil
            enhancedFamily = nil
            extractionProgress = .extractingFamily
            errorMessage = nil
            isProcessing = true
        }
        
        logDebug(.app, "Cleared previous state, starting extraction")
        
        do {
            // Extract family text from file
            let familyText = try extractFamilyText(familyId: normalizedId, from: fileContent)
            logDebug(.parsing, "Extracted family text (\(familyText.count) chars)")
            
            // Parse using AI service
            await MainActor.run {
                extractionProgress = .extractingFamily
            }
            
            let family = try await aiParsingService.parseFamily(
                familyId: normalizedId,
                familyText: familyText
            )
            
            // Update UI on main thread
            await MainActor.run {
                currentFamily = family
                extractionProgress = .familyExtracted
                isProcessing = false
                logInfo(.app, "✅ Family extraction completed: \(family.familyId)")
                logDebug(.parsing, "Family has \(family.children.count) children")
            }
            
        } catch {
            await MainActor.run {
                extractionProgress = .idle
                isProcessing = false
                errorMessage = "Extraction failed: \(error.localizedDescription)"
            }
            
            logError(.app, "❌ Family extraction failed: \(error)")
            throw error
        }
    }
    
    /**
     * Extract family with complete cross-references (future implementation)
     * For now, delegates to basic extractFamily method
     */
    func extractFamilyComplete(familyId: String) async throws {
        logInfo(.app, "🚀 Starting complete family extraction for: \(familyId)")
        logInfo(.app, "Note: Complete extraction with cross-references not yet implemented")
        
        // For now, just do basic extraction
        try await extractFamily(familyId: familyId)
        
        logDebug(.app, "Complete extraction delegated to basic extraction")
    }
    
    // MARK: - Family Text Extraction
    
    private func extractFamilyText(familyId: String, from fileContent: String) throws -> String {
        logDebug(.parsing, "🔍 Extracting text for family: \(familyId)")
        
        let lines = fileContent.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inFamily = false
        var familyFound = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this line starts a family
            if !trimmedLine.isEmpty {
                let firstPart = trimmedLine.components(separatedBy: " ").first ?? ""
                if FamilyIDs.validFamilyIds.contains(where: { firstPart.uppercased().hasPrefix($0) }) {
                    // Found a family line
                    if firstPart.uppercased().hasPrefix(familyId) {
                        // This is our target family
                        inFamily = true
                        familyFound = true
                        familyLines.append(line)
                        continue
                    } else if inFamily {
                        // Found a different family, stop collecting
                        break
                    }
                }
            }
            
            // Check for end of family (blank line after family content)
            if inFamily && trimmedLine.isEmpty {
                // Blank line - check if next non-blank line is a family
                let remainingLines = lines.dropFirst(lines.firstIndex(of: line) ?? 0).dropFirst()
                for nextLine in remainingLines {
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if !nextTrimmed.isEmpty {
                        let firstPart = nextTrimmed.components(separatedBy: " ").first ?? ""
                        if FamilyIDs.validFamilyIds.contains(where: { firstPart.uppercased().hasPrefix($0) }) {
                            break
                        }
                    }
                }
                break
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
     * Generate spouse citation (placeholder implementation)
     * This will be enhanced when cross-reference resolution is implemented
     */
    func generateSpouseCitation(spouseName: String, in family: Family) -> String {
        logInfo(.citation, "📖 Generating placeholder spouse citation for: \(spouseName)")
        
        let pages = family.pageReferences.joined(separator: ", ")
        var citation = "Spouse citation for \(spouseName) in family \(family.familyId)\n"
        citation += "Information from pages \(pages)\n\n"
        citation += "This feature is being developed. The citation will include:\n"
        citation += "- \(spouseName)'s parents' family information\n"
        citation += "- Birth date and location\n"
        citation += "- Parents' names and vital dates\n"
        citation += "- Cross-referenced family data\n\n"
        citation += "Cross-reference resolution coming in Phase 2."
        
        logDebug(.citation, "Generated placeholder spouse citation length: \(citation.count) characters")
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
    
    /// Load complex sample family for cross-reference testing
    @MainActor
    func loadComplexSampleFamily() {
        logInfo(.app, "📋 Loading complex sample family")
        currentFamily = Family.complexSampleFamily()
        extractionProgress = .familyExtracted
        errorMessage = nil
        logDebug(.app, "Complex sample family loaded successfully")
    }

    /**
     * Resolve cross-references for the current family
     */
    @MainActor
    func resolveCrossReferences() async throws {
        guard let currentFamily = self.currentFamily else { return }
        let network = try await familyResolver.resolveCrossReferences(for: currentFamily)
        // Optionally update enhancedFamily or handle network as needed
        self.enhancedFamily = network.mainFamily // or whatever behavior you want
    }
}
