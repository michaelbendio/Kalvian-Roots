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
    
    /// Currently processing family ID
    private(set) var processingFamilyId: String?
    
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

    // MARK: - Initialization

    init(persistenceStore: PersistentFamilyNetworkStore) {
        self.persistenceStore = persistenceStore
        loadPersistedCache()
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
        let citations: [String: String]
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
    func getCachedNetwork(familyId: String) -> (network: FamilyNetwork, citations: [String: String])? {
        guard let cached = cachedNetworks[familyId] else { return nil }
        logInfo(.cache, "⚡ Retrieved cached network for: \(familyId)")
        return (cached.network, cached.citations)
    }
    
    /**
     * Cache a network
     */
    func cacheNetwork(_ network: FamilyNetwork, citations: [String: String], extractionTime: TimeInterval) {
        let cached = CachedFamily(
            network: network,
            citations: citations,
            cachedAt: Date(),
            extractionTime: extractionTime
        )
        cachedNetworks[network.mainFamily.familyId] = cached
        persistenceStore.save(cachedNetworks)
        logInfo(.cache, "💾 Cached network for: \(network.mainFamily.familyId)")
    }
    
    /**
     * Start background processing of next family
     */
    func startBackgroundProcessing(
        currentFamilyId: String,
        fileManager: RootsFileManager,
        aiService: AIParsingService,
        familyResolver: FamilyResolver
    ) {
        // Cancel any existing background task
        backgroundTask?.cancel()
        
        // Find next family ID
        guard let nextId = fileManager.findNextFamilyId(after: currentFamilyId) else {
            logInfo(.cache, "📋 No next family to process")
            return
        }
        
        // Check if already cached
        if isCached(familyId: nextId) {
            logInfo(.cache, "✅ Next family already cached: \(nextId)")
            self.nextFamilyId = nextId
            self.nextFamilyReady = true
            return
        }

        if let persistedFamily = persistenceStore.loadFamily(withId: nextId) {
            cachedNetworks[nextId] = persistedFamily
            logInfo(.cache, "✅ Next family restored from disk: \(nextId)")
            self.nextFamilyId = nextId
            self.nextFamilyReady = true
            return
        }

        // Start background processing
        self.processingFamilyId = nextId
        self.backgroundError = nil
        self.nextFamilyReady = false
        
        backgroundTask = Task {
            await processInBackground(
                familyId: nextId,
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

    private func processInBackground(
        familyId: String,
        fileManager: RootsFileManager,
        aiService: AIParsingService,
        familyResolver: FamilyResolver
    ) async {
        let startTime = Date()
        
        do {
            logInfo(.cache, "🔄 Background processing: \(familyId)")

            if isCached(familyId: familyId) {
                logInfo(.cache, "✅ Skipping background processing for already cached family: \(familyId)")
                self.processingFamilyId = nil
                self.nextFamilyId = familyId
                self.nextFamilyReady = true
                self.backgroundError = nil
                return
            }

            if let persistedFamily = persistenceStore.loadFamily(withId: familyId) {
                cachedNetworks[familyId] = persistedFamily
                logInfo(.cache, "✅ Loaded existing family from disk: \(familyId)")
                self.processingFamilyId = nil
                self.nextFamilyId = familyId
                self.nextFamilyReady = true
                self.backgroundError = nil
                return
            }

            // Check for cancellation
            if Task.isCancelled { return }

            // Extract family text
            guard let familyText = fileManager.extractFamilyText(familyId: familyId) else {
                throw ExtractionError.familyNotFound(familyId)
            }
            
            // Check for cancellation
            if Task.isCancelled { return }
            
            // Parse with AI
            let family = try await aiService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            // Check for cancellation
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
                throw ExtractionError.parsingFailed("Failed to build network")
            }
            
            let citations = workflow.getActiveCitations()
            let extractionTime = Date().timeIntervalSince(startTime)
            
            // Cache the results
            cacheNetwork(network, citations: citations, extractionTime: extractionTime)
            
            // Update state
            self.processingFamilyId = nil
            self.nextFamilyId = familyId
            self.nextFamilyReady = true
            self.backgroundError = nil
            
            logInfo(.cache, "✅ Background processing complete: \(familyId) (\(String(format: "%.1f", extractionTime))s)")
            
        } catch {
            if !Task.isCancelled {
                logError(.cache, "❌ Background processing failed: \(error)")
                self.processingFamilyId = nil
                self.backgroundError = "Failed to process \(familyId): \(error.localizedDescription)"
                self.nextFamilyReady = false
            }
        }
    }
}

