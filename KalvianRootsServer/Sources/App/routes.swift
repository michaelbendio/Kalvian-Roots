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

        Task.detached { [app = req.application] in
            await store.update(id: job.id) {
                $0.status = .running
                $0.progress = 0.0
                $0.message = "Starting extraction"
            }

            app.logger.info("🚀 Extraction task started for job \(job.id)")

            do {
                let service = RootsExtractionService(app: app)
                let result = try await service.runExtraction()

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                let jsonString = String(data: data, encoding: .utf8)

                await store.update(id: job.id) {
                    $0.status = .completed
                    $0.progress = 1.0
                    $0.message = "Extraction completed"
                    $0.resultJSON = jsonString
                }

                app.logger.info("✅ Extraction task completed for job \(job.id)")
            } catch {
                await store.update(id: job.id) {
                    $0.status = .failed
                    $0.progress = 1.0
                    $0.message = "Extraction failed"
                    $0.errorMessage = String(describing: error)
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
                if let n = attrs[.size] as? NSNumber { size = n.int64Value }
                if let d = attrs[.modificationDate] as? Date { modified = d }
            }
        }

        return RootsInfoResponse(
            configuredPath: path,
            exists: exists,
            isDirectory: isDirObj.boolValue,
            fileSizeBytes: size,
            lastModified: modified,
            familyCount: nil
        )
    }

    // MARK: - Families

    let families = apiGroup.grouped("families")

    families.get(":id") { req async throws -> RootsFamilyLookupService.FamilyResponse in
        guard let familyID = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Family ID is required.")
        }

        let service = RootsFamilyLookupService(app: req.application)
        let response = try await service.findFamily(id: familyID)

        await req.application.coreState.displayFamily(
            id: familyID,
            rawText: response.text
        )

        return response
    }

    // MARK: - Citations ✅ FIXED

    let citations = apiGroup.grouped("citation")

    citations.post { req async throws -> CitationPayload in

        struct CitationRequest: Content {
            let name: String
            let birth: String
        }

        let body = try req.content.decode(CitationRequest.self)
        let core = req.application.coreState

        let citationText = try await core.generateCitation(
            personName: body.name,
            birth: body.birth
        )

        return CitationPayload(
            citation: citationText
        )
    }

    // MARK: - Cache and Processing State ✅ FIXED ORDER

    let cacheGroup = apiGroup.grouped("cache")

    cacheGroup.get("status") { req async throws -> CacheStatusResponse in
        await req.application.coreState.statusForCurrentFamily()
    }

    cacheGroup.get("list") { req async throws -> [String : [String]] in
        await req.application.coreState.groupedCacheList()
    }

    cacheGroup.post("remove") { req async throws -> HTTPStatus in
        struct RemoveRequest: Content { let id: String }
        let body = try req.content.decode(RemoveRequest.self)
        await req.application.coreState.removeFamily(id: body.id)
        return .ok
    }

    cacheGroup.post("clear-all") { req async throws -> HTTPStatus in
        let allowedHosts = ["127.0.0.1", "::1", "localhost"]
        let remoteHost = req.remoteAddress?.ipAddress ?? req.remoteAddress?.hostname ?? ""

        guard allowedHosts.contains(remoteHost) else {
            throw Abort(.forbidden, reason: "Cache clear is only available on localhost.")
        }

        await req.application.coreState.clearAllFamilies()
        return .ok
    }

    // MARK: - AI Model Selection

    let aiGroup = apiGroup.grouped("ai")

    aiGroup.get("model") { req async throws -> AIModelResponse in
        AIModelResponse(model: await req.application.coreState.getSelectedModel())
    }

    aiGroup.post("model") { req async throws -> AIModelResponse in
        struct ModelRequest: Content { let model: String }
        let body = try req.content.decode(ModelRequest.self)
        await req.application.coreState.updateModel(body.model)
        return AIModelResponse(model: await req.application.coreState.getSelectedModel())
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

struct AIModelResponse: Content {
    let model: String
}
