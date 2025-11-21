import Vapor

public func routes(_ app: Application, apiGroup: RoutesBuilder) throws {

    // Public
    app.get("health") { _ async -> [String:String] in
        ["status": "ok"]
    }

    app.get("status") { req async -> StatusResponse in
        StatusResponse(
            status: "ok",
            build: Environment.get("KALVIAN_BUILD") ?? "dev",
            commit: Environment.get("KALVIAN_COMMIT") ?? "local",
            uptimeSeconds: Int(ProcessInfo.processInfo.systemUptime)
        )
    }

    // Jobs
    let jobs = apiGroup.grouped("jobs")

    jobs.post("extraction") { req async throws -> JobState in
        let store = req.application.storage[InMemoryJobStore.Key.self]!
        let job = await store.create(type: "extraction")

        // placeholder async task
        Task.detached {
            await store.update(id: job.id) { $0.status = .running }
            // TODO integrate Core + MLX
            await store.update(id: job.id) { state in
                state.status = .completed
                state.progress = 1.0
                state.message = "Extraction completed"
            }
        }

        return job
    }

    jobs.get(":id") { req async throws -> JobState in
        let store = req.application.storage[InMemoryJobStore.Key.self]!
        guard
            let idString = req.parameters.get("id"),
            let uuid = UUID(uuidString: idString),
            let job = await store.get(id: uuid)
        else {
            throw Abort(.notFound, reason: "Job not found")
        }
        return job
    }
}

struct StatusResponse: Content {
    let status: String
    let build: String
    let commit: String
    let uptimeSeconds: Int
}
