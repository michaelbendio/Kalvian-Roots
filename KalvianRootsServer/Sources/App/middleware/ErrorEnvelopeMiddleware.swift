import Vapor

struct ErrorEnvelopeMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let abort as AbortError {
            let envelope = ErrorEnvelope.make(code: abort.reason, message: abort.reason)
            var response = Response(status: abort.status)
            try response.content.encode(envelope)
            return response
        } catch {
            request.logger.report(error: error)
            let envelope = ErrorEnvelope.make(code: "internal_error",
                                              message: "Unexpected error.")
            var response = Response(status: .internalServerError)
            try response.content.encode(envelope)
            return response
        }
    }
}

struct ErrorEnvelope: Content {
    struct Body: Content {
        let code: String
        let message: String
    }

    let error: Body

    static func make(code: String, message: String) -> ErrorEnvelope {
        .init(error: .init(code: code, message: message))
    }
}
