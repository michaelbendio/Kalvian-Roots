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
    var familyResolver: FamilyResolver
    
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

    // MARK: - Manual Citation Overrides
    private var manualCitations: [String: String] = [:] // key: familyId|personId
    private var familyNetworkWorkflow: FamilyNetworkWorkflow?
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
    
    // CRITICAL FIX: Update JuuretApp initialization in JuuretApp.swift
    // Replace the existing init() method with this updated version:

    // MARK: - Initialization

    init() {
        logInfo(.app, "🚀 JuuretApp initialization started")
        
        // Initialize core services locally first
        let localNameEquivalenceManager = NameEquivalenceManager()
        let localFileManager = FileManager()  // Initialize fileManager FIRST
        
        let localAIParsingService: AIParsingService
        #if os(macOS) && arch(arm64)
        // Apple Silicon Mac - use enhanced service with MLX support
        logInfo(.ai, "🧠 Initializing AI services with MLX support (Apple Silicon)")
        localAIParsingService = AIParsingService()
        logInfo(.ai, "✅ Enhanced AI parsing service initialized")
        
        logDebug(.ai, "Available services: \(localAIParsingService.availableServiceNames.joined(separator: ", "))")
        
        #else
        // Fallback for non-Apple Silicon (shouldn't happen in this app)
        logWarn(.ai, "⚠️ Non-Apple Silicon detected - using cloud services only")
        localAIParsingService = AIParsingService()
        #endif
        
        let localFamilyResolver = FamilyResolver(
            aiParsingService: localAIParsingService,
            nameEquivalenceManager: localNameEquivalenceManager,
            fileManager: localFileManager
        )
        
        // Assign all to self properties at the end
        self.nameEquivalenceManager = localNameEquivalenceManager
        self.fileManager = localFileManager
        self.aiParsingService = localAIParsingService
        self.familyResolver = localFamilyResolver
        
        logInfo(.app, "✅ Core services initialized with memory-efficient architecture")
        logInfo(.app, "Current AI service: \(self.currentServiceName)")
        logDebug(.app, "Available services: \(self.availableServices.joined(separator: ", "))")
        
        // Auto-load default file
        Task { @MainActor in
            logDebug(.file, "Attempting auto-load of default file")
            
            await self.fileManager.autoLoadDefaultFile()
            
            if let fileContent = self.fileManager.currentFileContent {
                logInfo(.file, "✅ Auto-loaded file - FamilyResolver has direct access")
                logDebug(.file, "File content length: \(fileContent.count) characters")
            } else {
                logDebug(.file, "No default file found for auto-loading")
                logInfo(.file, "💡 Use File menu to open JuuretKälviällä.txt")
            }
        }
        
        logInfo(.app, "🎉 JuuretApp initialization")
        logDebug(.app, "Ready state: \(self.isReady)")

        // Load manual citations
        loadManualCitations()
    }
    
    // MARK: - AI Service Management
    
    /**
     * Switch to a different AI service
     */
    func switchAIService(to serviceName: String) throws {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        try aiParsingService.switchService(to: serviceName)
        
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
        
        try aiParsingService.configureService(apiKey: apiKey)
        
        errorMessage = nil
        logDebug(.app, "Cleared error state after successful AI configuration")
        
        logInfo(.ai, "✅ Successfully configured \(currentServiceName)")
    }
    
    // MARK: - File Management
    
    /**
     * Load file via file picke
     */
    @MainActor
    func loadFile() async {
        logInfo(.file, "📁 User initiated file loading")
        do {
            let content = try await fileManager.openFile()
            
            // Clear any previous family data when new file loaded
            currentFamily = nil
            enhancedFamily = nil
            extractionProgress = .idle
            errorMessage = nil

            logInfo(.file, "✅ File loaded successfully with memory-efficient architecture")
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
     */
    func extractFamilyComplete(familyId: String) async throws {
        logInfo(.app, "🚀 Starting complete family extraction for: \(familyId)")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        logDebug(.parsing, "Normalized family ID: \(normalizedId)")
        
        // Validate prerequisites
        guard aiParsingService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentServiceName)")
            throw JuuretError.aiServiceNotConfigured(currentServiceName)
        }
        
        guard fileManager.isFileLoaded else {
            logError(.file, "❌ No file loaded")
            throw JuuretError.noFileLoaded
        }
        
        // Clear previous state
        await MainActor.run {
            currentFamily = nil
            enhancedFamily = nil
            familyNetworkWorkflow = nil  // FIXED: Clear previous workflow
            extractionProgress = .extractingFamily
            errorMessage = nil
            isProcessing = true
        }
        
        do {
            // Create family web workflow with ALL required dependencies
            let workflow = FamilyNetworkWorkflow(
                aiParsingService: aiParsingService,
                familyResolver: familyResolver,
                fileManager: fileManager
            )
            
            // Start the workflow
            try await workflow.processFamilyNetwork(for: normalizedId)
            
            // Update app state with results
            await MainActor.run {
                if let network = workflow.getFamilyNetwork() {
                    currentFamily = network.mainFamily
                    enhancedFamily = network.mainFamily
                    familyNetworkWorkflow = workflow  // FIXED: Store workflow instance
                    extractionProgress = .complete
                    isProcessing = false
                    
                    logInfo(.app, "✅ Complete family extraction completed: \(network.mainFamily.familyId)")
                    logInfo(.app, "📊 Resolved \(network.totalResolvedFamilies) cross-references")
                    logInfo(.app, "📄 Active citations: \(workflow.getActiveCitations().count)")
                } else {
                    extractionProgress = .idle
                    isProcessing = false
                    errorMessage = "Failed to build family network"
                    logError(.app, "❌ Family network was nil after workflow")
                }
            }
        } catch {
            await MainActor.run {
                extractionProgress = .idle
                isProcessing = false
                errorMessage = "Complete extraction failed: \(error.localizedDescription)"
            }
            
            logError(.app, "❌ Complete family extraction failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Family Text Extraction
    
    private func extractFamilyText(familyId: String, from fileContent: String) throws -> String {
        logDebug(.parsing, "🔍 Extracting text for family: \(familyId)")
        
        let lines = fileContent.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inTargetFamily = false
        var familyFound = false
        
        let normalizedTargetId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if this line starts a new family
            if let currentFamilyId = extractFamilyIdFromLine(trimmedLine) {
                let normalizedCurrentId = currentFamilyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                if normalizedCurrentId == normalizedTargetId {
                    // Found our target family
                    inTargetFamily = true
                    familyFound = true
                    familyLines.append(line)
                    logDebug(.parsing, "Found target family header: \(trimmedLine)")
                } else if inTargetFamily {
                    // Started a different family - stop collecting
                    logDebug(.parsing, "Found next family: \(currentFamilyId), stopping collection")
                    break
                } else {
                    // Not our target family, continue searching
                    inTargetFamily = false
                }
            } else if inTargetFamily {
                // We're in our target family, collect all lines
                familyLines.append(line)
                
                // Optional: Stop at empty line after substantial content
                // But only if we have children section and notes
                if trimmedLine.isEmpty && familyLines.count > 10 {
                    let content = familyLines.joined(separator: "\n")
                    if content.contains("Lapset") || content.contains("★") {
                        // Check if next non-empty line starts a new family
                        let remainingLines = Array(lines.dropFirst(index + 1))
                        for nextLine in remainingLines {
                            let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !nextTrimmed.isEmpty {
                                if extractFamilyIdFromLine(nextTrimmed) != nil {
                                    // Next non-empty line is a family - we can stop
                                    logDebug(.parsing, "Found end of family at empty line before: \(nextTrimmed)")
                                    break
                                } else {
                                    // Next line is content, keep going
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        guard familyFound else {
            logError(.parsing, "❌ Family \(familyId) not found in file")
            throw JuuretError.familyNotFound(familyId)
        }
        
        let familyText = familyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        logInfo(.parsing, "✅ Extracted family text for \(familyId) (\(familyText.count) characters)")
        logDebug(.parsing, "Family text preview: \(String(familyText.prefix(200)))...")
        
        // Additional validation
        if familyText.count < 50 {
            logWarn(.parsing, "⚠️ Extracted family text seems too short: \(familyText.count) characters")
            logWarn(.parsing, "Full extracted text: '\(familyText)'")
        }
        
        return familyText
    }

    private func extractFamilyIdFromLine(_ line: String) -> String? {
        // More robust family ID extraction
        // Pattern: FAMILY_NAME [ROMAN_NUMERALS] NUMBER[LETTER], page(s) ...
        // Examples: "KORPI 6, pages 105-106", "SIKALA II 3, page 45", "HANHISALO III 1A, page 200"
        
        let patterns = [
            // Pattern 1: FAMILY_NAME NUMBER, page(s)
            #"^([A-ZÄÖÅ-]+\s+\d+[A-Z]?)(?:,|\s)"#,
            // Pattern 2: FAMILY_NAME ROMAN NUMBER, page(s)
            #"^([A-ZÄÖÅ-]+\s+(?:II|III|IV|V|VI)\s+\d+[A-Z]?)(?:,|\s)"#,
            // Pattern 3: Just the family name and number (more permissive)
            #"^([A-ZÄÖÅ-]+(?:\s+(?:II|III|IV|V|VI))?\s+\d+[A-Z]?)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                let familyId = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                logTrace(.parsing, "Extracted family ID: '\(familyId)' from line: '\(line)'")
                return familyId
            }
        }
        
        return nil
    }
    
    // MARK: - Citation Generation
    
    /**
     * Generate citation for person
     */
    func generateCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "📖 Generating citation for: \(person.name)")

        // Manual override first
        if let override = getManualCitation(for: person, in: family) {
            logDebug(.citation, "Using manual citation override")
            return override
        }

        // FIXED: Check for enhanced citations from workflow
        if let workflow = familyNetworkWorkflow {
            let activeCitations = workflow.getActiveCitations()
            
            // Try to get person-specific citation by name
            if let enhancedCitation = activeCitations[person.name] {
                logDebug(.citation, "Using enhanced citation from workflow for: \(person.name)")
                return enhancedCitation
            }
            
            // If no person-specific citation, try family-level citation
            if let familyCitation = activeCitations[family.familyId] {
                logDebug(.citation, "Using enhanced family citation from workflow for: \(family.familyId)")
                return familyCitation
            }
            
            logDebug(.citation, "No enhanced citation found in workflow, falling back to standard")
        } else {
            logDebug(.citation, "No workflow available, using standard citation generation")
        }

        // Fallback to standard citation generation
        let citation = CitationGenerator.generateMainFamilyCitation(family: family)
        logDebug(.citation, "Generated standard citation length: \(citation.count) characters")
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
    @available(*, deprecated, message: "Use generateHiskiQuery(for:person,eventType:) instead")
    func generateHiskiQuery(for date: String, eventType: EventType) -> String {
        let cleanDate = date.replacingOccurrences(of: ".", with: "")
        return "https://hiski.genealogia.fi/hiski?en+query_\(eventType.rawValue)_\(cleanDate)"
    }

    func generateHiskiQuery(for person: Person, eventType: EventType) -> String? {
        logInfo(.citation, "🔗 Generating Hiski URL for person: \(person.displayName), event: \(eventType)")
        guard let query = HiskiQuery.from(person: person, eventType: eventType) else {
            logWarn(.citation, "No suitable data to build Hiski query for \(eventType)")
            return nil
        }
        let url = query.queryURL
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
        self.enhancedFamily = network.mainFamily
    }

    // MARK: - Manual Citation Persistence
    private func manualCitationKey(familyId: String, personId: String) -> String { "\(familyId)|\(personId)" }

    private func loadManualCitations() {
        if let data = UserDefaults.standard.data(forKey: "ManualCitations"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            manualCitations = dict
            logDebug(.citation, "Loaded \(manualCitations.count) manual citations")
        }
    }

    private func saveManualCitations() {
        if let data = try? JSONEncoder().encode(manualCitations) {
            UserDefaults.standard.set(data, forKey: "ManualCitations")
        }
    }

    func setManualCitation(_ citation: String, for person: Person, in family: Family) {
        let key = manualCitationKey(familyId: family.familyId, personId: person.id)
        manualCitations[key] = citation
        saveManualCitations()
        logInfo(.citation, "Saved manual citation for \(person.displayName) in \(family.familyId)")
    }

    func getManualCitation(for person: Person, in family: Family) -> String? {
        manualCitations[manualCitationKey(familyId: family.familyId, personId: person.id)]
    }
}

