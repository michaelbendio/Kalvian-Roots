//
//  JuuretApp.swift - Fixed for iOS/iPadOS
//  Kalvian Roots
//
//  Main app coordinator with proper platform detection
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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
    let fileManager: RootsFileManager
    
    /// Family network cache for background processing
    let familyNetworkCache: FamilyNetworkCache
    
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
        let localFileManager = RootsFileManager()
        
        let localAIParsingService: AIParsingService
        
        // FIXED: Proper platform detection for all Apple devices
        #if os(macOS) && arch(arm64)
        // Apple Silicon Mac - use enhanced service with MLX support
        logInfo(.ai, "🧠 Initializing AI services with MLX support (Apple Silicon Mac)")
        localAIParsingService = AIParsingService()
        logInfo(.ai, "✅ Enhanced AI parsing service initialized with MLX support")
        #else
        // iOS/iPadOS/Intel Mac - use cloud services only
        let platform = Self.detectPlatform()  // Changed to Self.detectPlatform()
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

        let localFamilyNetworkCache = FamilyNetworkCache(rootsFileManager: localFileManager)

        // Assign all to self properties at the end
        self.nameEquivalenceManager = localNameEquivalenceManager
        self.fileManager = localFileManager
        self.aiParsingService = localAIParsingService
        self.familyResolver = localFamilyResolver
        self.familyNetworkCache = localFamilyNetworkCache
        
        logInfo(.app, "✅ Core services initialized with memory-efficient architecture")
        logInfo(.app, "Current AI service: \(self.currentServiceName)")
        logDebug(.app, "Available services: \(self.availableServices.joined(separator: ", "))")
        
        // Auto-load default file
        Task { @MainActor in
            logDebug(.file, "Attempting auto-load of default file")
            
            await self.fileManager.autoLoadDefaultFile()
            
            // Check if FileManager set an error
            if let fileError = self.fileManager.errorMessage {
                // FileManager encountered an error - propagate it to app level
                self.errorMessage = fileError
                logError(.app, "❌ Cannot load canonical file: \(fileError)")
                // DO NOT suggest using file menu - this is a failure condition
            } else if let fileContent = self.fileManager.currentFileContent {
                // File loaded successfully
                logInfo(.file, "✅ Auto-loaded canonical file")
                logDebug(.file, "File content length: \(fileContent.count) characters")
            } else {
                // No file and no error means something unexpected happened
                self.errorMessage = "Unexpected state: No file loaded and no error reported"
                logError(.app, "❌ Unexpected state in auto-load")
            }
        }
        
        logInfo(.app, "🎉 JuuretApp initialization complete")
        logDebug(.app, "Ready state: \(self.isReady)")

        // Load manual citations
        loadManualCitations()
    }
    
    // MARK: - Platform Detection Helper
    
    private static func detectPlatform() -> String {
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
    func switchAIService(to serviceName: String) async throws {  // Add 'throws'
        logInfo(.app, "🔄 Switching AI service to: \(serviceName)")
        try aiParsingService.switchService(to: serviceName)
        
        // Clear any error state since service changed
        if errorMessage?.contains("not configured") == true {
            errorMessage = nil
        }
    }
    
    /// Configure the current AI service with an API key
    func configureAIService(apiKey: String) async throws {
        logInfo(.ai, "🔧 Configuring \(currentServiceName) with API key")
        
        // Change this line:
        try aiParsingService.configureService(apiKey: apiKey)  // Not configureCurrentService
        
        errorMessage = nil
        logDebug(.app, "Cleared error state after successful AI configuration")
        
        logInfo(.ai, "✅ Successfully configured \(currentServiceName)")
    }
    
    func extractFamily(familyId: String) async {
        // Check if AI service is configured
        guard aiParsingService.isConfigured else {
            errorMessage = "\(aiParsingService.currentServiceName) not configured. Please add API key in settings."
            return
        }
        
        logInfo(.app, "🔍 Starting extraction for family: \(familyId)")
        
        // Reset state
        isProcessing = true
        errorMessage = nil
        currentFamily = nil
        enhancedFamily = nil
        extractionProgress = .extractingText
        
        // CHECK CACHE FIRST
        if let cached = familyNetworkCache.getCachedNetwork(familyId: familyId) {
            logInfo(.app, "⚡ Using cached network for: \(familyId)")
            
            // Use cached network and citations
            await MainActor.run {
                currentFamily = cached.network.mainFamily
                enhancedFamily = cached.network.mainFamily
                
                // Create workflow with cached network
                familyNetworkWorkflow = FamilyNetworkWorkflow(
                    nuclearFamily: cached.network.mainFamily,
                    familyResolver: familyResolver,
                    resolveCrossReferences: false  // Already resolved in cache
                )
                
                // Activate cached network and citations so UI lookups work
                familyNetworkWorkflow?.activateCachedResults(network: cached.network, citations: cached.citations)
                
                isProcessing = false
                extractionProgress = .idle
                
                // Reset next family state
                familyNetworkCache.nextFamilyReady = false
                familyNetworkCache.nextFamilyId = nil
            }
            
            logInfo(.app, "✨ Family loaded from cache: \(familyId)")
            
            // Start background processing for next family
            familyNetworkCache.startBackgroundProcessing(
                currentFamilyId: familyId,
                fileManager: fileManager,
                aiService: aiParsingService,
                familyResolver: familyResolver
            )
            
            return
        }
        
        // NOT CACHED - continue with normal extraction
        do {
            let startTime = Date()
            
            // Step 1: Extract family text from file
            guard let familyText = fileManager.extractFamilyText(familyId: familyId) else {
                throw ExtractionError.familyNotFound(familyId)
            }
            
            logDebug(.app, "📄 Extracted text for family \(familyId):\n\(familyText.prefix(200))...")
            
            // Step 2: Parse with AI
            extractionProgress = .parsingWithAI
            
            let family = try await aiParsingService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            extractionProgress = .familyExtracted
            
            // Step 3: Keep the parsed family in a temporary variable
            let parsedFamily = family

            // Step 4: Process cross-references for complete citations
            logInfo(.app, "🔄 Processing cross-references for enhanced citations...")
            
            // Create workflow for this family
            familyNetworkWorkflow = FamilyNetworkWorkflow(
                nuclearFamily: parsedFamily,
                familyResolver: familyResolver,
                resolveCrossReferences: true
            )

            // Step 5: Process the workflow to build the network and generate citations
            do {
                try await familyNetworkWorkflow?.process()
                
                // Log what we found
                if let network = familyNetworkWorkflow?.getFamilyNetwork() {
                    logInfo(.app, "✅ Family network processed successfully")
                    
                    // Store enhanced version
                    enhancedFamily = network.mainFamily
                    
                    // CACHE THE RESULT
                    let extractionTime = Date().timeIntervalSince(startTime)
                    let citations = familyNetworkWorkflow?.getActiveCitations() ?? [:]
                    familyNetworkCache.cacheNetwork(
                        network,
                        citations: citations,
                        extractionTime: extractionTime
                    )
                    
                    logInfo(.app, "💾 Cached network for future use")
                }
                
            } catch {
                // Provide detailed context about cross-reference failure without stopping the flow
                let parentRefs = parsedFamily.allParents.compactMap { $0.asChild }
                let childRefs  = parsedFamily.couples.flatMap { $0.children.compactMap { $0.asParent } }
                let filePreview = String((fileManager.currentFileContent ?? "").prefix(300))

                reportError(
                    "Cross-reference processing failed.",
                    context: [
                        "familyId": familyId,
                        "error": String(describing: error),
                        "parentAsChildRefs": parentRefs,
                        "childAsParentRefs": childRefs,
                        "fileContentPreview": filePreview
                    ]
                )
                logInfo(.app, "📝 Proceeding with available data; enhanced citations may be unavailable.")
            }
            
            // Step 6: Update the UI with the fully processed family after citations are ready
            await MainActor.run {
                currentFamily = parsedFamily
                isProcessing = false
                extractionProgress = .idle
                
                // Reset next family state
                familyNetworkCache.nextFamilyReady = false
                familyNetworkCache.nextFamilyId = nil
            }
            
            logInfo(.app, "✨ Family extraction complete with citations for: \(familyId)")
            
            // START BACKGROUND PROCESSING for next family
            familyNetworkCache.startBackgroundProcessing(
                currentFamilyId: familyId,
                fileManager: fileManager,
                aiService: aiParsingService,
                familyResolver: familyResolver
            )
            
        } catch {
            // Handle extraction/parsing errors
            logError(.app, "❌ Failed to extract family: \(error)")
            errorMessage = error.localizedDescription
            isProcessing = false
            extractionProgress = .idle
            currentFamily = nil
            enhancedFamily = nil
        }
    }

    func loadNextFamily() async {
        guard let nextId = familyNetworkCache.nextFamilyId else {
            logWarn(.app, "⚠️ No next family ready")
            return
        }
        
        logInfo(.app, "⏭️ Loading next family: \(nextId)")
        await extractFamily(familyId: nextId)
    }
    
    func clearFamilyCache() {
        logInfo(.app, "🗑️ Clearing family cache")
        familyNetworkCache.clearCache()
    }

    // MARK: - Citation Generation (ensure it uses workflow citations)

    func generateCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "📝 Generating citation for: \(person.displayName)")
        
        // Manual override wins
        if let manualCitation = getManualCitation(for: person, in: family) {
            logDebug(.citation, "Using manual citation")
            return manualCitation
        }
        
        let parent = isParent(person, in: family)
        let child  = isChild(person, in: family)
        
        // Require workflow for enhanced citations, but do NOT crash; report and continue
        guard let workflow = familyNetworkWorkflow else {
            reportError(
                "No active workflow when generating citation.",
                context: [
                    "familyId": family.familyId,
                    "person": person.displayName
                ]
            )
            if parent {
                return CitationGenerator.generateMainFamilyCitation(family: family)
            } else if child {
                return CitationGenerator.generateMainFamilyCitation(family: family, targetPerson: person)
            } else {
                return "Citation unavailable for \(person.displayName)."
            }
        }
        
        let citations = workflow.getActiveCitations()
        if citations.isEmpty {
            reportError(
                "Citations are empty when generating citation.",
                context: [
                    "familyId": family.familyId,
                    "person": person.displayName,
                    "availableKeys": previewKeys(citations)
                ]
            )
            if parent {
                return CitationGenerator.generateMainFamilyCitation(family: family)
            } else if child {
                return CitationGenerator.generateMainFamilyCitation(family: family, targetPerson: person)
            } else {
                return "Citation unavailable for \(person.displayName)."
            }
        }
        
        // Try different key variations to find the citation
        let keyVariations: [String] = [
            person.displayName,
            person.name,
            "\(person.name) \(person.patronymic ?? "")"
        ]
        
        logInfo(.citation, "🔍 Looking for citation in workflow citations...")
        logInfo(.citation, "Available keys: \(citations.keys)")
        logInfo(.citation, "Looking for: \(keyVariations)")
        
        if let foundKey = keyVariations.first(where: { citations[$0] != nil }),
           let citation = citations[foundKey] {
            logInfo(.citation, "✅ Using enhanced citation from workflow for: \(person.displayName)")
            return citation
        }
        
        // No entry found for person: decide based on role and reference validity
        if parent {
            let asChildId = person.asChild?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasValidAsChild = (asChildId != nil) && FamilyIDs.isValid(familyId: asChildId!)
            if hasValidAsChild {
                reportError(
                    "Parent has valid asChild reference but no enhanced citation was found.",
                    context: [
                        "familyId": family.familyId,
                        "person": person.displayName,
                        "asChildId": asChildId ?? "",
                        "availableKeys": previewKeys(citations)
                    ]
                )
            }
            return CitationGenerator.generateMainFamilyCitation(family: family)
        }
        
        if child {
            let asParentId = person.asParent?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasValidAsParent = (asParentId != nil) && FamilyIDs.isValid(familyId: asParentId!)
            if hasValidAsParent {
                reportError(
                    "Child has valid asParent reference but no enhanced citation was found.",
                    context: [
                        "familyId": family.familyId,
                        "person": person.displayName,
                        "asParentId": asParentId ?? "",
                        "availableKeys": previewKeys(citations)
                    ]
                )
            }
            return CitationGenerator.generateMainFamilyCitation(family: family, targetPerson: person)
        }
        
        // Unknown role in this family context
        return "Citation unavailable for \(person.displayName)."
    }
    
    /**
     * Generate citation for a spouse (children's spouses)
     * This looks up the spouse citation from the active workflow citations
     */
    func generateSpouseCitation(for spouseName: String, in family: Family) -> String {
        logInfo(.citation, "📝 Generating spouse citation for: \(spouseName)")
        
        // Prefer workflow, but do not crash; report and continue
        guard let workflow = familyNetworkWorkflow else {
            reportError(
                "No active workflow when generating spouse citation.",
                context: [
                    "spouseName": spouseName,
                    "familyId": family.familyId
                ]
            )
            return CitationGenerator.generateMainFamilyCitation(family: family)
        }
        
        let citations = workflow.getActiveCitations()
        if citations.isEmpty {
            reportError(
                "Citations are empty when generating spouse citation.",
                context: [
                    "spouseName": spouseName,
                    "familyId": family.familyId
                ]
            )
            return CitationGenerator.generateMainFamilyCitation(family: family)
        }
        
        // Try direct key variations first
        let keyVariations = [
            spouseName,
            spouseName.trimmingCharacters(in: .whitespaces),
            spouseName.replacingOccurrences(of: "  ", with: " ")
        ]
        if let foundKey = keyVariations.first(where: { citations[$0] != nil }),
           let citation = citations[foundKey] {
            logInfo(.citation, "✅ Using spouse citation from workflow for: \(spouseName)")
            return citation
        }
        
        // Attempt to resolve spouse Person from the visible family
        let possibleSpouses: [Person] =
            family.couples.flatMap { [$0.husband, $0.wife] } +
            family.couples.flatMap { $0.children }
        if let spousePerson = possibleSpouses.first(where: { $0.displayName == spouseName || $0.name == spouseName }) {
            let asChildId = spousePerson.asChild?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasValidAsChild = (asChildId != nil) && FamilyIDs.isValid(familyId: asChildId!)
            if hasValidAsChild {
                reportError(
                    "Spouse has valid asChild reference but no spouse citation was found.",
                    context: [
                        "spouse": spousePerson.displayName,
                        "asChildId": asChildId ?? "",
                        "familyId": family.familyId,
                        "availableKeys": previewKeys(citations)
                    ]
                )
            }
            return CitationGenerator.generateMainFamilyCitation(family: family)
        }
        
        // Could not resolve spouse Person – treat as no reference and continue with main family citation
        return CitationGenerator.generateMainFamilyCitation(family: family)
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

    // MARK: - Error Reporting & Utilities

    private func reportError(
        _ message: String,
        context: [String: Any] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        var payload: [String: Any] = [
            "message": message,
            "location": "\(file):\(line) in \(function)",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if !context.isEmpty {
            payload["context"] = context
        }

        let details = (try? prettyJSONString(from: payload)) ?? String(describing: payload)
        logError(.app, details)
        self.errorMessage = details
        copyToClipboard(details)
    }

    private func prettyJSONString(from dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? String(describing: dict)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    private func previewKeys<V>(_ dict: [String: V], limit: Int = 10) -> [String] {
        return Array(dict.keys)
            .map { String(describing: $0) }
            .sorted()
            .prefix(limit)
            .map { $0 }
    }

    private func isParent(_ person: Person, in family: Family) -> Bool {
        family.allParents.contains { $0.id == person.id }
    }

    private func isChild(_ person: Person, in family: Family) -> Bool {
        family.couples.flatMap { $0.children }.contains { $0.id == person.id }
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

// Force AI API key sync on launch
extension JuuretApp {
    func syncAPIKeys() {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        logInfo(.app, "🔄 Syncing API keys from iCloud")
        
        // Force a check after a short delay to ensure sync completes
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            store.synchronize()
            
            // Re-check configuration
            if aiParsingService.isConfigured {
                await MainActor.run {
                    logInfo(.app, "✅ AI service configured via iCloud sync")
                }
            }
        }
    }
}

// MARK: - Cache Management

extension JuuretApp {
    /// Delete a family from cache and immediately re-extract it
    /// Useful when citation generation code has changed
    func regenerateCachedFamily(familyId: String) async {
        logInfo(.app, "♻️ Regenerating family: \(familyId)")
        
        // Delete from cache
        familyNetworkCache.deleteCachedFamily(familyId: familyId)
        
        // Small delay to ensure UI updates
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Re-extract with updated citation logic
        await extractFamily(familyId: familyId)
        
        logInfo(.app, "✅ Regenerated family with updated citations: \(familyId)")
    }
}
