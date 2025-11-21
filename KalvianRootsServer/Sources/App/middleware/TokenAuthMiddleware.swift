import Vapor

struct TokenAuthMiddleware: Middleware {
    let expectedToken: String

    func respond(to req: Request, chainingTo next: Responder) async throws -> Response {
        guard !expectedToken.isEmpty else { return try await next.respond(to: req) }

        let provided = req.headers.bearerAuthorization?.token ?? ""
        guard provided == expectedToken else {
            let env = ErrorEnvelope.make(code: "unauthorized", message: "Invalid or missing token.")
            let res = Response(status: .unauthorized)
            try res.content.encode(env)
            return res
        }

        return try await next.respond(to: req)
    }
}
