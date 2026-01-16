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
    private var channel: Channel?
    private let port: Int
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    // MARK: - Initialization

    init(juuretApp: JuuretApp, port: Int) {
        self.juuretApp = juuretApp
        self.port = port
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
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPHandler(juuretApp: juuretApp))
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
        case html(String, status: HTTPResponseStatus = .ok)
        case redirect(String)
        case error(HTTPResponseStatus, String)
    }

    // MARK: - State

    private weak var juuretApp: JuuretApp?

    private var buffer = ByteBuffer()
    private var requestURI: String?
    private var requestMethod: HTTPMethod?
    private var requestBody: String?
    private var isKeepAlive = false
    private var requestID: UUID?

    private let logger = Logger(label: "KalvianRoots.HTTP")

    // MARK: - Init

    init(juuretApp: JuuretApp) {
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

        logger.debug(
            "[\(requestID!)] Routing",
            metadata: [
                "method": "\(method)",
                "path": "\(path)"
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

        switch (method, path) {

        case (.GET, "/"):
            let error = queryItems.first(where: { $0.name == "error" })?.value
            let html = HTMLRenderer.renderLandingPage(error: error)
            return .html(html)

        case (.POST, "/"):
            return handleLandingPagePost()

        case (.GET, let p) where p.starts(with: "/family/"):
            return try await handleFamilyRoute(path: p)

        default:
            return .error(.notFound, "Not Found")
        }
    }

    // MARK: - Route Handlers (MainActor)

    @MainActor
    private func handleLandingPagePost() -> HTTPResponse {
        guard let body = requestBody,
              let familyId = parseFormData(body)["family"] else {
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
    private func handleFamilyRoute(path: String) async throws -> HTTPResponse {
        guard let juuretApp = juuretApp else {
            return .error(.internalServerError, "App not available")
        }

        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else {
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
            "[\(requestID!)] Family ID from path",
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

        // Deterministic await — no Task.sleep
        try await juuretApp.extractFamilyAndWait(familyId: canonicalID)

        guard let family = juuretApp.currentFamily,
              let network =
                juuretApp.familyNetworkWorkflow?.getFamilyNetwork() else {
            return .error(.notFound, "Family not found")
        }

        let html =
            HTMLRenderer.renderFamily(
                family: family,
                network: network
            )

        return .html(html)
    }

    // MARK: - Response Writer (EventLoop only)

    private func send(
        _ response: HTTPResponse,
        on context: ChannelHandlerContext
    ) {
        switch response {

        case .html(let html, let status):
            sendHTML(context: context, html: html, status: status)

        case .redirect(let location):
            sendRedirect(context: context, location: location)

        case .error(let status, let message):
            sendError(context: context, status: status, message: message)
        }
    }

    private func sendHTML(
        context: ChannelHandlerContext,
        html: String,
        status: HTTPResponseStatus
    ) {
        var headers = HTTPHeaders()
        headers.add(
            name: "Content-Type",
            value: "text/html; charset=utf-8"
        )
        headers.add(
            name: "Content-Length",
            value: String(html.utf8.count)
        )

        if isKeepAlive {
            headers.add(name: "Connection", value: "keep-alive")
        }

        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: headers
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
        location: String
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Location", value: location)

        if isKeepAlive {
            headers.add(name: "Connection", value: "keep-alive")
        }

        let head = HTTPResponseHead(
            version: .http1_1,
            status: .found,
            headers: headers
        )

        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(
            wrapOutboundOut(.end(nil))
        ).whenComplete { _ in
            if !self.isKeepAlive {
                context.close(promise: nil)
            }
        }
    }

    private func sendError(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        message: String
    ) {
        let html = """
        <!DOCTYPE html>
        <html>
        <body>
            <h1>Error \(status.code)</h1>
            <p>\(message)</p>
        </body>
        </html>
        """
        sendHTML(context: context, html: html, status: status)
    }

    // MARK: - Utilities

    private func parseFormData(_ data: String) -> [String: String] {
        // HTML form encoding: '+' represents space
        let normalized = data.replacingOccurrences(of: "+", with: " ")

        var components = URLComponents()
        components.query = normalized

        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}



// MARK: - FamilyNetwork Extension

extension FamilyNetwork {
    func getAllPersons() -> [Person] {
        var persons: [Person] = []

        // Add persons from main family
        persons.append(contentsOf: mainFamily.allParents)
        persons.append(contentsOf: mainFamily.allChildren)

        // Add persons from asChild families
        for family in asChildFamilies.values {
            persons.append(contentsOf: family.allParents)
            persons.append(contentsOf: family.allChildren)
        }

        // Add persons from asParent families
        for family in asParentFamilies.values {
            persons.append(contentsOf: family.allParents)
            persons.append(contentsOf: family.allChildren)
        }

        // Remove duplicates based on name and birth date
        var uniquePersons: [Person] = []
        var seen: Set<String> = []

        for person in persons {
            let key = "\(person.name)-\(person.birthDate ?? "")"
            if !seen.contains(key) {
                seen.insert(key)
                uniquePersons.append(person)
            }
        }

        return uniquePersons
    }
}

#endif // os(macOS)
