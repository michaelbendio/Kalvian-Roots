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
        guard isReady else {
            errorMessage = aiParsingService.isConfigured ?
                "No file loaded. Please open JuuretKälviällä.roots first." :
                "AI service not configured. Please add API key in settings."
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
                nuclearFamily: parsedFamily,
                familyResolver: familyResolver,
                resolveCrossReferences: true
            )

            // Step 5: Process the workflow to build the network
            do {
                try await familyNetworkWorkflow?.process()
                
                // Log what we found
                if let network = familyNetworkWorkflow?.getFamilyNetwork() {
                    logInfo(.app, "✅ Family network processed successfully")
                    
                    // Store enhanced version
                    enhancedFamily = network.mainFamily
                    
                    // CACHE THE RESULT (no citations in new architecture)
                    let extractionTime = Date().timeIntervalSince(startTime)
                    familyNetworkCache.cacheNetwork(
                        network,
                        citations: [:],  // Empty - citations are generated on-demand
                        extractionTime: extractionTime
                    )
                    
                    logInfo(.app, "💾 Cached network for future use")
                }
                
            } catch {
                // Provide detailed context about cross-reference failure
                let parentRefs = parsedFamily.allParents.compactMap { $0.asChild }
                let childRefs = parsedFamily.couples.flatMap { $0.children.compactMap { $0.asParent } }
                
                reportError(
                    "Cross-reference processing failed.",
                    context: [
                        "familyId": familyId,
                        "error": String(describing: error),
                        "parentAsChildRefs": parentRefs,
                        "childAsParentRefs": childRefs
                    ]
                )
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
        
        logInfo(.citation, "  Role: \(isParent ? "parent" : isChild ? "child" : "unknown")")
        
        // Generate appropriate citation based on role
        if isParent {
            // Check if this parent has an asChild family in the network
            if let network = network,
               let asChildFamily = network.getAsChildFamily(for: person) {
                logInfo(.citation, "✅ Found parent's asChild family: \(asChildFamily.familyId)")
                
                // Create enhanced network with parent's nuclear family as their asParent
                var enhancedNetwork = network
                enhancedNetwork.asParentFamilies[person.displayName] = family
                enhancedNetwork.asParentFamilies[person.name] = family
                
                // Generate enhanced asChild citation
                return CitationGenerator.generateAsChildCitation(
                    for: person,
                    in: asChildFamily,
                    network: enhancedNetwork,
                    nameEquivalenceManager: nameEquivalenceManager
                )
            } else {
                logInfo(.citation, "ℹ️ No asChild family for parent - using main family citation")
                return CitationGenerator.generateMainFamilyCitation(
                    family: family,
                    targetPerson: nil,
                    network: network
                )
            }
        }
        
        if isChild {
            // For children, always use main family citation with them as target
            logInfo(.citation, "  Generating child citation with potential enhancement")
            return CitationGenerator.generateMainFamilyCitation(
                family: family,
                targetPerson: person,
                network: network
            )
        }
        
        // Unknown role - shouldn't happen but handle gracefully
        logWarn(.citation, "⚠️ Person role unclear in family context")
        return CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: nil,
            network: network
        )
    }
    
    /**
     * Helper method for backwards compatibility with string-based spouse citations
     * Used by JuuretView which only has the spouse name string
     */
    func generateSpouseCitation(for spouseName: String, in family: Family) -> String {
        logInfo(.citation, "📝 Generating spouse citation from name: \(spouseName)")
        
        // Find which child has this spouse
        var childPerson: Person? = nil
        
        // Search all children in the family for one with this spouse
        for child in family.allChildren {
            if child.spouse == spouseName {
                childPerson = child
                break
            }
        }
        
        guard let child = childPerson else {
            logWarn(.citation, "Could not find child with spouse '\(spouseName)' in family")
            return "Citation unavailable for \(spouseName)"
        }
        
        // Get the network
        guard let network = familyNetworkWorkflow?.getFamilyNetwork() else {
            logWarn(.citation, "⚠️ No network available for spouse citation")
            return "Citation unavailable for \(spouseName)"
        }
        
        // Get the child's asParent family (where the spouse appears)
        guard let asParentFamily = network.getAsParentFamily(for: child) else {
            logWarn(.citation, "⚠️ No asParent family found for child")
            return "Citation unavailable for \(spouseName)"
        }
        
        // Try to find the spouse Person object in the asParent family
        var spousePerson: Person? = nil
        for couple in asParentFamily.couples {
            if couple.husband.name == spouseName || couple.husband.displayName == spouseName {
                spousePerson = couple.husband
                break
            }
            if couple.wife.name == spouseName || couple.wife.displayName == spouseName {
                spousePerson = couple.wife
                break
            }
        }
        
        // If we couldn't find the spouse Person, create a minimal one
        if spousePerson == nil {
            spousePerson = Person(name: spouseName, noteMarkers: [])
        }
        
        // Now check if the spouse has their own asChild family
        if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spousePerson!) {
            logInfo(.citation, "✅ Found spouse's asChild family: \(spouseAsChildFamily.familyId)")
            
            // Create enhanced network with spouse's marriage family as their asParent
            var enhancedNetwork = network
            enhancedNetwork.asParentFamilies[spousePerson!.displayName] = asParentFamily
            enhancedNetwork.asParentFamilies[spousePerson!.name] = asParentFamily
            
            // Generate enhanced asChild citation for spouse
            return CitationGenerator.generateAsChildCitation(
                for: spousePerson!,
                in: spouseAsChildFamily,
                network: enhancedNetwork,
                nameEquivalenceManager: nameEquivalenceManager
            )
        } else {
            logInfo(.citation, "ℹ️ No asChild family for spouse - using marriage family citation")
            return CitationGenerator.generateMainFamilyCitation(
                family: asParentFamily,
                targetPerson: spousePerson!,
                network: network
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /**
     * Check if two Person objects represent the same person
     * Uses birth date as primary identifier, falls back to name
     */
    private func arePersonsEqual(_ person1: Person, _ person2: Person) -> Bool {
        // First try birth date (most reliable)
        if let birth1 = person1.birthDate?.trimmingCharacters(in: .whitespaces),
           let birth2 = person2.birthDate?.trimmingCharacters(in: .whitespaces),
           !birth1.isEmpty && !birth2.isEmpty {
            return birth1 == birth2
        }
        
        // Then try display name
        if person1.displayName == person2.displayName {
            return true
        }
        
        // Finally try simple name
        return person1.name.lowercased() == person2.name.lowercased()
    }
    
    // MARK: - AI Service Management (Stubbed)
    
    /**
     * Switch to a different AI service
     * TODO: Implement when needed
     */
    func switchAIService(to serviceName: String) async throws {
        logInfo(.app, "Switching AI service to: \(serviceName)")
        // Stub - implement when needed
    }
    
    /**
     * Configure the current AI service with API key
     */
    func configureAIService(apiKey: String) async throws {
        logInfo(.app, "Configuring AI service with new API key")
        try aiParsingService.configureService(apiKey: apiKey)
    }
    
    /**
     * Regenerate a cached family (force re-extraction)
     * Clears cache entry and re-extracts the family
     */
    func regenerateCachedFamily(familyId: String) async {
        logInfo(.app, "🔄 Regenerating cached family: \(familyId)")
        
        // Clear from cache
        familyNetworkCache.clearCache()
        
        // Re-extract the family
        await extractFamily(familyId: familyId)
    }
    
    // MARK: - Manual Citation Support
    
    private func loadManualCitations() {
        if let data = UserDefaults.standard.data(forKey: "ManualCitations"),
           let citations = try? JSONDecoder().decode([String: String].self, from: data) {
            manualCitations = citations
            logInfo(.app, "📚 Loaded \(citations.count) manual citations")
        }
    }
    
    func saveManualCitation(for person: Person, in family: Family, citation: String) {
        let key = "\(family.familyId)|\(person.displayName)"
        manualCitations[key] = citation
        
        if let data = try? JSONEncoder().encode(manualCitations) {
            UserDefaults.standard.set(data, forKey: "ManualCitations")
            logInfo(.app, "💾 Saved manual citation for \(person.displayName)")
        }
    }
    
    func getManualCitation(for person: Person, in family: Family) -> String? {
        let key = "\(family.familyId)|\(person.displayName)"
        return manualCitations[key]
    }
    
    // MARK: - Hiski Query Generation
    
    func generateHiskiURL(for date: String, eventType: EventType) -> String {
        let cleanDate = date.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        return "https://hiski.genealogia.fi/hiski?en+query_\(eventType.rawValue)_\(cleanDate)"
    }
    
    func generateHiskiQuery(for person: Person, eventType: EventType) -> String? {
        guard let query = HiskiQuery.from(person: person, eventType: eventType) else {
            return nil
        }
        return query.queryURL
    }
    
    // MARK: - Error Reporting
    
    private func reportError(_ message: String, context: [String: Any] = [:]) {
        logError(.app, message)
        for (key, value) in context {
            logDebug(.app, "  \(key): \(value)")
        }
    }
}

// MARK: - Enums

enum ExtractionError: LocalizedError {
    case familyNotFound(String)
    case parsingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .familyNotFound(let id):
            return "Family \(id) not found in file"
        case .parsingFailed(let reason):
            return "Failed to parse family: \(reason)"
        }
    }
}

enum ExtractionProgress {
    case idle
    case extractingText
    case parsingWithAI
    case resolvingCrossReferences
    case familyExtracted
    
    var description: String {
        switch self {
        case .idle: return "Ready"
        case .extractingText: return "Extracting family text..."
        case .parsingWithAI: return "Parsing with AI..."
        case .resolvingCrossReferences: return "Resolving cross-references..."
        case .familyExtracted: return "Family extracted"
        }
    }
}
