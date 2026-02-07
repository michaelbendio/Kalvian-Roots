//
//  KalvianRootsServer.swift
//  Kalvian Roots
//
//  SwiftNIO HTTP server for browser-based interface
//  Runs in-process with the SwiftUI app for shared state
//

#if os(macOS)
import Foundation
import NIO
import NIOCore
import NIOHTTP1
import NIOPosix

/**
 * HTTP Server for Kalvian Roots browser interface
 *
 * Provides server-rendered HTML access to family data via Tailscale
 * Reuses all domain logic from the SwiftUI app
 */
@MainActor
class KalvianRootsServer {

    // MARK: - Properties

    private weak var juuretApp: JuuretApp?
    private let sessionManager: BrowserSessionManager
    private var channel: Channel?
    private let port: Int
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    // MARK: - Initialization

    init(juuretApp: JuuretApp, port: Int) {
        self.juuretApp = juuretApp
        self.port = port
        self.sessionManager = BrowserSessionManager(
            cache: juuretApp.familyNetworkCache,
            fileManager: juuretApp.fileManager,
            aiParsingService: juuretApp.aiParsingService,
            familyResolver: juuretApp.familyResolver,
            nameEquivalenceManager: juuretApp.nameEquivalenceManager
        )
    }

    // MARK: - Server Lifecycle

    func start() async throws {
        guard let juuretApp = juuretApp else {
            throw ServerError.appNotAvailable
        }

        // Create bootstrap configuration
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline
                    .configureHTTPServerPipeline(withErrorHandling: true)
                    .flatMap { [self] in
                    channel.pipeline
                        .addHandler(
                            HTTPHandler(
                                sessionManager: self.sessionManager,
                                juuretApp: juuretApp
                            )
                        )
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        // Bind to all interfaces on specified port
        channel = try await bootstrap.bind(host: "0.0.0.0", port: port).get()

        logInfo(.app, "🌐 HTTP server started on port \(port)")
        logInfo(.app, "   Access via Tailscale: http://[your-tailscale-ip]:\(port)")
    }

    func stop() async {
        do {
            try await channel?.close()
            try await eventLoopGroup.shutdownGracefully()
            logInfo(.app, "🛑 HTTP server stopped")
        } catch {
            logError(.app, "Error stopping server: \(error)")
        }
    }

    // MARK: - Error Types

    enum ServerError: Error {
        case appNotAvailable
    }
}

// MARK: - HTTP Request Handler

import Logging

final class HTTPHandler: ChannelInboundHandler {

    // MARK: - NIO Types

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    // MARK: - Transport Response Model

    private enum HTTPResponse {
        case html(String, status: HTTPResponseStatus = .ok, headers: HTTPHeaders = HTTPHeaders())
        case redirect(String, headers: HTTPHeaders = HTTPHeaders())
        case error(HTTPResponseStatus, String, headers: HTTPHeaders = HTTPHeaders())
    }

    // MARK: - State

    private let sessionManager: BrowserSessionManager
    private weak var juuretApp: JuuretApp?

    private var buffer = ByteBuffer()
    private var requestURI: String?
    private var requestMethod: HTTPMethod?
    private var requestBody: String?
    private var requestHeaders: HTTPHeaders?
    private var isKeepAlive = false
    private var requestID: UUID?

    private let logger = Logger(label: "KalvianRoots.HTTP")

    // MARK: - Init

    init(sessionManager: BrowserSessionManager, juuretApp: JuuretApp) {
        self.sessionManager = sessionManager
        self.juuretApp = juuretApp
    }

    // MARK: - ChannelInboundHandler

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {

        case .head(let request):
            requestID = UUID()
            requestURI = request.uri
            requestMethod = request.method
            isKeepAlive = request.isKeepAlive
            requestHeaders = request.headers
            buffer.clear()
            requestBody = nil

            logger.info(
                "[\(requestID!)] ⇢ Request",
                metadata: [
                    "method": "\(request.method)",
                    "uri": "\(request.uri)",
                    "keepAlive": "\(request.isKeepAlive)"
                ]
            )

        case .body(var body):
            buffer.writeBuffer(&body)

        case .end:
            if buffer.readableBytes > 0 {
                requestBody = buffer.getString(
                    at: buffer.readerIndex,
                    length: buffer.readableBytes
                )
            }
            routeRequest(context: context)
        }
    }

    // MARK: - Routing Entry Point

    private func routeRequest(context: ChannelHandlerContext) {
        guard let uri = requestURI,
              let method = requestMethod else {
            send(.error(.badRequest, "Invalid request"), on: context)
            return
        }

        let urlComponents = URLComponents(string: uri)
        let path = urlComponents?.path ?? "/"
        let queryItems = urlComponents?.queryItems ?? []

        logger.info(
            "[\(requestID!)] 🛤️ Routing",
            metadata: [
                "method": "\(method)",
                "path": "\(path)",
                "queryItemCount": "\(queryItems.count)",
                "queryItems": "\(queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))"
            ]
        )

        let eventLoop = context.eventLoop
        let channel = context.channel

        Task { @MainActor in
            let response: HTTPResponse

            do {
                response = try await handleRoute(
                    method: method,
                    path: path,
                    queryItems: queryItems
                )
            } catch {
                logger.error(
                    "[\(requestID!)] ❌ Route handler error",
                    metadata: ["error": "\(error)"]
                )
                response = .error(.internalServerError, "Server error: \(error)")
            }

            eventLoop.execute {
                // Reconstitute a context-safe write via the channel pipeline
                channel.pipeline.context(handler: self).whenSuccess { ctx in
                    self.logger.info(
                        "[\(self.requestID!)] ⇠ Responding",
                        metadata: ["keepAlive": "\(self.isKeepAlive)"]
                    )
                    self.send(response, on: ctx)
                }
            }
        }
    }

    // MARK: - Route Dispatcher (MainActor only)

    @MainActor
    private func handleRoute(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> HTTPResponse {

        logger.info(
            "[\(requestID!)] 📍 handleRoute called",
            metadata: [
                "method": "\(method)",
                "path": "\(path)"
            ]
        )

        switch (method, path) {

        case (.GET, "/"):
            logger.info("[\(requestID!)] 🏠 Handling landing page")
            let error = queryItems.first(where: { $0.name == "error" })?.value
            let html = HTMLRenderer.renderLandingPage(error: error)
            return .html(html)

        case (.POST, "/"):
            logger.info("[\(requestID!)] 📝 Handling landing page POST")
            return handleLandingPagePost()

        case (.GET, "/family"):
            // Handle form submission from navigation bar
            logger.info("[\(requestID!)] 📝 Handling family form submission")
            
            // Log all query items for debugging
            logger.info(
                "[\(requestID!)] Query items",
                metadata: [
                    "count": "\(queryItems.count)",
                    "items": "\(queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))"
                ]
            )
            
            if let rawFamilyId = queryItems.first(where: { $0.name == "id" })?.value {
                // Decode + to space (URL form encoding)
                let familyId = rawFamilyId.replacingOccurrences(of: "+", with: " ")
                
                let canonical = familyId
                    .trimmingCharacters(in: .whitespaces)
                    .uppercased()
                
                logger.info(
                    "[\(requestID!)] Form family ID",
                    metadata: [
                        "raw": "\(rawFamilyId)",
                        "decoded": "\(familyId)",
                        "canonical": "\(canonical)",
                        "length": "\(canonical.count)"
                    ]
                )
                
                guard FamilyIDs.isValid(familyId: canonical) else {
                    logger.warning(
                        "[\(requestID!)] ⚠️ Invalid family ID from form",
                        metadata: ["familyId": "\(canonical)"]
                    )
                    return .redirect("/?error=invalid")
                }
                
                let encoded = canonical.addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed
                ) ?? canonical
                
                logger.info("[\(requestID!)] ✅ Valid family ID, redirecting to: /family/\(encoded)")
                
                // Redirect to family page (becomes new home)
                return .redirect("/family/\(encoded)")
            } else {
                logger.warning("[\(requestID!)] ⚠️ No 'id' parameter in form submission")
                return .redirect("/?error=invalid")
            }

        case (.GET, let p) where p.starts(with: "/family/"):
            logger.info("[\(requestID!)] 👪 Handling family route: \(p)")
            return try await handleFamilyRoute(path: p, queryItems: queryItems)

        default:
            logger.warning("[\(requestID!)] ❓ Unknown route: \(method) \(path)")
            return .error(.notFound, "Not Found")
        }
    }

    // MARK: - Route Handlers (MainActor)

    @MainActor
    private func handleLandingPagePost() -> HTTPResponse {
        guard let body = requestBody,
              let familyId = parseFormData(body)["family"] else {
            logger.warning("[\(requestID!)] ⚠️ Invalid POST body")
            return .redirect("/?error=invalid")
        }

        let canonical =
            familyId
                .trimmingCharacters(in: .whitespaces)
                .uppercased()

        let isValid = FamilyIDs.isValid(familyId: canonical)

        logger.info(
            "[\(requestID!)] Family ID from POST",
            metadata: [
                "raw": "\(familyId)",
                "canonical": "\(canonical)",
                "isValid": "\(isValid)"
            ]
        )

        guard isValid else {
            return .redirect("/?error=invalid")
        }

        let encoded =
            canonical.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? canonical

        return .redirect("/family/\(encoded)")
    }

    @MainActor
    private func handleFamilyRoute(path: String, queryItems: [URLQueryItem]) async throws -> HTTPResponse {
        // Parse path components: /family/{familyId} or /family/{familyId}/cite or /family/{familyId}/hiski
        let components = path.split(separator: "/").map(String.init)
        
        logger.info(
            "[\(requestID!)] 🔍 Parsing family route",
            metadata: [
                "path": "\(path)",
                "componentCount": "\(components.count)",
                "components": "\(components.joined(separator: ", "))"
            ]
        )
        
        guard components.count >= 2 else {
            logger.warning("[\(requestID!)] ⚠️ Not enough path components")
            return .error(.notFound, "Not Found")
        }

        let rawID = components[1]
        let decodedID = rawID.removingPercentEncoding ?? rawID
        let canonicalID =
            decodedID
                .trimmingCharacters(in: .whitespaces)
                .uppercased()

        let isValid = FamilyIDs.isValid(familyId: canonicalID)

        logger.info(
            "[\(requestID!)] 📋 Family ID parsed",
            metadata: [
                "raw": "\(rawID)",
                "decoded": "\(decodedID)",
                "canonical": "\(canonicalID)",
                "isValid": "\(isValid)"
            ]
        )

        guard isValid else {
            return .redirect("/?error=invalid")
        }

        // Extract query parameters
        let homeParam = queryItems.first(where: { $0.name == "home" })?.value
        let reloadFlag = queryItems.first(where: { $0.name == "reload" })?.value != nil
        
        // Determine home ID: use query param if present, otherwise displayed family is home
        let homeId: String?
        if let rawHomeParam = homeParam {
            // Decode + to space (URL form encoding)
            let decodedHomeParam = rawHomeParam.replacingOccurrences(of: "+", with: " ")
            let canonicalHome = decodedHomeParam
                .trimmingCharacters(in: .whitespaces)
                .uppercased()
            homeId = FamilyIDs.isValid(familyId: canonicalHome) ? canonicalHome : nil
        } else {
            homeId = nil  // nil means displayed family is home
        }
        
        logger.info(
            "[\(requestID!)] 🏠 Home parameter",
            metadata: [
                "homeParamRaw": "\(homeParam ?? "nil")",
                "homeIdDecoded": "\(homeId ?? "nil (displayed is home)")",
                "reloadFlag": "\(reloadFlag)"
            ]
        )

        // Determine sub-route
        let subRoute = components.count >= 3 ? components[2] : nil
        
        logger.info(
            "[\(requestID!)] 🎯 Sub-route detection",
            metadata: [
                "subRoute": "\(subRoute ?? "none")",
                "hasSubRoute": "\(subRoute != nil)"
            ]
        )

        // Get session
        let headers = requestHeaders ?? HTTPHeaders()
        let sessionResult = sessionManager.session(for: headers)
        let setCookieHeader = sessionResult.isNew
            ? sessionManager.makeSessionCookieHeader(for: sessionResult.sessionId)
            : nil

        logger.info(
            "[\(requestID!)] 🔐 Session",
            metadata: [
                "sessionId": "\(sessionResult.sessionId.prefix(8))...",
                "isNew": "\(sessionResult.isNew)"
            ]
        )
        
        // Handle reload flag - regenerate home family
        if reloadFlag, let actualHome = homeId ?? canonicalID as String? {
            logger.info("[\(requestID!)] ↺ Reload requested for: \(actualHome)")
            if let app = juuretApp {
                do {
                    await app.regenerateCachedFamily(familyId: actualHome)
                    logger.info("[\(requestID!)] ✅ Family regenerated: \(actualHome)")
                } catch {
                    logger.error(
                        "[\(requestID!)] ❌ Failed to regenerate family",
                        metadata: ["error": "\(error)"]
                    )
                }
            }
        }

        // Load family network for displayed family
        let network: FamilyNetwork
        do {
            logger.info("[\(requestID!)] 📥 Loading family network for: \(canonicalID)")
            network = try await sessionResult.session.loadFamily(familyId: canonicalID)
            logger.info(
                "[\(requestID!)] ✅ Family network loaded",
                metadata: [
                    "familyId": "\(network.mainFamily.familyId)",
                    "childCount": "\(network.mainFamily.allChildren.count)"
                ]
            )
        } catch {
            logger.error(
                "[\(requestID!)] ❌ Failed to load family",
                metadata: ["error": "\(error)"]
            )

            var responseHeaders = HTTPHeaders()
            if let setCookieHeader {
                responseHeaders.add(name: "Set-Cookie", value: setCookieHeader)
            }

            return .error(.notFound, "Family not found: \(error.localizedDescription)", headers: responseHeaders)
        }

        // Handle sub-routes
        switch subRoute {
        case "cite":
            logger.info("[\(requestID!)] 📝 Handling CITATION request")
            return await handleCitationRequest(
                familyId: canonicalID,
                network: network,
                queryItems: queryItems,
                homeId: homeId,
                setCookieHeader: setCookieHeader
            )
            
        case "hiski":
            logger.info("[\(requestID!)] 🔎 Handling HISKI request")
            return await handleHiskiRequest(
                familyId: canonicalID,
                network: network,
                queryItems: queryItems,
                homeId: homeId,
                setCookieHeader: setCookieHeader,
                session: sessionResult.session
            )
            
        case nil:
            logger.info("[\(requestID!)] 🏠 Rendering family display (no sub-route)")
            let html = HTMLRenderer.renderFamily(
                family: network.mainFamily,
                network: network,
                homeId: homeId
            )

            var responseHeaders = HTTPHeaders()
            if let setCookieHeader {
                responseHeaders.add(name: "Set-Cookie", value: setCookieHeader)
            }

            return .html(html, headers: responseHeaders)
            
        default:
            logger.warning("[\(requestID!)] ⚠️ Unknown sub-route: \(subRoute ?? "nil")")
            return .error(.notFound, "Unknown route: \(subRoute ?? "")")
        }
    }
    
    // MARK: - Citation Handler
    
    @MainActor
    private func handleCitationRequest(
        familyId: String,
        network: FamilyNetwork,
        queryItems: [URLQueryItem],
        homeId: String?,
        setCookieHeader: String?
    ) async -> HTTPResponse {
        // Extract query parameters
        let name = queryItems.first(where: { $0.name == "name" })?.value
        let birthDate = queryItems.first(where: { $0.name == "birth" })?.value
        let role = queryItems.first(where: { $0.name == "role" })?.value
        
        logger.info(
            "[\(requestID!)] 📋 Citation request parameters",
            metadata: [
                "name": "\(name ?? "nil")",
                "birthDate": "\(birthDate ?? "nil")",
                "role": "\(role ?? "nil")"
            ]
        )
        
        guard let personName = name else {
            logger.warning("[\(requestID!)] ⚠️ Missing 'name' parameter for citation")
            return renderFamilyWithError(
                network: network,
                homeId: homeId,
                error: "Missing person name for citation",
                setCookieHeader: setCookieHeader
            )
        }
        
        // Find the person in the family
        let person = findPerson(
            name: personName,
            birthDate: birthDate,
            in: network.mainFamily
        )
        
        logger.info(
            "[\(requestID!)] 🔍 Person lookup result",
            metadata: [
                "found": "\(person != nil)",
                "personName": "\(person?.displayName ?? "not found")"
            ]
        )
        
        guard let person = person else {
            return renderFamilyWithError(
                network: network,
                homeId: homeId,
                error: "Person '\(personName)' not found in family",
                setCookieHeader: setCookieHeader
            )
        }
        
        // Generate citation based on role
        let citation = generateCitation(for: person, role: role, network: network)
        
        logger.info(
            "[\(requestID!)] ✅ Citation generated",
            metadata: [
                "citationLength": "\(citation.count)",
                "citationPreview": "\(String(citation.prefix(100)))..."
            ]
        )
        
        // Render family with citation panel
        let html = HTMLRenderer.renderFamily(
            family: network.mainFamily,
            network: network,
            homeId: homeId,
            citationText: citation
        )
        
        var responseHeaders = HTTPHeaders()
        if let setCookieHeader {
            responseHeaders.add(name: "Set-Cookie", value: setCookieHeader)
        }
        
        return .html(html, headers: responseHeaders)
    }
    
    // MARK: - Hiski Handler
    
    @MainActor
    private func handleHiskiRequest(
        familyId: String,
        network: FamilyNetwork,
        queryItems: [URLQueryItem],
        homeId: String?,
        setCookieHeader: String?,
        session: BrowserSession
    ) async -> HTTPResponse {
        // Extract query parameters
        let name = queryItems.first(where: { $0.name == "name" })?.value
        let birthDate = queryItems.first(where: { $0.name == "birth" })?.value
        let eventType = queryItems.first(where: { $0.name == "event" })?.value
        let date = queryItems.first(where: { $0.name == "date" })?.value
        
        // For marriage, we have two spouses
        let spouse1 = queryItems.first(where: { $0.name == "spouse1" })?.value
        let birth1 = queryItems.first(where: { $0.name == "birth1" })?.value
        let spouse2 = queryItems.first(where: { $0.name == "spouse2" })?.value
        let birth2 = queryItems.first(where: { $0.name == "birth2" })?.value
        
        logger.info(
            "[\(requestID!)] 🔎 Hiski request parameters",
            metadata: [
                "name": "\(name ?? "nil")",
                "birthDate": "\(birthDate ?? "nil")",
                "eventType": "\(eventType ?? "nil")",
                "date": "\(date ?? "nil")",
                "spouse1": "\(spouse1 ?? "nil")",
                "spouse2": "\(spouse2 ?? "nil")"
            ]
        )
        
        // Create HiskiService with httpOnly mode
        let hiskiService = HiskiService(nameEquivalenceManager: session.nameEquivalenceManager)
        hiskiService.setCurrentFamily(familyId)
        
        // Initialize citationResult - will be set by successful queries
        var citationResult: String = ""
        var errorMessage: String?
        
        logger.info("[\(requestID!)] 🔍 Event type: \(eventType ?? "nil")")
        
        switch eventType {
        case "birth":
            guard let personName = name, let searchDate = date else {
                errorMessage = "Missing name or date for birth query"
                break
            }
            logger.info("[\(requestID!)] 👶 Processing birth query for: \(personName), date: \(searchDate)")
            
            let result = await hiskiService.queryBirthWithResult(
                name: personName,
                date: searchDate,
                fatherName: nil,
                mode: .httpOnly
            )
            
            switch result {
            case .found(let citationURL, _):
                logger.info("[\(requestID!)] ✅ Birth citation found: \(citationURL)")
                citationResult = citationURL
            case .notFound:
                logger.warning("[\(requestID!)] ⚠️ No birth record found")
                errorMessage = "No birth record found for \(personName) on \(searchDate)"
            case .multipleResults(let searchURL):
                logger.info("[\(requestID!)] 📋 Multiple birth results, search URL: \(searchURL)")
                citationResult = "Multiple results found. Search URL:\n\(searchURL)"
            case .error(let message):
                logger.error("[\(requestID!)] ❌ Birth query error: \(message)")
                errorMessage = "HisKi query failed: \(message)"
            }
            
        case "death":
            guard let personName = name, let searchDate = date else {
                errorMessage = "Missing name or date for death query"
                break
            }
            logger.info("[\(requestID!)] 💀 Processing death query for: \(personName), date: \(searchDate)")
            
            let result = await hiskiService.queryDeathWithResult(
                name: personName,
                date: searchDate,
                mode: .httpOnly
            )
            
            switch result {
            case .found(let citationURL, _):
                logger.info("[\(requestID!)] ✅ Death citation found: \(citationURL)")
                citationResult = citationURL
            case .notFound:
                logger.warning("[\(requestID!)] ⚠️ No death record found")
                errorMessage = "No death record found for \(personName) on \(searchDate)"
            case .multipleResults(let searchURL):
                logger.info("[\(requestID!)] 📋 Multiple death results, search URL: \(searchURL)")
                citationResult = "Multiple results found. Search URL:\n\(searchURL)"
            case .error(let message):
                logger.error("[\(requestID!)] ❌ Death query error: \(message)")
                errorMessage = "HisKi query failed: \(message)"
            }
            
        case "marriage":
            guard let s1 = spouse1, let s2 = spouse2, let searchDate = date else {
                errorMessage = "Missing spouse names or date for marriage query"
                break
            }
            logger.info("[\(requestID!)] 💒 Processing marriage query: \(s1) + \(s2), date: \(searchDate)")
            
            let result = await hiskiService.queryMarriageWithResult(
                husbandName: s1,
                wifeName: s2,
                date: searchDate,
                mode: .httpOnly
            )
            
            switch result {
            case .found(let citationURL, _):
                logger.info("[\(requestID!)] ✅ Marriage citation found: \(citationURL)")
                citationResult = citationURL
            case .notFound:
                logger.warning("[\(requestID!)] ⚠️ No marriage record found")
                errorMessage = "No marriage record found for \(s1) & \(s2) on \(searchDate)"
            case .multipleResults(let searchURL):
                logger.info("[\(requestID!)] 📋 Multiple marriage results, search URL: \(searchURL)")
                citationResult = "Multiple results found. Search URL:\n\(searchURL)"
            case .error(let message):
                logger.error("[\(requestID!)] ❌ Marriage query error: \(message)")
                errorMessage = "HisKi query failed: \(message)"
            }
            
        default:
            errorMessage = "Unknown event type: \(eventType ?? "nil")"
        }
        
        // Render response
        if let error = errorMessage {
            return renderFamilyWithError(
                network: network,
                homeId: homeId,
                error: error,
                setCookieHeader: setCookieHeader
            )
        }
        
        // Render family with HisKi citation in citation panel
        let html = HTMLRenderer.renderFamily(
            family: network.mainFamily,
            network: network,
            homeId: homeId,
            citationText: citationResult
        )
        
        var responseHeaders = HTTPHeaders()
        if let setCookieHeader {
            responseHeaders.add(name: "Set-Cookie", value: setCookieHeader)
        }
        
        return .html(html, headers: responseHeaders)
    }
    
    // MARK: - Helper Methods
    
    private func findPerson(name: String, birthDate: String?, in family: Family) -> Person? {
        logger.info(
            "[\(requestID!)] 🔍 Finding person",
            metadata: [
                "searchName": "\(name)",
                "searchBirthDate": "\(birthDate ?? "nil")"
            ]
        )
        
        // Search parents first
        for parent in family.allParents {
            logger.debug("[\(requestID!)]   Checking parent: '\(parent.name)' birth: '\(parent.birthDate ?? "nil")'")
            if matchesPerson(parent, name: name, birthDate: birthDate) {
                logger.info("[\(requestID!)] ✅ Found as parent: \(parent.displayName)")
                return parent
            }
        }
        
        // Search children
        for child in family.allChildren {
            logger.debug("[\(requestID!)]   Checking child: '\(child.name)' birth: '\(child.birthDate ?? "nil")'")
            if matchesPerson(child, name: name, birthDate: birthDate) {
                logger.info("[\(requestID!)] ✅ Found as child: \(child.displayName)")
                return child
            }
        }
        
        // Search spouses of children
        for couple in family.couples {
            for child in couple.children {
                if let spouseName = child.spouse {
                    logger.debug("[\(requestID!)]   Checking spouse: \(spouseName)")
                    if spouseName.lowercased() == name.lowercased() {
                        let spousePerson = Person(name: spouseName, noteMarkers: [])
                        logger.info("[\(requestID!)] ✅ Found as spouse: \(spouseName)")
                        return spousePerson
                    }
                }
            }
        }
        
        logger.warning("[\(requestID!)] ⚠️ Person not found: \(name)")
        return nil
    }
    
    private func matchesPerson(_ person: Person, name: String, birthDate: String?) -> Bool {
        // Name matching - exact match preferred
        let personNameLower = person.name.lowercased()
        let searchNameLower = name.lowercased()
        
        let nameMatches = personNameLower == searchNameLower ||
                          personNameLower.hasPrefix(searchNameLower) ||
                          searchNameLower.hasPrefix(personNameLower)
        
        guard nameMatches else { return false }
        
        // If birth date provided, verify it matches
        if let searchBirth = birthDate, let personBirth = person.birthDate {
            // Handle both full dates and year-only
            if personBirth == searchBirth {
                return true
            }
            // Extract years and compare
            let personYear = extractYear(from: personBirth)
            let searchYear = extractYear(from: searchBirth)
            if let py = personYear, let sy = searchYear {
                return py == sy
            }
            return personBirth.contains(searchBirth) || searchBirth.contains(personBirth)
        }
        
        return true
    }
    
    private func extractYear(from date: String) -> String? {
        let pattern = "\\b(1[6-9]\\d{2})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: date, range: NSRange(date.startIndex..., in: date)),
              let range = Range(match.range(at: 1), in: date) else {
            return nil
        }
        return String(date[range])
    }
    
    private func generateCitation(for person: Person, role: String?, network: FamilyNetwork) -> String {
        logger.info(
            "[\(requestID!)] 📝 Generating citation",
            metadata: [
                "person": "\(person.displayName)",
                "role": "\(role ?? "auto")"
            ]
        )
        
        let family = network.mainFamily
        
        // Determine role if not specified
        let isParent = family.allParents.contains { $0.name == person.name }
        let isChild = family.allChildren.contains { $0.name == person.name }
        
        logger.info(
            "[\(requestID!)] 👤 Person role detection",
            metadata: [
                "isParent": "\(isParent)",
                "isChild": "\(isChild)"
            ]
        )
        
        // Generate appropriate citation
        if isParent {
            // For parents, try to find their asChild family
            if let asChildFamily = network.getAsChildFamily(for: person) {
                logger.info("[\(requestID!)] 📄 Using asChild family: \(asChildFamily.familyId)")
                return CitationGenerator.generateAsChildCitation(
                    for: person,
                    in: asChildFamily,
                    network: network,
                    nameEquivalenceManager: nil
                )
            } else {
                logger.info("[\(requestID!)] 📄 No asChild family, using main family citation")
                return CitationGenerator.generateMainFamilyCitation(
                    family: family,
                    targetPerson: person,
                    network: network
                )
            }
        } else if isChild {
            logger.info("[\(requestID!)] 📄 Using main family citation for child")
            return CitationGenerator.generateMainFamilyCitation(
                family: family,
                targetPerson: person,
                network: network
            )
        } else {
            // Must be a spouse - try to find their asChild family
            if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: person) {
                logger.info("[\(requestID!)] 📄 Using spouse's asChild family: \(spouseAsChildFamily.familyId)")
                return CitationGenerator.generateAsChildCitation(
                    for: person,
                    in: spouseAsChildFamily,
                    network: network,
                    nameEquivalenceManager: nil
                )
            } else {
                logger.info("[\(requestID!)] 📄 No spouse asChild family, using main family citation")
                return CitationGenerator.generateMainFamilyCitation(
                    family: family,
                    targetPerson: person,
                    network: network
                )
            }
        }
    }
    
    private func renderFamilyWithError(
        network: FamilyNetwork,
        homeId: String?,
        error: String,
        setCookieHeader: String?
    ) -> HTTPResponse {
        let html = HTMLRenderer.renderFamily(
            family: network.mainFamily,
            network: network,
            homeId: homeId,
            errorMessage: error
        )
        
        var responseHeaders = HTTPHeaders()
        if let setCookieHeader {
            responseHeaders.add(name: "Set-Cookie", value: setCookieHeader)
        }
        
        return .html(html, headers: responseHeaders)
    }

    // MARK: - Response Writer (EventLoop only)

    private func send(
        _ response: HTTPResponse,
        on context: ChannelHandlerContext
    ) {
        switch response {

        case .html(let html, let status, let headers):
            sendHTML(context: context, html: html, status: status, headers: headers)

        case .redirect(let location, let headers):
            sendRedirect(context: context, location: location, headers: headers)

        case .error(let status, let message, let headers):
            sendError(context: context, status: status, message: message, headers: headers)
        }
    }

    private func sendHTML(
        context: ChannelHandlerContext,
        html: String,
        status: HTTPResponseStatus,
        headers: HTTPHeaders
    ) {
        var responseHeaders = headers
        responseHeaders.add(
            name: "Content-Type",
            value: "text/html; charset=utf-8"
        )
        responseHeaders.add(
            name: "Content-Length",
            value: String(html.utf8.count)
        )

        if isKeepAlive {
            responseHeaders.add(name: "Connection", value: "keep-alive")
        }

        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: responseHeaders
        )

        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var body =
            context.channel.allocator.buffer(
                capacity: html.utf8.count
            )
        body.writeString(html)

        context.write(
            wrapOutboundOut(.body(.byteBuffer(body))),
            promise: nil
        )

        context.writeAndFlush(
            wrapOutboundOut(.end(nil))
        ).whenComplete { _ in
            if !self.isKeepAlive {
                context.close(promise: nil)
            }
        }
    }

    private func sendRedirect(
        context: ChannelHandlerContext,
        location: String,
        headers: HTTPHeaders
    ) {
        var responseHeaders = headers
        responseHeaders.add(name: "Location", value: location)

        if isKeepAlive {
            responseHeaders.add(name: "Connection", value: "keep-alive")
        }

        let head = HTTPResponseHead(
            version: .http1_1,
            status: .seeOther,
            headers: responseHeaders
        )

        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            if !self.isKeepAlive {
                context.close(promise: nil)
            }
        }
    }

    private func sendError(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        message: String,
        headers: HTTPHeaders
    ) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Error</title></head>
        <body>
            <h1>Error \(status.code)</h1>
            <p>\(message)</p>
            <a href="/">Back to home</a>
        </body>
        </html>
        """
        sendHTML(context: context, html: html, status: status, headers: headers)
    }

    // MARK: - Utilities

    private func parseFormData(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = body.split(separator: "&")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                // Replace + with space to handle application/x-www-form-urlencoded format
                let rawValue = String(parts[1]).replacingOccurrences(of: "+", with: " ")
                let value = rawValue.removingPercentEncoding ?? rawValue
                result[key] = value
            }
        }
        return result
    }
}

#endif
