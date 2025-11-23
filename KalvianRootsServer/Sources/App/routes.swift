import Foundation
import Vapor

public func routes(_ app: Application, apiGroup: RoutesBuilder) throws {

    // MARK: - Public Endpoints

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

    // MARK: - Jobs

    let jobs = apiGroup.grouped("jobs")

    jobs.post("extraction") { req async throws -> JobState in
        let store = req.application.storage[InMemoryJobStore.Key.self]!
        let job = await store.create(type: "extraction")

        // Kick off background work
        Task.detached { [app = req.application] in
            // Mark as running
            await store.update(id: job.id) { state in
                state.status = .running
                state.progress = 0.0
                state.message = "Starting extraction"
            }
            app.logger.info("🚀 Extraction task started for job \(job.id)")

            do {
                let service = RootsExtractionService(app: app)
                let result = try await service.runExtraction()

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                let jsonString = String(data: data, encoding: .utf8)

                await store.update(id: job.id) { state in
                    state.status = .completed
                    state.progress = 1.0
                    state.message = "Extraction completed"
                    state.resultJSON = jsonString
                }
                app.logger.info("✅ Extraction task completed for job \(job.id)")
            } catch {
                await store.update(id: job.id) { state in
                    state.status = .failed
                    state.progress = 1.0
                    state.message = "Extraction failed"
                    state.errorMessage = String(describing: error)
                }
                app.logger.error("❌ Extraction task failed for job \(job.id): \(error)")
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

    // MARK: - Debug: Roots File Info

    let debug = apiGroup.grouped("debug")

    debug.get("roots-info") { req async throws -> RootsInfoResponse in
        guard let rootsEnv = req.application.roots else {
            return RootsInfoResponse(
                configuredPath: nil,
                exists: false,
                isDirectory: false,
                fileSizeBytes: nil,
                lastModified: nil,
                familyCount: nil
            )
        }

        let path = rootsEnv.rootsPath
        let fm = FileManager.default

        var isDirObj: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDirObj)

        var size: Int64? = nil
        var modified: Date? = nil

        if exists {
            if let attrs = try? fm.attributesOfItem(atPath: path) {
                if let n = attrs[.size] as? NSNumber {
                    size = n.int64Value
                }
                if let d = attrs[.modificationDate] as? Date {
                    modified = d
                }
            }
        }

        return RootsInfoResponse(
            configuredPath: path,
            exists: exists,
            isDirectory: isDirObj.boolValue,
            fileSizeBytes: size,
            lastModified: modified,
            familyCount: nil // Will fill in later when Roots parser is integrated
        )
    }
}

// MARK: - Response Models

struct StatusResponse: Content {
    let status: String
    let build: String
    let commit: String
    let uptimeSeconds: Int
}

struct RootsInfoResponse: Content {
    let configuredPath: String?
    let exists: Bool
    let isDirectory: Bool
    let fileSizeBytes: Int64?
    let lastModified: Date?
    let familyCount: Int?
}
