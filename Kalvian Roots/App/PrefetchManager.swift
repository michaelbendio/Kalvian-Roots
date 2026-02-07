//
//  PrefetchManager.swift
//  Kalvian Roots
//
//  Caches all families in FamilyIDs order, skipping what is already cached.
//

import Foundation
import Combine

@MainActor
final class PrefetchManager: ObservableObject {
    @Published private(set) var isPrefetching: Bool = false
    @Published private(set) var currentFamilyId: String?
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    
    private var prefetchTask: Task<Void, Never>?
    
    private let fileManager: RootsFileManager
    private let aiService: AIParsingService
    private let familyResolver: FamilyResolver
    private let familyNetworkCache: FamilyNetworkCache
    
    init(
        fileManager: RootsFileManager,
        aiService: AIParsingService,
        familyResolver: FamilyResolver,
        familyNetworkCache: FamilyNetworkCache
    ) {
        self.fileManager = fileManager
        self.aiService = aiService
        self.familyResolver = familyResolver
        self.familyNetworkCache = familyNetworkCache
    }
    
    func startPrefetchAll() {
        guard !isPrefetching else { return }
        guard fileManager.isFileLoaded else { return }
        guard aiService.isConfigured else { return }
        
        let orderedFamilies = FamilyIDs.validFamilyIds
        totalCount = orderedFamilies.count
        completedCount = 0
        currentFamilyId = nil
        isPrefetching = true
        
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            await self.runPrefetchAll(orderedFamilies: orderedFamilies)
        }
    }
    
    func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        isPrefetching = false
        currentFamilyId = nil
    }
    
    func isFamilyCached(familyId: String) -> Bool {
        let normalized = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        return familyNetworkCache.isCached(familyId: normalized)
            || familyNetworkCache.isFamilyCachedOnDisk(familyId: normalized)
    }
    
    private func runPrefetchAll(orderedFamilies: [String]) async {
        defer {
            isPrefetching = false
            currentFamilyId = nil
            prefetchTask = nil
        }
        
        for familyId in orderedFamilies {
            if Task.isCancelled { break }
            
            if isFamilyCached(familyId: familyId) {
                completedCount += 1
                continue
            }
            
            currentFamilyId = familyId
            
            do {
                _ = try await familyNetworkCache.prefetchFamilyIfNeeded(
                    familyId: familyId,
                    fileManager: fileManager,
                    aiService: aiService,
                    familyResolver: familyResolver
                )
            } catch {
                if Task.isCancelled { break }
                logError(.cache, "❌ Prefetch failed for \(familyId): \(error)")
            }
            
            completedCount += 1
        }
    }
}
