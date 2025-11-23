import Vapor

struct TokenAuthMiddleware: AsyncMiddleware {
    let expectedToken: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // If no token is configured, treat auth as disabled (useful for local dev)
        if expectedToken.isEmpty {
            return try await next.respond(to: request)
        }

        let provided = request.headers.bearerAuthorization?.token ?? ""
        guard provided == expectedToken else {
            let envelope = ErrorEnvelope.make(
                code: "unauthorized",
                message: "Invalid or missing token."
            )
            var response = Response(status: .unauthorized)
            try response.content.encode(envelope)
            return response
        }

        // Token OK → continue down the chain
        return try await next.respond(to: request)
    }
}
