import Foundation

// Minimal stub for removed MLX local execution support
class MLXService: AIService {
    let name: String
    var isConfigured: Bool { false }

    init(name: String) {
        self.name = name
    }

    func configure(apiKey: String) throws {}

    func parseFamily(familyId: String, familyText: String) async throws -> String {
        throw AIServiceError.notConfigured("MLX is not available")
    }

    static func isAvailable() -> Bool { false }

    static func qwen3_30B() throws -> MLXService { MLXService(name: "MLX Qwen3-30B (Local)") }
    static func qwen2_5_14B() throws -> MLXService { MLXService(name: "MLX Qwen2.5-14B (Local)") }
    static func llama3_1_8B() throws -> MLXService { MLXService(name: "MLX Llama-3.1-8B (Local)") }

    static func getRecommendedModel() -> MLXService? { nil }
}

// Minimal stub for MLX server coordination
class MLXServerManager {
    struct ServerStatus {
        var isReady: Bool
    }

    var serverStatus = ServerStatus(isReady: true)
    var currentModel: String?
    var queuedExtractions: [String] = []

    func getDefaultModel() -> String { currentModel ?? "" }

    func startServer(modelName: String) async throws {
        currentModel = modelName
        serverStatus.isReady = true
    }

    func switchModel(to modelName: String) async throws {
        currentModel = modelName
        serverStatus.isReady = true
    }

    func queueExtraction(_ familyId: String) {
        queuedExtractions.append(familyId)
    }

    func clearQueue() {
        queuedExtractions.removeAll()
    }
}

// Minimal stub for mock AI service
class MockAIService: AIService {
    let name = "Mock AI"
    var isConfigured: Bool { true }

    func configure(apiKey: String) throws {}

    func parseFamily(familyId: String, familyText: String) async throws -> String {
        return "{}"
    }
}
