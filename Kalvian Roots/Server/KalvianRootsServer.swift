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

final class HTTPHandler: ChannelInboundHandler {

    // MARK: - NIO Types

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    // MARK: - Response Model (transport-level)

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

    // MARK: - Init

    init(juuretApp: JuuretApp) {
        self.juuretApp = juuretApp
    }

    // MARK: - ChannelInboundHandler

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {

        case .head(let request):
            requestURI = request.uri
            requestMethod = request.method
            isKeepAlive = request.isKeepAlive
            buffer.clear()
            requestBody = nil

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

        let eventLoop = context.eventLoop

        // Hop to MainActor ONLY to touch app state
        Task { @MainActor in
            let response: HTTPResponse

            do {
                response = try await handleRoute(
                    method: method,
                    path: path,
                    queryItems: queryItems
                )
            } catch {
                response = .error(
                    .internalServerError,
                    "Server error: \(error)"
                )
            }

            // Hop back to NIO EventLoop for socket writes
            eventLoop.execute {
                self.send(response, on: context)
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
            return try await handleFamilyRoute(
                path: p,
                queryItems: queryItems
            )

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

        let normalizedId = familyId
            .uppercased()
            .trimmingCharacters(in: .whitespaces)

        if FamilyIDs.isValid(familyId: normalizedId) {
            let encoded =
                normalizedId.addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed
                ) ?? normalizedId
            return .redirect("/family/\(encoded)")
        } else {
            return .redirect("/?error=invalid")
        }
    }

    @MainActor
    private func handleFamilyRoute(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> HTTPResponse {

        guard let juuretApp = juuretApp else {
            return .error(.internalServerError, "App not available")
        }

        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2 else {
            return .error(.notFound, "Not Found")
        }

        let familyId = components[1]

        guard FamilyIDs.isValid(familyId: familyId) else {
            return .redirect("/?error=invalid")
        }

        if juuretApp.currentFamily?.familyId != familyId {
            await juuretApp.extractFamily(familyId: familyId)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

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

        var bodyBuffer =
            context.channel.allocator.buffer(
                capacity: html.utf8.count
            )
        bodyBuffer.writeString(html)

        context.write(
            wrapOutboundOut(.body(.byteBuffer(bodyBuffer))),
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
        <head>
            <title>Error</title>
            <style>
                body {
                    font-family: system-ui, -apple-system, sans-serif;
                    padding: 20px;
                }
                .error {
                    color: #dc3545;
                    margin-top: 20px;
                }
            </style>
        </head>
        <body>
            <h1>Error \(status.code)</h1>
            <div class="error">\(message)</div>
        </body>
        </html>
        """
        sendHTML(context: context, html: html, status: status)
    }

    // MARK: - Utilities (pure)

    private func parseFormData(_ data: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = data.split(separator: "&")

        for pair in pairs {
            let components = pair.split(
                separator: "=",
                maxSplits: 1
            )
            if components.count == 2 {
                let key =
                    String(components[0])
                        .removingPercentEncoding
                    ?? String(components[0])
                let value =
                    String(components[1])
                        .removingPercentEncoding
                    ?? String(components[1])
                result[key] = value
            }
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
