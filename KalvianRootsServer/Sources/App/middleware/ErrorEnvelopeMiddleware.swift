import Vapor

struct ErrorEnvelopeMiddleware: Middleware {
    func respond(to req: Request, chainingTo next: Responder) async throws -> Response {
        do { return try await next.respond(to: req) }
        catch let abort as AbortError {
            let env = ErrorEnvelope.make(code: abort.reason, message: abort.reason)
            let res = Response(status: abort.status)
            try res.content.encode(env)
            return res
        }
        catch {
            req.logger.report(error: error)
            let env = ErrorEnvelope.make(code: "internal_error", message: "Unexpected error.")
            let res = Response(status: .internalServerError)
            try res.content.encode(env)
            return res
        }
    }
}

struct ErrorEnvelope: Content {
    struct Err: Content { let code: String; let message: String }
    let error: Err
    static func make(code: String, message: String) -> ErrorEnvelope {
        .init(error: .init(code: code, message: message))
    }
}
