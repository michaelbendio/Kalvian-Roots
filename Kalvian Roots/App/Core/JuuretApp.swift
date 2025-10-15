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
    
    /// Family ID being loaded (shows in nav bar during extraction)
    var pendingFamilyId: String?

    /// Enhanced family with cross-reference data
    var enhancedFamily: Family?
    
    /// Processing state
    var isProcessing = false
    
    /// Error state
    var errorMessage: String?
    
    /// Extraction progress tracking
    var extractionProgress: ExtractionProgress = .idle
    
    // MARK: - Navigation State

    /// Navigation history stack of family IDs
    var navigationHistory: [String] = []

    /// Current position in navigation history
    var historyIndex: Int = -1

    /// Home family ID (set when explicitly navigating via address bar or back/forward)
    var homeFamily: String?

    /// PDF mode toggle state
    var showPDFMode: Bool = false

    // MARK: - Navigation Methods

    /**
     * Navigate to a family, optionally adding to history
     *
     * - Parameters:
     *   - familyId: The family ID to navigate to
     *   - updateHistory: If true, adds this navigation to history and sets as home
     */
    func navigateToFamily(_ familyId: String, updateHistory: Bool) {
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Validate family ID
        guard FamilyIDs.isValid(familyId: normalizedId) else {
            logWarn(.app, "⚠️ Invalid family ID: \(familyId)")
            errorMessage = "Invalid family ID: \(familyId)"
            return
        }
        
        // If updating history, manage the history stack
        if updateHistory {
            // Remove any forward history if we're not at the end
            if historyIndex < navigationHistory.count - 1 {
                navigationHistory.removeSubrange((historyIndex + 1)...)
            }
            
            // Add to history
            navigationHistory.append(normalizedId)
            historyIndex = navigationHistory.count - 1
            
            // Set as home family
            homeFamily = normalizedId
            
            logInfo(.app, "📍 Set home family: \(normalizedId)")
        }
        
        // Extract the family
        Task {
            await extractFamily(familyId: normalizedId)
        }
    }

    /**
     * Navigate to the previous family in history
     */
    func navigateBack() {
        guard historyIndex > 0 else {
            logWarn(.app, "⚠️ Cannot navigate back - at start of history")
            return
        }
        
        historyIndex -= 1
        let familyId = navigationHistory[historyIndex]
        
        logInfo(.app, "⬅️ Navigating back to: \(familyId)")
        
        Task {
            await extractFamily(familyId: familyId)
        }
    }

    /**
     * Navigate to the next family in history
     */
    func navigateForward() {
        guard historyIndex < navigationHistory.count - 1 else {
            logWarn(.app, "⚠️ Cannot navigate forward - at end of history")
            return
        }
        
        historyIndex += 1
        let familyId = navigationHistory[historyIndex]
        
        logInfo(.app, "➡️ Navigating forward to: \(familyId)")
        
        Task {
            await extractFamily(familyId: familyId)
        }
    }

    /**
     * Navigate to the home family
     * 
     * This adds the home family to history (so back/forward work correctly)
     * but does NOT change which family is considered "home"
     */
    func navigateHome() {
        guard let home = homeFamily else {
            logWarn(.app, "⚠️ No home family set")
            errorMessage = "No home family set"
            return
        }
        
        logInfo(.app, "🏠 Navigating to home: \(home)")
        
        // Add to history but don't change home
        let normalizedId = home.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Remove any forward history if we're not at the end
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory.removeSubrange((historyIndex + 1)...)
        }
        
        // Add to history
        navigationHistory.append(normalizedId)
        historyIndex = navigationHistory.count - 1
        
        // DON'T change homeFamily - it stays the same
        // This allows you to navigate around and always come back to the same home
        
        Task {
            await extractFamily(familyId: normalizedId)
        }
    }

    /**
     * Set the current family as home
     */
    func setHomeFamily(_ familyId: String) {
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        
        guard FamilyIDs.isValid(familyId: normalizedId) else {
            logWarn(.app, "⚠️ Invalid family ID for home: \(familyId)")
            return
        }
        
        homeFamily = normalizedId
        logInfo(.app, "🏠 Home family set to: \(normalizedId)")
    }

    // MARK: - Sequential File Navigation (Previous/Next in file order)

    /**
     * Navigate to the previous family in the JuuretKälviällä.roots file
     */
    func navigateToPreviousFamily() {
        // Use pendingFamilyId if set, otherwise use currentFamily
        // This ensures arrows work based on what's shown in nav bar
        let referenceId = pendingFamilyId ?? currentFamily?.familyId
        
        guard let referenceId = referenceId else {
            logWarn(.app, "⚠️ No reference family to navigate from")
            return
        }
        
        guard let previousId = FamilyIDs.previousFamilyBefore(referenceId) else {
            logWarn(.app, "⚠️ Already at first family in file")
            errorMessage = "Already at the first family"
            return
        }
        
        logInfo(.app, "⬅️ Navigating to previous family in file: \(previousId)")
        
        // Navigate without updating history
        navigateToFamily(previousId, updateHistory: false)
    }

    /**
     * Navigate to the next family in the JuuretKälviällä.roots file
     */
    func navigateToNextFamily() {
        // Use pendingFamilyId if set, otherwise use currentFamily
        // This ensures arrows work based on what's shown in nav bar
        let referenceId = pendingFamilyId ?? currentFamily?.familyId
        
        guard let referenceId = referenceId else {
            logWarn(.app, "⚠️ No reference family to navigate from")
            return
        }
        
        guard let nextId = FamilyIDs.nextFamilyAfter(referenceId) else {
            logWarn(.app, "⚠️ Already at last family in file")
            errorMessage = "Already at the last family"
            return
        }
        
        logInfo(.app, "➡️ Navigating to next family in file: \(nextId)")
        
        // Navigate without updating history
        navigateToFamily(nextId, updateHistory: false)
    }

    // MARK: - Navigation State Helpers for Sequential Navigation

    /// Check if we can navigate to previous family in file
    var canNavigateToPreviousFamily: Bool {
        let referenceId = pendingFamilyId ?? currentFamily?.familyId
        guard let referenceId = referenceId else { return false }
        return !FamilyIDs.isFirst(referenceId)
    }

    /// Check if we can navigate to next family in file
    var canNavigateToNextFamily: Bool {
        let referenceId = pendingFamilyId ?? currentFamily?.familyId
        guard let referenceId = referenceId else { return false }
        return !FamilyIDs.isLast(referenceId)
    }
    
    // MARK: - Navigation State Helpers

    /// Check if we can navigate backward
    var canNavigateBack: Bool {
        return historyIndex > 0
    }

    /// Check if we can navigate forward
    var canNavigateForward: Bool {
        return historyIndex < navigationHistory.count - 1
    }

    /// Check if we can navigate home
    var canNavigateHome: Bool {
        return homeFamily != nil
    }

    /// Get the current family ID from history (if in history)
    var currentFamilyIdInHistory: String? {
        guard historyIndex >= 0 && historyIndex < navigationHistory.count else {
            return nil
        }
        return navigationHistory[historyIndex]
    }
    
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

        // CREATE CACHE FIRST (before resolver)
        let localFamilyNetworkCache = FamilyNetworkCache(rootsFileManager: localFileManager)

        // NOW create resolver WITH cache reference
        let localFamilyResolver = FamilyResolver(
            aiParsingService: localAIParsingService,
            nameEquivalenceManager: localNameEquivalenceManager,
            fileManager: localFileManager,
            familyNetworkCache: localFamilyNetworkCache  // NEW: pass cache!
        )

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
    
    func closeHiskiWebViews() {
        #if os(macOS)
        Task { @MainActor in
            // Access the shared manager
            HiskiWebViewManager.shared.closeAllWindows()
        }
        #endif
    }
    
    // MARK: - Hiski Query Methods

    /**
     * Process Hiski query for a person's life event
     * 
     * Queries the Hiski database for birth, death, or marriage records
     * and returns a citation URL. Opens browser windows/sheets to display results.
     */
    func processHiskiQuery(for person: Person, eventType: EventType, familyId: String, explicitDate: String? = nil) async -> String {
        let hiskiService = HiskiService(nameEquivalenceManager: nameEquivalenceManager)
        hiskiService.setCurrentFamily(familyId)
        
        do {
            let citation: HiskiCitation
            
            switch eventType {
            case .birth:
                let birthDate = explicitDate ?? person.birthDate
                guard let birthDate = birthDate else {
                    return "No birth date available for \(person.name)"
                }
                // Pass father's name to narrow search results
                citation = try await hiskiService.queryBirth(
                    name: person.name, 
                    date: birthDate,
                    fatherName: person.fatherName
                )
                
            case .death:
                let deathDate = explicitDate ?? person.deathDate
                guard let deathDate = deathDate else {
                    return "No death date available for \(person.name)"
                }
                citation = try await hiskiService.queryDeath(name: person.name, date: deathDate)
                
            case .marriage:
                let marriageDate = explicitDate ?? person.fullMarriageDate ?? person.marriageDate
                guard let marriageDate = marriageDate else {
                    return "No marriage date available for \(person.name)"
                }
                citation = try await hiskiService.queryMarriage(
                    husbandName: person.name,
                    wifeName: person.spouse ?? "",
                    date: marriageDate
                )
                
            case .baptism, .burial:
                return "Hiski queries for \(eventType.displayName) are not yet supported"
            }
            
            return citation.url
            
        } catch {
            return "Hiski query failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Family Extraction
    
    /**
     * Extract and parse a family from the file
     *
     * This is the main entry point for family extraction.
     * It handles caching, AI parsing, and cross-reference resolution.
     */
    func extractFamily(familyId: String) async {
        // Normalize the family ID
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Validate the family ID
        guard FamilyIDs.isValid(familyId: normalizedId) else {
            await MainActor.run {
                errorMessage = "Invalid family ID: \(familyId)"
                isProcessing = false
                pendingFamilyId = nil
            }
            logWarn(.app, "⚠️ Invalid family ID: \(familyId)")
            return
        }
        
        // Check if file is ready
        guard fileManager.isFileLoaded else {
            await MainActor.run {
                errorMessage = "File not loaded. Please wait for file to load or load manually."
                isProcessing = false
                pendingFamilyId = nil
            }
            logWarn(.app, "⚠️ Cannot extract - file not loaded")
            return
        }
        
        // Check if AI service is configured
        guard aiParsingService.isConfigured else {
            await MainActor.run {
                errorMessage = "AI service not configured. Please add API key in settings."
                isProcessing = false
                pendingFamilyId = nil
            }
            logWarn(.app, "⚠️ Cannot extract - AI not configured")
            return
        }
        
        logInfo(.app, "🔍 Starting extraction for family: \(normalizedId)")
        
        // Set processing state and pending family ID
        await MainActor.run {
            isProcessing = true
            errorMessage = nil
            currentFamily = nil
            enhancedFamily = nil
            extractionProgress = .extractingText
            pendingFamilyId = normalizedId  // Show this in nav bar immediately
        }
        
        // CHECK CACHE FIRST
        if let cached = familyNetworkCache.getCachedNetwork(familyId: normalizedId) {
            logInfo(.app, "⚡ Using cached network for: \(normalizedId)")
            
            // Use cached network
            await MainActor.run {
                currentFamily = cached.network.mainFamily
                enhancedFamily = cached.network.mainFamily
                
                // Create workflow with cached network
                familyNetworkWorkflow = FamilyNetworkWorkflow(
                    nuclearFamily: cached.network.mainFamily,
                    familyResolver: familyResolver,
                    resolveCrossReferences: false  // Already resolved in cache
                )
                
                // Activate the cached network
                familyNetworkWorkflow?.activateCachedNetwork(cached.network)
                
                isProcessing = false
                extractionProgress = .idle
                pendingFamilyId = nil  // Clear pending - we're done
                
                // Reset next family state
                familyNetworkCache.nextFamilyReady = false
                familyNetworkCache.nextFamilyId = nil
            }
            
            logInfo(.app, "✨ Family loaded from cache: \(normalizedId)")
            
            // Start background processing for next family
            familyNetworkCache.startBackgroundProcessing(
                currentFamilyId: normalizedId,
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
            guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
                throw ExtractionError.familyNotFound(normalizedId)
            }
            
            logDebug(.app, "📄 Extracted text for family \(normalizedId)")
            
            // Step 2: Parse with AI
            await MainActor.run {
                extractionProgress = .parsingWithAI
            }
            
            let family = try await aiParsingService.parseFamily(
                familyId: normalizedId,
                familyText: familyText
            )
            
            await MainActor.run {
                extractionProgress = .familyExtracted
            }
            
            // Step 3: Process cross-references
            logInfo(.app, "🔄 Processing cross-references for enhanced citations...")
            
            // Create workflow for this family
            await MainActor.run {
                familyNetworkWorkflow = FamilyNetworkWorkflow(
                    nuclearFamily: family,
                    familyResolver: familyResolver,
                    resolveCrossReferences: true  // Process cross-references
                )
            }
            
            // Step 4: Process the workflow
            await MainActor.run {
                extractionProgress = .resolvingReferences
            }
            
            do {
                try await familyNetworkWorkflow?.process()
                
                // Get the enhanced family
                if let workflow = familyNetworkWorkflow,
                   let network = workflow.getFamilyNetwork() {
                    
                    await MainActor.run {
                        enhancedFamily = network.mainFamily
                    }
                    
                    // Cache the network for future use
                    let extractionTime = Date().timeIntervalSince(startTime)
                    familyNetworkCache.cacheNetwork(
                        network,
                        citations: [:],  // No citations in new architecture
                        extractionTime: extractionTime
                    )
                    logInfo(.app, "💾 Cached network for future use")
                }
                
                await MainActor.run {
                    extractionProgress = .complete
                }
                logInfo(.app, "✅ Family network processed successfully")
                
            } catch {
                // Log cross-reference errors but continue with the family
                logError(.app, "⚠️ Cross-reference resolution failed: \(error)")
                
                // Still use the base family even if cross-references fail
                await MainActor.run {
                    enhancedFamily = family
                }
            }
            
            // Step 5: Update UI with the family
            await MainActor.run {
                currentFamily = family
                isProcessing = false
                extractionProgress = .idle
                pendingFamilyId = nil  // Clear pending - we're done
                errorMessage = nil
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            logInfo(.app, "✅ Family extraction complete in \(String(format: "%.2f", totalTime))s")
            
            // Start background processing for next family
            familyNetworkCache.startBackgroundProcessing(
                currentFamilyId: normalizedId,
                fileManager: fileManager,
                aiService: aiParsingService,
                familyResolver: familyResolver
            )
            
        } catch {
            await MainActor.run {
                currentFamily = nil
                enhancedFamily = nil
                isProcessing = false
                extractionProgress = .idle
                pendingFamilyId = nil  // Clear pending on error
                
                if let extractionError = error as? ExtractionError {
                    errorMessage = extractionError.localizedDescription
                } else {
                    errorMessage = "Extraction failed: \(error.localizedDescription)"
                }
            }
            
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
    func generateCitation(for person: Person, in family: Family) async -> String {
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
            // Must be a spouse - try to find their asChild family first
            if let network = network,
               let spouseAsChildFamily = network.getSpouseAsChildFamily(for: person) {
                logInfo(.citation, "  Found spouse's asChild family: \(spouseAsChildFamily.familyId)")
                
                // Use helper to find and enhance the spouse
                if let enhancedSpouse = findEnhancedSpouseInAsChildFamily(
                    spouseName: person.name,
                    spouseAsChildFamily: spouseAsChildFamily,
                    nuclearFamily: family,
                    network: network
                ) {
                    citation = CitationGenerator.generateAsChildCitation(
                        for: enhancedSpouse,
                        in: spouseAsChildFamily,
                        network: network,
                        nameEquivalenceManager: nameEquivalenceManager
                    )
                } else {
                    // Fallback: generate without enhancement
                    citation = CitationGenerator.generateAsChildCitation(
                        for: person,
                        in: spouseAsChildFamily,
                        network: network,
                        nameEquivalenceManager: nameEquivalenceManager
                    )
                }
            } else {
                // No asChild family for spouse, use main citation
                logInfo(.citation, "  No asChild family found for spouse, using main family citation")
                citation = CitationGenerator.generateMainFamilyCitation(
                    family: family,
                    targetPerson: person,
                    network: network
                )
            }
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
        
        // Create a Person object for the spouse
        let spousePerson = Person(name: spouseName, noteMarkers: [])
        
        // Try to find the spouse in spouseAsChildFamilies
        if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: spousePerson) {
            logInfo(.citation, "📝 Found spouse's asChild family: \(spouseAsChildFamily.familyId)")
            
            // Use helper to find and enhance the spouse
            if let enhancedSpouse = findEnhancedSpouseInAsChildFamily(
                spouseName: spouseName,
                spouseAsChildFamily: spouseAsChildFamily,
                nuclearFamily: family,
                network: network
            ) {
                return CitationGenerator.generateAsChildCitation(
                    for: enhancedSpouse,
                    in: spouseAsChildFamily,
                    network: network,
                    nameEquivalenceManager: nameEquivalenceManager
                )
            } else {
                // Fallback: generate without enhancement
                return CitationGenerator.generateAsChildCitation(
                    for: spousePerson,
                    in: spouseAsChildFamily,
                    network: network,
                    nameEquivalenceManager: nameEquivalenceManager
                )
            }
        }
        
        // If not found as spouse asChild, try finding through child's asParent family
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
    
    // MARK: - Helper Methods

    /**
     * Find and enhance a spouse person from their asChild family
     * Returns the actual Person object from the family with all data populated
     */
    private func findEnhancedSpouseInAsChildFamily(
        spouseName: String,
        spouseAsChildFamily: Family,
        nuclearFamily: Family,
        network: FamilyNetwork
    ) -> Person? {
        logInfo(.citation, "🔍 Finding enhanced spouse in asChild family")
        
        // Step 1: Find the actual child in the asChild family
        let actualChild = spouseAsChildFamily.allChildren.first { child in
            // Match by name (flexible matching)
            let childNameLower = child.name.lowercased()
            let spouseNameLower = spouseName.lowercased()
            
            // Try exact match or partial match
            return childNameLower == spouseNameLower ||
                   spouseNameLower.contains(childNameLower) ||
                   childNameLower.contains(spouseNameLower.components(separatedBy: " ").first ?? "")
        }
        
        guard var spouse = actualChild else {
            logWarn(.citation, "⚠️ Could not find spouse '\(spouseName)' in asChild family")
            return nil
        }
        
        logInfo(.citation, "✅ Found spouse in asChild family: \(spouse.displayName)")
        
        // Step 2: Try to enhance with data from their asParent family
        // Find which child in the nuclear family has this spouse
        var childWithSpouse: Person? = nil
        for couple in nuclearFamily.couples {
            for child in couple.children {
                if child.spouse == spouseName {
                    childWithSpouse = child
                    break
                }
            }
            if childWithSpouse != nil { break }
        }
        
        // If we found the child, look for their asParent family which has enhanced spouse data
        if let child = childWithSpouse,
           let childAsParentFamily = network.getAsParentFamily(for: child) {
            // Find the spouse in the asParent family to get enhanced data
            if let enhancedSpouse = childAsParentFamily.findSpouseInFamily(for: child.name) {
                logInfo(.citation, "✅ Found enhanced spouse data in asParent family")
                // Merge the enhanced data
                spouse.birthDate = enhancedSpouse.birthDate ?? spouse.birthDate
                spouse.deathDate = enhancedSpouse.deathDate ?? spouse.deathDate
                spouse.fullMarriageDate = enhancedSpouse.fullMarriageDate ?? spouse.fullMarriageDate
                spouse.marriageDate = enhancedSpouse.marriageDate ?? spouse.marriageDate
            }
        }
        
        return spouse
    }
    
    // MARK: - Hiski Query Generation
    
    // MARK: - Hiski Query with Service

    func queryHiski(for person: Person, eventType: EventType, familyId: String) async -> String? {
        let hiskiService = HiskiService(nameEquivalenceManager: nameEquivalenceManager)
        hiskiService.setCurrentFamily(familyId)
        
        do {
            let citation: HiskiCitation
            
            switch eventType {
            case .birth:
                guard let birthDate = person.birthDate else { return nil }
                citation = try await hiskiService.queryBirth(name: person.name, date: birthDate)
                
            case .death:
                guard let deathDate = person.deathDate else { return nil }
                citation = try await hiskiService.queryDeath(name: person.name, date: deathDate)
                
            case .marriage:
                guard let marriageDate = person.bestMarriageDate,
                      let spouse = person.spouse else { return nil }
                citation = try await hiskiService.queryMarriage(
                    husbandName: person.displayName,
                    wifeName: spouse,
                    date: marriageDate
                )
                
            default:
                return nil
            }
            
            return citation.url
            
        } catch {
            logError(.app, "Hiski query failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Hiski Search URL Generation
    
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
        // First check ID if both have one
        if person1.id == person2.id {
            return true
        }
        
        // For people with birth dates, require BOTH name and birth date to match
        if let birth1 = person1.birthDate, let birth2 = person2.birthDate {
            // Birth dates must match exactly
            if birth1 != birth2 {
                return false
            }
            // And names must match
            return person1.name.lowercased() == person2.name.lowercased()
        }
        
        // If only one has a birth date, they're not equal
        // This prevents matching Matti (1679) with Matti (1712)
        if person1.birthDate != nil || person2.birthDate != nil {
            return false
        }
        
        // Only if neither has a birth date, match on name alone
        // This should be rare in genealogical data
        return person1.name.lowercased() == person2.name.lowercased()
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
