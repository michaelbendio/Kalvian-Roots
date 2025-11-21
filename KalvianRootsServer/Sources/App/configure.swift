import Vapor

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

    try routes(app, apiGroup: api)
}
