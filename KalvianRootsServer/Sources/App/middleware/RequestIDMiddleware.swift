import Vapor

struct RequestIDMiddleware: AsyncMiddleware {
    private let headerName = "X-Request-Id"

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Generate or reuse a request ID
        let id = request.headers.first(name: headerName) ?? UUID().uuidString
        request.headers.replaceOrAdd(name: headerName, value: id)
        request.logger[metadataKey: "request_id"] = .string(id)

        // Call the next responder in the chain
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: headerName, value: id)
        return response
    }
}
