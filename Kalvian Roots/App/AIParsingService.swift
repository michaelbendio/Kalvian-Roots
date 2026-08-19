import Foundation
import KalvianRootsCore

@Observable
final class AIParsingService {
    private let service: AIService

    var isConfigured: Bool { service.isConfigured }
    var currentServiceName: String { service.name }

    init() {
        let service = DeepSeekService()
        self.service = service
        logInfo(.ai, "Using hosted AI service: \(service.name)")
    }

    init(service: AIService) {
        self.service = service
    }

    func configure(apiKey: String) throws {
        try service.configure(apiKey: apiKey)
    }

    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        guard isConfigured else {
            throw AIServiceError.notConfigured(service.name)
        }

        do {
            let response = try await service.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            return try FamilyJSONDecoder.decode(response, expectedFamilyId: familyId)
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw AIServiceError.parsingFailed(error.localizedDescription)
        }
    }
}
