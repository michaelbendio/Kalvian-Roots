//
//  JuuretApp.swift - Fixed for iOS/iPadOS
//  Kalvian Roots
//
//  Main app coordinator with proper platform detection
//

import Foundation
import SwiftUI

/**
 * JuuretApp - Main application coordinator
 *
 * Central hub that owns all services and manages app state.
 * Uses @Observable for SwiftUI integration.
 */
@Observable
@MainActor
class JuuretApp {
    
    // MARK: - Core Services (Owned by App)
    
    /// AI parsing service for family extraction
    let aiParsingService: AIParsingService
    
    /// Family resolver for cross-references
    let familyResolver: FamilyResolver
    
    /// Name equivalence manager
    let nameEquivalenceManager: NameEquivalenceManager
    
    /// File manager for I/O operations
    let fileManager: FileManager
    
    // MARK: - App State
    
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
    
    init() {
        logInfo(.app, "🚀 JuuretApp initialization started")
        
        // Initialize core services locally first
        let localNameEquivalenceManager = NameEquivalenceManager()
        let localFileManager = FileManager()
        
        let localAIParsingService: AIParsingService
        
        // FIXED: Proper platform detection for all Apple devices
        #if os(macOS) && arch(arm64)
        // Apple Silicon Mac - use enhanced service with MLX support
        logInfo(.ai, "🧠 Initializing AI services with MLX support (Apple Silicon Mac)")
        localAIParsingService = AIParsingService()
        logInfo(.ai, "✅ Enhanced AI parsing service initialized with MLX support")
        #else
        // iOS/iPadOS/Intel Mac - use cloud services only
        let platform = detectPlatform()
        logInfo(.ai, "🧠 Initializing AI services for \(platform)")
        localAIParsingService = AIParsingService()
        logInfo(.ai, "✅ AI parsing service initialized (cloud services only)")
        #endif
        
        logDebug(.ai, "Available services: \(localAIParsingService.availableServiceNames.joined(separator: ", "))")
        
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
        
        logInfo(.app, "🎉 JuuretApp initialization complete")
        logDebug(.app, "Ready state: \(self.isReady)")

        // Load manual citations
        loadManualCitations()
    }
    
    // MARK: - Platform Detection Helper
    
    private func detectPlatform() -> String {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Check if it's an Apple Silicon iPad
            var systemInfo = utsname()
            uname(&systemInfo)
            let machineMirror = Mirror(reflecting: systemInfo.machine)
            let identifier = machineMirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
            
            // iPad Pro M-series and iPad Air M-series identifiers
            if identifier.contains("iPad") &&
               (identifier.contains("13,") || // iPad Pro M1/M2
                identifier.contains("14,") || // iPad Air M1/M2
                identifier.contains("15,") || // iPad Pro M4
                identifier.contains("16,")) { // Future M-series
                return "iPad with Apple Silicon"
            } else {
                return "iPad"
            }
        } else {
            return "iPhone"
        }
        #elseif os(macOS)
        return "macOS"
        #else
        return "Unknown Platform"
        #endif
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
     * Load file via file picker
     */
    func loadFile() async throws {
        logInfo(.file, "📁 User initiated file loading")
        
        do {
            #if os(macOS)
            let content = try await fileManager.openFile()
            logInfo(.file, "✅ File loaded successfully")
            logDebug(.file, "Content length: \(content.count) characters")
            #else
            // On iOS, this is handled through the document picker in the View
            logWarn(.file, "File loading on iOS must be handled through document picker UI")
            throw FileManagerError.loadFailed("Use the document picker on iOS/iPadOS")
            #endif
            
            // Clear any previous state
            currentFamily = nil
            enhancedFamily = nil
            errorMessage = nil
            extractionProgress = .idle
            
        } catch FileManagerError.userCancelled {
            logInfo(.file, "User cancelled file selection")
            throw FileManagerError.userCancelled
        } catch {
            logError(.file, "❌ Failed to load file: \(error)")
            errorMessage = "Failed to load file: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Family Extraction
    
    /**
     * Extract family from loaded file
     */
    func extractFamily(familyId: String) async {
        guard fileManager.isFileLoaded else {
            errorMessage = "No file loaded"
            return
        }
        
        guard aiParsingService.isConfigured else {
            errorMessage = "AI service not configured. Please add API key in settings."
            return
        }
        
        logInfo(.app, "🔍 Starting extraction for family: \(familyId)")
        
        // Reset state
        isProcessing = true
        errorMessage = nil
        currentFamily = nil
        enhancedFamily = nil
        extractionProgress = .extractingText
        
        do {
            // Extract family text
            guard let familyText = fileManager.extractFamilyText(familyId: familyId) else {
                throw ExtractionError.familyNotFound(familyId)
            }
            
            extractionProgress = .parsingWithAI
            
            // Parse with AI
            let family = try await aiParsingService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            extractionProgress = .familyExtracted
            
            // Update state
            currentFamily = family
            isProcessing = false
            
            logInfo(.app, "✅ Successfully extracted family: \(familyId)")
            logDebug(.app, "Family has \(family.children.count) children")
            
        } catch {
            logError(.app, "❌ Failed to extract family: \(error)")
            errorMessage = error.localizedDescription
            isProcessing = false
            extractionProgress = .idle
        }
    }
    
    // MARK: - Citation Generation
    
    func generateCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "📝 Generating citation for: \(person.displayName)")
        
        // Check for manual citation first
        if let manualCitation = getManualCitation(for: person, in: family) {
            logDebug(.citation, "Using manual citation")
            return manualCitation
        }
        
        let citation = EnhancedCitationGenerator.generateCitation(
            for: person,
            in: family,
            fileURL: fileManager.currentFileURL
        )
        
        logDebug(.citation, "Generated citation: \(citation.prefix(100))...")
        return citation
    }
    
    func generateSpouseCitation(for spouse: Person, marriedTo person: Person, in family: Family) -> String {
        logInfo(.citation, "📝 Generating spouse citation for: \(spouse.displayName)")
        
        let citation = EnhancedCitationGenerator.generateSpouseCitation(
            for: spouse,
            marriedTo: person,
            in: family,
            fileURL: fileManager.currentFileURL
        )
        
        logDebug(.citation, "Generated spouse citation: \(citation.prefix(100))...")
        return citation
    }
    
    // MARK: - Hiski Query Generation
    
    func generateHiskiURL(for date: String, eventType: EventType) -> String {
        let cleanDate = date.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
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
    
    private func manualCitationKey(familyId: String, personId: String) -> String {
        "\(familyId)|\(personId)"
    }

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

// MARK: - Extraction Progress

enum ExtractionProgress: CustomStringConvertible {
    case idle
    case extractingText
    case parsingWithAI
    case familyExtracted
    
    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .extractingText:
            return "Extracting family text..."
        case .parsingWithAI:
            return "Parsing with AI..."
        case .familyExtracted:
            return "Family extracted"
        }
    }
}

// MARK: - Extraction Errors

enum ExtractionError: LocalizedError {
    case familyNotFound(String)
    case parsingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .familyNotFound(let familyId):
            return "Family '\(familyId)' not found in file"
        case .parsingFailed(let reason):
            return "Failed to parse family: \(reason)"
        }
    }
}
