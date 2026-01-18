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

    private let cache: FamilyNetworkCaching
    private let fileManager: RootsFileManager
    private let aiParsingService: AIParsingService
    private let familyResolver: FamilyResolver

    init(
        cache: FamilyNetworkCaching,
        fileManager: RootsFileManager,
        aiParsingService: AIParsingService,
        familyResolver: FamilyResolver
    ) {
        self.cache = cache
        self.fileManager = fileManager
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
    }

    func loadFamily(familyId: String) async throws -> FamilyNetwork {
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespaces)

        if let loadedNetwork, currentFamilyId == normalizedId {
            return loadedNetwork
        }

        if let cached = cache.fetchNetwork(familyId: normalizedId) {
            currentFamilyId = normalizedId
            loadedNetwork = cached
            return cached
        }

        guard fileManager.isFileLoaded else {
            throw BrowserSessionError.fileNotLoaded
        }

        guard aiParsingService.isConfigured else {
            throw BrowserSessionError.aiNotConfigured
        }

        guard let familyText = fileManager.extractFamilyText(familyId: normalizedId) else {
            throw JuuretApp.ExtractionError.familyNotFound(normalizedId)
        }

        let family = try await aiParsingService.parseFamily(
            familyId: normalizedId,
            familyText: familyText
        )

        let workflow = FamilyNetworkWorkflow(
            nuclearFamily: family,
            familyResolver: familyResolver,
            resolveCrossReferences: true
        )
        try await workflow.process()

        guard let network = workflow.getFamilyNetwork() else {
            throw JuuretApp.ExtractionError.parsingFailed("Failed to build network")
        }

        cache.storeNetwork(network)

        currentFamilyId = normalizedId
        loadedNetwork = network

        return network
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

    init(
        cache: FamilyNetworkCaching,
        fileManager: RootsFileManager,
        aiParsingService: AIParsingService,
        familyResolver: FamilyResolver
    ) {
        self.cache = cache
        self.fileManager = fileManager
        self.aiParsingService = aiParsingService
        self.familyResolver = familyResolver
    }

    func session(for headers: HTTPHeaders) -> SessionResult {
        if let sessionId = parseSessionId(from: headers),
           let session = sessions[sessionId] {
            return SessionResult(session: session, sessionId: sessionId, isNew: false)
        }

        let sessionId = UUID().uuidString
        let session = BrowserSession(
            cache: cache,
            fileManager: fileManager,
            aiParsingService: aiParsingService,
            familyResolver: familyResolver
        )
        sessions[sessionId] = session
        return SessionResult(session: session, sessionId: sessionId, isNew: true)
    }

    func makeSessionCookieHeader(for sessionId: String) -> String {
        "\(SessionCookie.name)=\(sessionId); Path=/; SameSite=\(SessionCookie.sameSite); HttpOnly"
    }

    private func parseSessionId(from headers: HTTPHeaders) -> String? {
        guard let cookieHeader = headers.first(name: "Cookie") else {
            return nil
        }

        let cookies = cookieHeader.split(separator: ";")
        for cookie in cookies {
            let parts = cookie.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            if name == SessionCookie.name {
                return String(parts[1])
            }
        }

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
