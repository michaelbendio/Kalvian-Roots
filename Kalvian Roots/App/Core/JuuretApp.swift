//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Main app coordinator with on-demand citation generation
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
 * NEW ARCHITECTURE: Citations are generated on-demand, no storage
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
    
    /// Current family network workflow
    var familyNetworkWorkflow: FamilyNetworkWorkflow?
    
    // MARK: - File Loading Coordination
    
    /// Continuation for waiting for file to load
    private var fileLoadContinuation: CheckedContinuation<Bool, Never>?
    
    // MARK: - Computed Properties
    
    /// Check if app is ready for family extraction
    var isReady: Bool {
        fileManager.isFileLoaded && aiParsingService.isConfigured
    }
    
    /// Check if we can load from cache (doesn't need file)
    var canLoadFromCache: Bool {
        familyNetworkCache.hasCachedFamilies
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
        let platform = Self.detectPlatform()
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
                
                // Resume any waiting continuation with failure
                self.fileLoadContinuation?.resume(returning: false)
                self.fileLoadContinuation = nil
            } else if let fileContent = self.fileManager.currentFileContent {
                // File loaded successfully
                logInfo(.file, "✅ Auto-loaded canonical file")
                logDebug(.file, "File content length: \(fileContent.count) characters")
                
                // Resume any waiting continuation with success
                self.fileLoadContinuation?.resume(returning: true)
                self.fileLoadContinuation = nil
            } else {
                // No file and no error means something unexpected happened
                self.errorMessage = "Unexpected state: No file loaded and no error reported"
                logError(.app, "❌ Unexpected state in auto-load")
                
                // Resume any waiting continuation with failure
                self.fileLoadContinuation?.resume(returning: false)
                self.fileLoadContinuation = nil
            }
        }
        
        logInfo(.app, "🎉 JuuretApp initialization complete")
        logDebug(.app, "Ready state: \(self.isReady)")
        
        // Load manual citations
        loadManualCitations()
    }
    
    // MARK: - File Ready Coordination
    
    /**
     * Async method to wait for file to be ready
     */
    func waitForFileReady() async -> Bool {
        // If already loaded, return immediately
        if fileManager.isFileLoaded {
            return true
        }
        
        // If there's an error, return false
        if fileManager.errorMessage != nil {
            return false
        }
        
        // Wait for file to load
        return await withCheckedContinuation { continuation in
            self.fileLoadContinuation = continuation
        }
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
            
            // iPad models with M-series chips
            let mSeriesIPads = ["iPad14,", "iPad15,", "iPad16,"]
            let hasAppleSilicon = mSeriesIPads.contains { identifier.hasPrefix($0) }
            
            return hasAppleSilicon ? "iPadOS (Apple Silicon)" : "iPadOS"
        } else {
            return "iOS"
        }
#elseif os(macOS)
#if arch(x86_64)
        return "macOS (Intel)"
#else
        return "macOS (Apple Silicon)"
#endif
#else
        return "Unknown Platform"
#endif
    }
    
    // MARK: - Family Extraction
    
    /**
     * Extract a family by ID with caching support
     */
    func extractFamily(familyId: String) async {
        // More specific error checking
        if !fileManager.isFileLoaded {
            if fileManager.errorMessage != nil {
                // File failed to load - show the actual error
                errorMessage = fileManager.errorMessage
            } else {
                // File is still loading
                errorMessage = "File is still loading. Please wait a moment and try again."
            }
            return
        }
        
        if !aiParsingService.isConfigured {
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
        
        // CHECK CACHE FIRST
        if let cached = familyNetworkCache.getCachedNetwork(familyId: familyId) {
            logInfo(.app, "⚡ Using cached network for: \(familyId)")
            
            // Use cached network - NO CITATIONS in new architecture
            await MainActor.run {
                currentFamily = cached.network.mainFamily
                enhancedFamily = cached.network.mainFamily
                
                // Create workflow with cached network
                familyNetworkWorkflow = FamilyNetworkWorkflow(
                    nuclearFamily: cached.network.mainFamily,
                    familyResolver: familyResolver,
                    resolveCrossReferences: false  // Already resolved in cache
                )
                
                // Just activate the network - no citations
                familyNetworkWorkflow?.activateCachedNetwork(cached.network)
                
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
            
            // Step 3: Keep the parsed family
            let parsedFamily = family
            
            // Step 4: Process cross-references
            logInfo(.app, "🔄 Processing cross-references for enhanced citations...")
            
            // Create workflow for this family
            familyNetworkWorkflow = FamilyNetworkWorkflow(
                nuclearFamily: family,
                familyResolver: familyResolver,
                resolveCrossReferences: true  // Process cross-references
            )
            
            // Step 5: Process the workflow
            extractionProgress = .resolvingReferences
            do {
                try await familyNetworkWorkflow?.process()
                
                // Get the enhanced family (main family with resolved references)
                if let workflow = familyNetworkWorkflow,
                   let network = workflow.getFamilyNetwork() {
                    enhancedFamily = network.mainFamily
                    
                    // Cache the network for future use
                    let extractionTime = Date().timeIntervalSince(startTime)
                    familyNetworkCache.cacheNetwork(
                        network,
                        citations: [:],  // No citations in new architecture
                        extractionTime: extractionTime
                    )
                    logInfo(.app, "💾 Cached network for future use")
                }
                
                extractionProgress = .complete
                logInfo(.app, "✅ Family network processed successfully")
                
            } catch {
                // Log cross-reference errors but continue with the family
                logError(.app, "⚠️ Cross-reference resolution failed: \(error)")
                
                // Collect some debugging info for logging
                let parentRefs = family.allParents.compactMap { $0.asChild }
                let childRefs = family.allChildren.compactMap { $0.asParent }
                
                logError(.app, """
                    Cross-reference resolution failed:
                    - Family ID: \(familyId)
                    - Parent refs: \(parentRefs.joined(separator: ", "))
                    - Child refs: \(childRefs.joined(separator: ", "))
                    - Error: \(error.localizedDescription)
                    """)
                
                logInfo(.app, "📝 Proceeding with available data")
            }
            
            // Step 6: Set the current family (even if cross-refs failed)
            currentFamily = parsedFamily
            extractionProgress = .idle
            isProcessing = false
            
            // Start background processing for next family
            familyNetworkCache.startBackgroundProcessing(
                currentFamilyId: familyId,
                fileManager: fileManager,
                aiService: aiParsingService,
                familyResolver: familyResolver
            )
            
        } catch {
            errorMessage = error.localizedDescription
            extractionProgress = .idle
            isProcessing = false
            logError(.app, "❌ Extraction failed: \(error)")
        }
    }
    
    /**
     * Load the next family from cache
     */
    func loadNextFamily() async {
        guard let nextId = familyNetworkCache.nextFamilyId else { return }
        await extractFamily(familyId: nextId)
    }
    
    // MARK: - Citation Generation (On-Demand from Network)
    
    /**
     * Generate citation for any person in the current family
     * NEW ARCHITECTURE: No citation dictionary - generate fresh from network
     */
    func generateCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "📝 Generating on-demand citation for: \(person.displayName)")
        logInfo(.citation, "  Birth date: \(person.birthDate ?? "unknown")")
        logInfo(.citation, "  In family: \(family.familyId)")
        
        // Get the network if available
        let network = familyNetworkWorkflow?.getFamilyNetwork()
        
        // Determine the person's role in this family
        let isParent = family.allParents.contains { parent in
            arePersonsEqual(parent, person)
        }
        
        let isChild = family.allChildren.contains { child in
            arePersonsEqual(child, person)
        }
        
        logInfo(.citation, "  Role: \(isParent ? "parent" : isChild ? "child" : "spouse")")
        
        // Check for manual override first
        let overrideKey = "\(family.familyId)|\(person.id)"
        if let manualCitation = manualCitations[overrideKey] {
            logInfo(.citation, "  Using manual override")
            return manualCitation
        }
        
        // Generate appropriate citation based on role
        let citation: String
        if isParent {
            // For parents, try to find their asChild family
            if let network = network,
               let asChildFamily = network.getAsChildFamily(for: person) {
                citation = CitationGenerator.generateAsChildCitation(
                    for: person,
                    in: asChildFamily,
                    network: network,
                    nameEquivalenceManager: nameEquivalenceManager
                )
            } else {
                // No asChild family, use main citation
                citation = CitationGenerator.generateMainFamilyCitation(
                    family: family,
                    targetPerson: person,
                    network: network
                )
            }
        } else if isChild {
            // For children, use main family citation with them as target
            citation = CitationGenerator.generateMainFamilyCitation(
                family: family,
                targetPerson: person,
                network: network
            )
        } else {
            // Must be a spouse - use main citation
            citation = CitationGenerator.generateMainFamilyCitation(
                family: family,
                targetPerson: person,
                network: network
            )
        }
        
        logInfo(.citation, "  Generated: \(citation)")
        return citation
    }
    
    // MARK: - Manual Citation Management
    
    func setManualCitation(for person: Person, in family: Family, citation: String) {
        let key = "\(family.familyId)|\(person.id)"
        manualCitations[key] = citation
        saveManualCitations()
        logInfo(.app, "💾 Saved manual citation for \(person.displayName) in \(family.familyId)")
    }
    
    func getManualCitation(for person: Person, in family: Family) -> String? {
        let key = "\(family.familyId)|\(person.id)"
        return manualCitations[key]
    }
    
    func clearManualCitation(for person: Person, in family: Family) {
        let key = "\(family.familyId)|\(person.id)"
        manualCitations.removeValue(forKey: key)
        saveManualCitations()
        logInfo(.app, "🗑️ Cleared manual citation for \(person.displayName) in \(family.familyId)")
    }
    
    private func loadManualCitations() {
        if let data = UserDefaults.standard.data(forKey: "ManualCitations"),
           let citations = try? JSONDecoder().decode([String: String].self, from: data) {
            manualCitations = citations
            logInfo(.app, "📚 Loaded \(citations.count) manual citations")
        }
    }
    
    private func saveManualCitations() {
        if let data = try? JSONEncoder().encode(manualCitations) {
            UserDefaults.standard.set(data, forKey: "ManualCitations")
        }
    }
    
    // MARK: - Regeneration
    
    /**
     * Delete a family from cache and re-extract it
     * Useful for regenerating with updated citations
     */
    func regenerateCachedFamily(familyId: String) async {
        logInfo(.app, "♻️ Regenerating family: \(familyId)")
        
        // Delete from cache
        familyNetworkCache.deleteCachedFamily(familyId: familyId)
        
        // Re-extract
        await extractFamily(familyId: familyId)
    }
    
    // MARK: - Spouse Citation Generation
    
    /**
     * Generate citation for a spouse (by name)
     * This is used when clicking on spouse names in the UI
     */
    func generateSpouseCitation(for spouseName: String, in family: Family) -> String {
        logInfo(.citation, "📝 Generating spouse citation for: \(spouseName)")
        
        guard let network = familyNetworkWorkflow?.getFamilyNetwork() else {
            return "Network not available for spouse citation"
        }
        
        // First try to find the spouse in spouseAsChildFamilies
        let spousePerson = Person(name: spouseName, noteMarkers: [])
        if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spousePerson) {
            logInfo(.citation, "📝 Found spouse's asChild family: \(spouseAsChildFamily.familyId)")
            return CitationGenerator.generateAsChildCitation(
                for: spousePerson,
                in: spouseAsChildFamily,
                network: network,
                nameEquivalenceManager: nameEquivalenceManager
            )
        }
        
        // If not found as spouse asChild, try finding them through the child's asParent family
        // (but this would be a secondary citation, not their primary one)
        for couple in family.couples {
            for child in couple.children {
                if child.spouse == spouseName {
                    if let childAsParentFamily = network.getAsParentFamily(for: child) {
                        logInfo(.citation, "📝 Using child's asParent family as fallback: \(childAsParentFamily.familyId)")
                        return CitationGenerator.generateMainFamilyCitation(
                            family: childAsParentFamily,
                            targetPerson: nil,
                            network: network
                        )
                    }
                }
            }
        }
        
        // Fallback
        return "No family information found for \(spouseName)"
    }
    // MARK: - Hiski Query Generation
    
    /**
     * Generate Hiski query for a person
     * Returns the query URL string
     */
    func generateHiskiQuery(for person: Person, eventType: EventType) -> String? {
        guard let query = HiskiQuery.from(person: person, eventType: eventType) else {
            return nil
        }
        return query.queryURL
    }
    
    // MARK: - Hiski Search URL Generation
    
    /**
     * Generate Hiski search URL for a person
     */
    func generateHiskiURL(for person: Person) -> URL? {
        var components = URLComponents(string: "https://hiski.genealogia.fi/hiski")
        
        var queryItems: [URLQueryItem] = []
        
        // Add name components
        let nameParts = person.name.split(separator: " ")
        if let firstName = nameParts.first {
            queryItems.append(URLQueryItem(name: "en", value: String(firstName)))
        }
        if nameParts.count > 1 {
            let lastName = nameParts.dropFirst().joined(separator: " ")
            queryItems.append(URLQueryItem(name: "sn", value: lastName))
        }
        
        // Add patronymic if available
        if let patronymic = person.patronymic {
            queryItems.append(URLQueryItem(name: "pn", value: patronymic))
        }
        
        // Add birth year if available
        if let birthDate = person.birthDate {
            let year = extractYear(from: birthDate)
            if let year = year {
                queryItems.append(URLQueryItem(name: "sy", value: year))
            }
        }
        
        // Add location (Kälviä)
        queryItems.append(URLQueryItem(name: "kr", value: "Kälviä"))
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    private func extractYear(from dateString: String) -> String? {
        // Handle various date formats
        let components = dateString.components(separatedBy: CharacterSet.decimalDigits.inverted)
        for component in components.reversed() {
            if component.count == 4 && component.hasPrefix("1") {
                return component
            }
        }
        return nil
    }
    
    // MARK: - AI Service Management
    
    /**
     * Switch to a different AI service
     */
    func switchAIService(to serviceName: String) async throws {
        try aiParsingService.switchService(to: serviceName)
        logInfo(.app, "✅ Switched to AI service: \(serviceName)")
    }
    
    /**
     * Configure the current AI service
     */
    func configureAIService(apiKey: String) async throws {
        try aiParsingService.configureService(apiKey: apiKey)
        
        // Save the API key for the current service
        let currentService = aiParsingService.currentServiceName
        UserDefaults.standard.set(apiKey, forKey: "AIService_\(currentService)_APIKey")
        
        logInfo(.app, "✅ Configured AI service: \(currentService)")
    }
    
    // MARK: - Utility Methods
    
    /**
     * Compare two persons for equality (used in citation generation)
     */
    private func arePersonsEqual(_ person1: Person, _ person2: Person) -> Bool {
        // First check ID
        if person1.id == person2.id {
            return true
        }
        
        // Then check birth date AND name
        if let birth1 = person1.birthDate, let birth2 = person2.birthDate {
            return birth1 == birth2 && person1.name.lowercased() == person2.name.lowercased()
        }
        
        // Don't match on name alone when there are multiple people with same name!
        return false
    }
    
    // MARK: - Extraction Progress States
    
    enum ExtractionProgress {
        case idle
        case extractingText
        case parsingWithAI
        case familyExtracted
        case resolvingReferences
        case extractingNuclear
        case extractingAsChild
        case extractingAsParent
        case complete
        
        var description: String {
            switch self {
            case .idle: return "Ready"
            case .extractingText: return "Extracting family text..."
            case .parsingWithAI: return "Parsing with AI..."
            case .familyExtracted: return "Family extracted"
            case .resolvingReferences: return "Resolving cross-references..."
            case .extractingNuclear: return "Extracting nuclear family..."
            case .extractingAsChild: return "Finding parent families..."
            case .extractingAsParent: return "Finding child families..."
            case .complete: return "Complete"
            }
        }
    }
    
    // MARK: - Extraction Errors
    
    enum ExtractionError: LocalizedError {
        case familyNotFound(String)
        case parsingFailed(String)
        case crossReferenceFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .familyNotFound(let id):
                return "Family '\(id)' not found in file"
            case .parsingFailed(let details):
                return "Failed to parse family: \(details)"
            case .crossReferenceFailed(let details):
                return "Cross-reference resolution failed: \(details)"
            }
        }
    }
}
