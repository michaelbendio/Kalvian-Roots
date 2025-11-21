import Vapor

struct RequestIDMiddleware: Middleware {
    private let key = "X-Request-Id"

    func respond(to req: Request, chainingTo next: Responder) async throws -> Response {
        let id = req.headers.first(name: key) ?? UUID().uuidString
        req.headers.replaceOrAdd(name: key, value: id)
        req.logger[metadataKey: "request_id"] = .string(id)

        let res = try await next.respond(to: req)
        res.headers.replaceOrAdd(name: key, value: id)
        return res
    }
}
