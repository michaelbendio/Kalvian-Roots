import Foundation
import KalvianRootsCore

protocol AIService {
    var name: String { get }
    var isConfigured: Bool { get }
    func configure(apiKey: String) throws
    func parseFamily(familyId: String, familyText: String) async throws -> String
}

final class DeepSeekService: AIService {
    let name = "DeepSeek"
    private let storageKey = "AIService_DeepSeek_APIKey"
    private var apiKey: String?

    init() {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        apiKey = stored?.isEmpty == false ? stored : nil
    }

    var isConfigured: Bool { apiKey?.isEmpty == false }

    func configure(apiKey: String) throws {
        guard !apiKey.isEmpty else { throw AIServiceError.apiKeyMissing }
        self.apiKey = apiKey
        UserDefaults.standard.set(apiKey, forKey: storageKey)
    }

    func parseFamily(familyId: String, familyText: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw AIServiceError.notConfigured("DeepSeek API key not configured")
        }
        return try await DeepSeekFamilyClient(
            credentials: FixedDeepSeekCredential(apiKey: apiKey)
        ).parseFamily(familyId: familyId, familyText: familyText)
    }
}

private struct FixedDeepSeekCredential: DeepSeekCredentialProviding {
    let apiKeyValue: String

    init(apiKey: String) {
        apiKeyValue = apiKey
    }

    func apiKey() throws -> String { apiKeyValue }
}
