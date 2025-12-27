//
//  FamilyNetworkCache.swift
//  Kalvian Roots
//
//  Simple cache for pre-processed family networks
//
//  Created by Michael Bendio on 9/4/25.
//

import Foundation

/**
 * FamilyNetworkCache - Simple in-memory cache for now
 *
 * We'll start with a simple dictionary-based cache and can add
 * CoreData + CloudKit later if needed
 */
@Observable
@MainActor
class FamilyNetworkCache {

    // MARK: - Properties

    /// Persistent store for cached networks
    private let persistenceStore: PersistentFamilyNetworkStore

    /// Simple in-memory cache storage
    private var cachedNetworks: [String: CachedFamily] = [:]
    
    /// Status message to display (only shows ready messages)
    private(set) var statusMessage: String?
    
    /// Currently processing family ID (internal use only)
    private var processingFamilyId: String?
    
    /// Next family ready state
    var nextFamilyReady: Bool = false
    
    /// Next family ID that's ready
    var nextFamilyId: String?
    
    /// Number of cached families
    var cachedFamilyCount: Int {
        return cachedNetworks.count
    }
    
    /// Background processing errors
    private(set) var backgroundError: String?

    /// Background task reference
    private var backgroundTask: Task<Void, Never>?
    
    /// Track how many families processed in this session
    private var familiesProcessedInSession = 0
    private let maxFamiliesToProcess = 10

    // MARK: - Initialization

    init(persistenceStore: PersistentFamilyNetworkStore) {
        self.persistenceStore = persistenceStore
        loadPersistedCache()
        
        // Show the last cached family on startup
        if let lastCached = findLastCachedFamily() {
            statusMessage = "\(lastCached) ready"
            logInfo(.cache, "📦 Last cached family: \(lastCached)")
        }
    }

    convenience init(rootsFileManager: RootsFileManager) {
        let store = PersistentFamilyNetworkStore(rootsFileManager: rootsFileManager)
        self.init(persistenceStore: store)
    }

    convenience init() {
        self.init(rootsFileManager: RootsFileManager())
    }

    // MARK: - Cache Structure

    struct CachedFamily: Codable, Sendable {
        let network: FamilyNetwork
        let cachedAt: Date
        let extractionTime: TimeInterval
    }
    
    // MARK: - Public Methods
    
    /**
     * Check if a family is cached
     */
    func isCached(familyId: String) -> Bool {
        return cachedNetworks[familyId] != nil
    }
    
    /**
     * Get cached network
     */
    func getCachedNetwork(familyId: String) -> FamilyNetwork? {
        let startTime = Date()
        let normalized = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Check memory cache first
        if let cached = cachedNetworks[normalized] {
            let retrieveTime = Date().timeIntervalSince(startTime)
            logInfo(.cache, "⚡ Retrieved from memory cache: \(normalized) in \(String(format: "%.3f", retrieveTime))s")
            return cached.network
        }
        
        // Check persistent store
        logInfo(.cache, "🔍 Checking persistent store for: \(normalized)")
        let diskStartTime = Date()
        
        if let persisted = persistenceStore.loadFamily(withId: normalized) {
            let diskLoadTime = Date().timeIntervalSince(diskStartTime)
            let totalTime = Date().timeIntervalSince(startTime)
            
            logInfo(.cache, """
                💾 Loaded from disk: \(normalized)
                - Disk read time: \(String(format: "%.3f", diskLoadTime))s
                - Total time: \(String(format: "%.3f", totalTime))s
                - Network size: \(persisted.network.allFamilies.count) families
                """)
            
            // Add to memory cache for next time
            cachedNetworks[normalized] = persisted
            
            return persisted.network
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        logInfo(.cache, "❌ Not found in cache: \(familyId) (checked in \(String(format: "%.3f", totalTime))s)")
        return nil
    }
    
    /**
     * Get just the nuclear/main family from cache (without the full network)
     * This is useful for cross-reference resolution to avoid redundant AI calls
     */
    func getCachedNuclearFamily(familyId: String) -> Family? {
        let normalized = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        // Check memory cache first
        if let cached = cachedNetworks[normalized] {
            logInfo(.cache, "⚡ Cache hit (nuclear) for: \(normalized)")
            return cached.network.mainFamily
        }
        
        // Check persistent store
        if let persisted = persistenceStore.loadFamily(withId: normalized) {
            logInfo(.cache, "💾 Cache hit (nuclear, disk) for: \(normalized)")
            // Add to memory cache for next time
            cachedNetworks[normalized] = persisted
            return persisted.network.mainFamily
        }
        
        logTrace(.cache, "❌ Cache miss (nuclear) for: \(normalized)")
        return nil
    }
    
    /**
     * Cache a network
     */
    func cacheNetwork(_ network: FamilyNetwork, extractionTime: TimeInterval) {
        let normalized = network.mainFamily.familyId.uppercased().trimmingCharacters(in: .whitespaces)
        let cached = CachedFamily(
            network: network,
            cachedAt: Date(),
            extractionTime: extractionTime
        )
        cachedNetworks[normalized] = cached  // Use normalized key
        persistenceStore.save(cachedNetworks)
        logInfo(.cache, "💾 Cached network for: \(normalized)")
    }
    
    /**
     * Delete a specific family from the cache
     * Useful for regenerating citations after code changes
     */
    func deleteCachedFamily(familyId: String) {
        let normalized = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        guard cachedNetworks[normalized] != nil else {
            logInfo(.cache, "⚠️ Family \(normalized) not found in cache")
            return
        }
        
        // Remove from memory cache
        cachedNetworks.removeValue(forKey: normalized)
        
        // Update persistence
        persistenceStore.save(cachedNetworks)
        
        // Update ready state if this was the next family
        if nextFamilyId == normalized {
            nextFamilyReady = false
        }
        
        logInfo(.cache, "🗑️ Deleted \(normalized) from cache")
    }
    
    /**
     * Clear all cached families
     * Useful when cache format changes or for debugging
     */
    func clearAllCache() {
        let count = cachedNetworks.count
        
        // Clear memory cache
        cachedNetworks.removeAll()
        
        // Clear persistent store
        persistenceStore.clear()
        
        // Reset state
        nextFamilyReady = false
        nextFamilyId = nil
        statusMessage = nil
        
        logInfo(.cache, "🧹 Cleared all \(count) cached families")
    }

    /**
     * Get the first cached family ID (sorted alphabetically/numerically)
     * This will be displayed on startup
     */
    func getFirstCachedFamilyId() -> String? {
        let allCachedIds = Array(cachedNetworks.keys)
        
        guard !allCachedIds.isEmpty else { return nil }
        
        // Sort them naturally (handles numeric sorting properly)
        let sortedIds = allCachedIds.sorted { (a, b) in
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        
        return sortedIds.first
    }

    /**
     * Get all cached family IDs in sorted order
     * Useful for displaying a list of cached families
     */
    func getAllCachedFamilyIds() -> [String] {
        let allCachedIds = Array(cachedNetworks.keys)
        
        // Sort them naturally
        return allCachedIds.sorted { (a, b) in
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    /**
     * Check if there are any cached families
     */
    var hasCachedFamilies: Bool {
        return !cachedNetworks.isEmpty
    }

    /**
     * Get information about a cached family
     */
    func getCachedFamilyInfo(familyId: String) -> (cachedAt: Date, extractionTime: TimeInterval)? {
        guard let cached = cachedNetworks[familyId] else { return nil }
        return (cached.cachedAt, cached.extractionTime)
    }
    
    /**
     * Start background processing - processes up to 5 families after current
     */
    func startBackgroundProcessing(
        currentFamilyId: String,
        fileManager: RootsFileManager,
        aiService: AIParsingService,
        familyResolver: FamilyResolver
    ) {
        // Cancel any existing background task
        backgroundTask?.cancel()
        
        // Reset session counter
        familiesProcessedInSession = 0
        
        // The "Next" button should ALWAYS show the immediate next family
        if let immediateNext = fileManager.findNextFamilyId(after: currentFamilyId) {
            self.nextFamilyId = immediateNext
            
            // Check if it's already cached
            if isCached(familyId: immediateNext) || persistenceStore.loadFamily(withId: immediateNext) != nil {
                self.nextFamilyReady = true
                logInfo(.cache, "✅ Next family already cached: \(immediateNext)")
            } else {
                self.nextFamilyReady = false
                logInfo(.cache, "⏳ Next family needs processing: \(immediateNext)")
            }
        }
        
        // Find where to start background processing (first uncached family)
        let startingFamilyId = findNextUncachedFamily(
            startingFrom: currentFamilyId,
            fileManager: fileManager
        )
        
        guard let processingStart = startingFamilyId else {
            logInfo(.cache, "📋 No uncached families found to process")
            return
        }
        
        logInfo(.cache, "🎯 Starting background processing from: \(processingStart)")
        logInfo(.cache, "📊 Will process up to \(maxFamiliesToProcess) families")
        
        // Start background processing
        self.processingFamilyId = processingStart
        self.backgroundError = nil
        
        backgroundTask = Task {
            await processInBackground(
                familyId: processingStart,
                fileManager: fileManager,
                aiService: aiService,
                familyResolver: familyResolver
            )
        }
    }
    
    /**
     * Clear cache
     */
    func clearCache() {
        cachedNetworks.removeAll()
        nextFamilyReady = false
        nextFamilyId = nil
        processingFamilyId = nil
        statusMessage = nil
        backgroundTask?.cancel()
        persistenceStore.clear()
        logInfo(.cache, "🗑️ Cache cleared")
    }
    
    // MARK: - Private Methods

    private func loadPersistedCache() {
        let persisted = persistenceStore.loadAll()

        guard !persisted.isEmpty else {
            logDebug(.cache, "📦 No persisted cache entries found")
            return
        }

        cachedNetworks = persisted
        updateReadyStateFromCache()

        logInfo(.cache, "📦 Restored \(persisted.count) cached families from disk")
    }

    private func updateReadyStateFromCache() {
        guard let latestEntry = cachedNetworks.max(by: { $0.value.cachedAt < $1.value.cachedAt }) else {
            nextFamilyReady = false
            nextFamilyId = nil
            return
        }

        nextFamilyReady = true
        nextFamilyId = latestEntry.key
    }
    
    /**
     * Find the last (highest) family in the cache
     */
    private func findLastCachedFamily() -> String? {
        // Sort family IDs naturally to find the highest one
        let sortedFamilies = cachedNetworks.keys.sorted { (a, b) in
            return a.localizedStandardCompare(b) == .orderedDescending
        }
        return sortedFamilies.first
    }
    
    /**
     * Find the next uncached family starting from a given position
     */
    private func findNextUncachedFamily(
        startingFrom familyId: String,
        fileManager: RootsFileManager
    ) -> String? {
        // Get all family IDs from the file
        let allFamilyIds = fileManager.getAllFamilyIds()
        
        // Find the starting position
        guard let startIndex = allFamilyIds.firstIndex(of: familyId) else {
            // If we can't find the current family, check from beginning
            return allFamilyIds.first { familyId in
                !isCached(familyId: familyId) && persistenceStore.loadFamily(withId: familyId) == nil
            }
        }
        
        // Look for the first uncached family after the current one
        for i in (startIndex + 1)..<allFamilyIds.count {
            let candidateId = allFamilyIds[i]
            
            // Check if this family is already cached (in memory or on disk)
            if !isCached(familyId: candidateId) {
                if persistenceStore.loadFamily(withId: candidateId) == nil {
                    // Found an uncached family
                    return candidateId
                }
            }
        }
        
        logInfo(.cache, "✅ All families after \(familyId) are already cached")
        return nil
    }

    /**
     * Process families in background
     */
    private func processInBackground(
        familyId: String,
        fileManager: RootsFileManager,
        aiService: AIParsingService,
        familyResolver: FamilyResolver
    ) async {
        let startTime = Date()
        
        do {
            logInfo(.cache, "🔄 Background processing: \(familyId)")
            
            // No "Preparing" message - just process silently
            
            // Check if already cached in memory
            if isCached(familyId: familyId) {
                logInfo(.cache, "✅ Skipping already cached family: \(familyId)")
                
                // Show ready message
                self.statusMessage = "\(familyId) ready"
                
                // If this is the immediate next family, mark it ready
                if familyId == nextFamilyId {
                    self.nextFamilyReady = true
                }
                
                // Continue to next family
                if familiesProcessedInSession < maxFamiliesToProcess {
                    if let nextId = fileManager.findNextFamilyId(after: familyId) {
                        await continueBackgroundProcessing(
                            nextFamilyId: nextId,
                            fileManager: fileManager,
                            aiService: aiService,
                            familyResolver: familyResolver
                        )
                    }
                }
                return
            }

            // Check if persisted on disk
            if let persistedFamily = persistenceStore.loadFamily(withId: familyId) {
                cachedNetworks[familyId] = persistedFamily
                logInfo(.cache, "✅ Loaded existing family from disk: \(familyId)")
                
                // Show ready message
                self.statusMessage = "\(familyId) ready"
                
                // If this is the immediate next family, mark it ready
                if familyId == nextFamilyId {
                    self.nextFamilyReady = true
                }
                
                // Continue to next family
                if familiesProcessedInSession < maxFamiliesToProcess {
                    if let nextId = fileManager.findNextFamilyId(after: familyId) {
                        await continueBackgroundProcessing(
                            nextFamilyId: nextId,
                            fileManager: fileManager,
                            aiService: aiService,
                            familyResolver: familyResolver
                        )
                    }
                }
                return
            }

            // Check for cancellation
            if Task.isCancelled { return }

            // Extract family text
            guard let familyText = fileManager.extractFamilyText(familyId: familyId) else {
                throw JuuretApp.ExtractionError.familyNotFound(familyId)
            }
            
            if Task.isCancelled { return }
            
            // Parse with AI (happens silently in background)
            let family = try await aiService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            if Task.isCancelled { return }
            
            // Create workflow for cross-references
            let workflow = FamilyNetworkWorkflow(
                nuclearFamily: family,
                familyResolver: familyResolver,
                resolveCrossReferences: true
            )
            
            // Process the workflow
            try await workflow.process()
            
            // Get the network and citations
            guard let network = workflow.getFamilyNetwork() else {
                throw JuuretApp.ExtractionError.parsingFailed("Failed to build network")
            }
            
            let extractionTime = Date().timeIntervalSince(startTime)
            
            // Cache the results
            cacheNetwork(network, extractionTime: extractionTime)
            
            // INCREMENT the processed counter
            familiesProcessedInSession += 1
            
            // NOW show the ready message after successful caching
            self.statusMessage = "\(familyId) ready"
            
            // If this is the immediate next family, mark it ready
            if familyId == nextFamilyId {
                self.nextFamilyReady = true
            }
            
            logInfo(.cache, "✅ Background processing complete: \(familyId) (\(String(format: "%.1f", extractionTime))s)")
            logInfo(.cache, "📊 Processed \(familiesProcessedInSession)/\(maxFamiliesToProcess) families in this session")
            
            // Check if we should continue or stop
            if familiesProcessedInSession >= maxFamiliesToProcess {
                logInfo(.cache, "🛑 Reached processing limit (\(maxFamiliesToProcess) families)")
                return
            }
            
            // Continue with next family
            if let nextId = fileManager.findNextFamilyId(after: familyId) {
                await continueBackgroundProcessing(
                    nextFamilyId: nextId,
                    fileManager: fileManager,
                    aiService: aiService,
                    familyResolver: familyResolver
                )
            } else {
                logInfo(.cache, "✅ No more families to process")
            }
            
        } catch {
            if !Task.isCancelled {
                logError(.cache, "❌ Background processing failed: \(error)")
                self.backgroundError = "Failed to process \(familyId)"
                
                // Count this as processed to prevent infinite retries
                familiesProcessedInSession += 1
            }
        }
    }
    
    /**
     * Continue background processing with the next family
     */
    private func continueBackgroundProcessing(
        nextFamilyId: String,
        fileManager: RootsFileManager,
        aiService: AIParsingService,
        familyResolver: FamilyResolver
    ) async {
        // Check if we've hit our limit
        if familiesProcessedInSession >= maxFamiliesToProcess {
            logInfo(.cache, "🛑 Reached session limit, stopping background processing")
            self.processingFamilyId = nil
            return
        }
        
        // Short delay to avoid overwhelming the system
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check if still active and not cancelled
        guard !Task.isCancelled else { return }
        
        // Update state to show what we're processing (internally)
        self.processingFamilyId = nextFamilyId
        
        logInfo(.cache, "🔄 Continuing to process: \(nextFamilyId) (session: \(familiesProcessedInSession + 1)/\(maxFamiliesToProcess))")
        
        // Continue processing the next family
        await processInBackground(
            familyId: nextFamilyId,
            fileManager: fileManager,
            aiService: aiService,
            familyResolver: familyResolver
        )
    }
}

