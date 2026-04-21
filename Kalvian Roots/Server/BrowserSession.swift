//
//  BrowserSession.swift
//  Kalvian Roots
//
//  Browser session state for HTTP server
//

#if os(macOS)
import Foundation
import NIOHTTP1

@MainActor
final class BrowserSession {

    private(set) var currentFamilyId: String?
    private(set) var loadedNetwork: FamilyNetwork?
    private var familySearchExtractions: [String: FamilySearchFamilyExtraction] = [:]

    private let cache: FamilyNetworkCaching
    private let fileManager: RootsFileManager
    private let aiParsingService: AIParsingService
    private let familyResolver: FamilyResolver
    let nameEquivalenceManager: NameEquivalenceManager

    init(
        cache: FamilyNetworkCaching,
        fileManager: RootsFileManager,
        aiParsingService: AIParsingService,
        familyResolver: FamilyResolver,
        nameEquivalenceManager: NameEquivalenceManager
    ) {
        self.cache = cache
        self.fileManager = fileManager
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
        self.nameEquivalenceManager = nameEquivalenceManager
        
        logInfo(.network, "🌐 BrowserSession initialized")
    }

    func loadFamily(familyId: String) async throws -> FamilyNetwork {
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespaces)

        logInfo(.network, "📥 BrowserSession.loadFamily called")
        logInfo(.network, "   Input familyId: '\(familyId)'")
        logInfo(.network, "   Normalized ID: '\(normalizedId)'")
        logInfo(.network, "   Current familyId: '\(currentFamilyId ?? "nil")'")
        logInfo(.network, "   Has loaded network: \(loadedNetwork != nil)")

        // Check if we already have this family loaded
        if let loadedNetwork, currentFamilyId == normalizedId {
            logInfo(.network, "✅ Returning already-loaded network for: \(normalizedId)")
            return loadedNetwork
        }

        // Check cache
        logInfo(.network, "🔍 Checking cache for: \(normalizedId)")
        if let cached = cache.fetchNetwork(familyId: normalizedId) {
            logInfo(.network, "✅ Found in cache: \(normalizedId)")
            logInfo(.network, "   Main family: \(cached.mainFamily.familyId)")
            logInfo(.network, "   Children count: \(cached.mainFamily.allChildren.count)")
            currentFamilyId = normalizedId
            loadedNetwork = cached
            return cached
        }
        logInfo(.network, "❌ Not in cache: \(normalizedId)")

        // Validate file is loaded
        guard fileManager.isFileLoaded else {
            logError(.network, "❌ File not loaded!")
            throw BrowserSessionError.fileNotLoaded
        }
        logInfo(.network, "✅ File is loaded")

        // Validate AI is configured
        guard aiParsingService.isConfigured else {
            logError(.network, "❌ AI service not configured!")
            throw BrowserSessionError.aiNotConfigured
        }
        logInfo(.network, "✅ AI service is configured")

        // Extract family text
        logInfo(.network, "📝 Extracting family text for: \(normalizedId)")
        guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
            logError(.network, "❌ Family not found in file: \(normalizedId)")
            throw JuuretApp.ExtractionError.familyNotFound(normalizedId)
        }
        logInfo(.network, "✅ Family text extracted")
        logInfo(.network, "   Text length: \(familyText.count) characters")
        logInfo(.network, "   First 100 chars: \(String(familyText.prefix(100)))...")

        // Parse family with AI
        logInfo(.network, "🤖 Parsing family with AI service...")
        let family = try await aiParsingService.parseFamily(
            familyId: normalizedId,
            familyText: familyText
        )
        logInfo(.network, "✅ AI parsing complete")
        logInfo(.network, "   Family ID: \(family.familyId)")
        logInfo(.network, "   Couples: \(family.couples.count)")
        logInfo(.network, "   Children: \(family.allChildren.count)")

        // Build family network with cross-references
        logInfo(.network, "🔗 Building family network with cross-references...")
        let workflow = FamilyNetworkWorkflow(
            nuclearFamily: family,
            familyResolver: familyResolver,
            resolveCrossReferences: true
        )
        try await workflow.process()

        guard let network = workflow.getFamilyNetwork() else {
            logError(.network, "❌ Failed to build network from workflow")
            throw JuuretApp.ExtractionError.parsingFailed("Failed to build network")
        }
        logInfo(.network, "✅ Family network built successfully")
        logInfo(.network, "   asChildFamilies: \(network.asChildFamilies.count)")
        logInfo(.network, "   asParentFamilies: \(network.asParentFamilies.count)")
        logInfo(.network, "   spouseAsChildFamilies: \(network.spouseAsChildFamilies.count)")

        // Store in cache
        logInfo(.network, "💾 Storing network in cache...")
        cache.storeNetwork(network)

        currentFamilyId = normalizedId
        loadedNetwork = network

        logInfo(.network, "🎉 Family loading complete: \(normalizedId)")
        return network
    }

    func storeFamilySearchExtraction(
        _ extraction: FamilySearchFamilyExtraction,
        for familyId: String
    ) {
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        familySearchExtractions[normalizedId] = extraction
    }

    func familySearchExtraction(for familyId: String) -> FamilySearchFamilyExtraction? {
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespaces)
        return familySearchExtractions[normalizedId]
    }
}

@MainActor
final class BrowserSessionManager {

    struct SessionResult {
        let session: BrowserSession
        let sessionId: String
        let isNew: Bool
    }

    private enum SessionCookie {
        static let name = "KRSession"
        static let sameSite = "Lax"
    }

    private var sessions: [String: BrowserSession] = [:]

    private let cache: FamilyNetworkCaching
    private let fileManager: RootsFileManager
    private let aiParsingService: AIParsingService
    private let familyResolver: FamilyResolver
    private let nameEquivalenceManager: NameEquivalenceManager

    init(
        cache: FamilyNetworkCaching,
        fileManager: RootsFileManager,
        aiParsingService: AIParsingService,
        familyResolver: FamilyResolver,
        nameEquivalenceManager: NameEquivalenceManager
    ) {
        self.cache = cache
        self.fileManager = fileManager
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
        self.nameEquivalenceManager = nameEquivalenceManager
        
        logInfo(.network, "🌐 BrowserSessionManager initialized")
    }

    func session(for headers: HTTPHeaders) -> SessionResult {
        logInfo(.network, "🔐 BrowserSessionManager.session(for:) called")
        
        if let sessionId = parseSessionId(from: headers),
           let session = sessions[sessionId] {
            logInfo(.network, "✅ Found existing session: \(sessionId.prefix(8))...")
            return SessionResult(session: session, sessionId: sessionId, isNew: false)
        }

        let sessionId = UUID().uuidString
        logInfo(.network, "🆕 Creating new session: \(sessionId.prefix(8))...")
        
        let session = BrowserSession(
            cache: cache,
            fileManager: fileManager,
            aiParsingService: aiParsingService,
            familyResolver: familyResolver,
            nameEquivalenceManager: nameEquivalenceManager
        )
        sessions[sessionId] = session
        
        logInfo(.network, "✅ New session created. Total sessions: \(sessions.count)")
        return SessionResult(session: session, sessionId: sessionId, isNew: true)
    }

    func existingSession(id sessionId: String) -> BrowserSession? {
        sessions[sessionId]
    }

    func makeSessionCookieHeader(for sessionId: String) -> String {
        let header = "\(SessionCookie.name)=\(sessionId); Path=/; SameSite=\(SessionCookie.sameSite); HttpOnly"
        logInfo(.network, "🍪 Generated cookie header: \(header.prefix(50))...")
        return header
    }

    private func parseSessionId(from headers: HTTPHeaders) -> String? {
        guard let cookieHeader = headers.first(name: "Cookie") else {
            logInfo(.network, "🍪 No Cookie header found")
            return nil
        }
        
        logInfo(.network, "🍪 Parsing Cookie header: \(cookieHeader.prefix(50))...")

        let cookies = cookieHeader.split(separator: ";")
        for cookie in cookies {
            let parts = cookie.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            if name == SessionCookie.name {
                let sessionId = String(parts[1])
                logInfo(.network, "🍪 Found session ID: \(sessionId.prefix(8))...")
                return sessionId
            }
        }

        logInfo(.network, "🍪 Session cookie not found in header")
        return nil
    }
}

enum BrowserSessionError: LocalizedError {
    case fileNotLoaded
    case aiNotConfigured

    var errorDescription: String? {
        switch self {
        case .fileNotLoaded:
            return "File not loaded"
        case .aiNotConfigured:
            return "AI service not configured"
        }
    }
}

#endif
