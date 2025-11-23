import Vapor
import Foundation

public func configure(_ app: Application) throws {
    // Localhost binding
    app.http.server.configuration.hostname = "127.0.0.1"
    app.http.server.configuration.port = 8081

    // Middlewares
    app.middleware.use(RequestIDMiddleware())
    app.middleware.use(ErrorEnvelopeMiddleware())

    // Token for /api/* routes
    let token = Environment.get("KALVIAN_API_TOKEN") ?? ""
    let api = app.grouped("api").grouped(TokenAuthMiddleware(expectedToken: token))

    // Shared in-memory stores
    app.storage[InMemoryJobStore.Key.self] = InMemoryJobStore()
    app.storage[InMemoryLockStore.Key.self] = InMemoryLockStore()

    // ROOTS_FILE wiring
    if let rootsPath = Environment.get("ROOTS_FILE"), !rootsPath.isEmpty {
        app.logger.info("ROOTS_FILE set to: \(rootsPath)")
        app.roots = RootsEnvironment(rootsPath: rootsPath)
    } else {
        app.logger.warning("ROOTS_FILE is not set; server will run without roots data.")
        app.roots = nil
    }

    try routes(app, apiGroup: api)
}
