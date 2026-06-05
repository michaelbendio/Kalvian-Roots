//
//  AIParsingServiceTests.swift
//  Kalvian Roots Tests
//
//  Comprehensive test coverage for AIParsingService
//

import XCTest
@testable import Kalvian_Roots

@MainActor
final class AIParsingServiceTests: XCTestCase {
    
    var service: AIParsingService!
    private let apiKeyStorageKey = "AIService_DeepSeek_APIKey"
    private var savedAPIKey: String?
    
    override func setUp() async throws {
        try await super.setUp()

        let defaults = UserDefaults.standard
        savedAPIKey = defaults.string(forKey: apiKeyStorageKey)
        defaults.removeObject(forKey: apiKeyStorageKey)

        service = AIParsingService()
    }
    
    override func tearDown() async throws {
        let defaults = UserDefaults.standard
        if let savedAPIKey {
            defaults.set(savedAPIKey, forKey: apiKeyStorageKey)
        } else {
            defaults.removeObject(forKey: apiKeyStorageKey)
        }

        service = nil
        savedAPIKey = nil

        try await super.tearDown()
    }
    
    // MARK: - Service Configuration Tests
    
    func testServiceInitialization() {
        XCTAssertNotNil(service, "Service should initialize")
        XCTAssertFalse(service.isConfigured, "Service should not be configured without API key")
    }
    
    func testServiceConfiguration() throws {
        // When: Setting an API key
        try service.configure(apiKey: "test-api-key")
        
        // Then: Service should be configured
        XCTAssertTrue(service.isConfigured, "Service should be configured with API key")
        XCTAssertEqual(service.currentServiceName, "DeepSeek", "Should use DeepSeek by default")
    }
    
    func testMultipleServiceTypes() throws {
        // Test: Service can handle different AI providers
        try service.configure(apiKey: "deepseek-key")
        XCTAssertTrue(service.isConfigured, "Should configure DeepSeek")
        
        // Note: MLX services would be tested separately as they don't require API keys
    }
    
    func testEmptyAPIKeyDoesNotConfigure() {
        // When: Setting empty API key
        XCTAssertThrowsError(try service.configure(apiKey: "")) { error in
            guard case AIServiceError.apiKeyMissing = error else {
                XCTFail("Expected apiKeyMissing, got \(error)")
                return
            }
        }
        
        // Then: Service should not be configured
        XCTAssertFalse(service.isConfigured, "Empty API key should not configure service")
    }
    
    // MARK: - Family Parsing Tests (Would require integration mode)
    
    func testParseFamilyRequiresConfiguration() async {
        // Given: Unconfigured service
        XCTAssertFalse(service.isConfigured, "Service should not be configured")
        
        // When/Then: Attempting to parse should fail appropriately
        // (Actual parsing would require integration test mode)
    }
    
    func testParseFamilyWithValidInput() async {
        // Integration test - would require RUN_INTEGRATION_TESTS=1
        // Test parsing actual family text and validating structure
    }
    
    func testParseFamilyHandlesInvalidJSON() async {
        // Integration test - would test error handling for malformed responses
    }
    
    // MARK: - Service Name Tests
    
    func testCurrentServiceName() {
        XCTAssertEqual(service.currentServiceName, "DeepSeek", "Default service should be DeepSeek")
    }

    func testPromptIgnoresSyntOriginPhrases() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let aiServicesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/App/AIServices.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(aiServicesSource.contains(#"Ignore origin-place phrases beginning with "synt.":"#))
        XCTAssertTrue(aiServicesSource.contains(#""synt. Veteli" means the person was originally from Veteli"#))
        XCTAssertTrue(aiServicesSource.contains(#"Do NOT store "synt." text in notes, coupleNotes, deathDate, spouse, asChild, or asParent"#))
    }

    func testParsedFamilySuppressesSyntOriginPhrasesFromModelOutput() async throws {
        let service = AIParsingService(service: MockAIService(response: """
        {
          "familyId": "TIKKANEN 6",
          "pageReferences": ["240", "241"],
          "couples": [
            {
              "husband": {
                "name": "Erik",
                "patronymic": "Juhonp.",
                "birthDate": "1716",
                "deathDate": "27.02.1797 synt. Veteli",
                "asChild": "Tikkanen 4 synt. Veteli",
                "familySearchId": "K2YQ-1ZY",
                "noteMarkers": []
              },
              "wife": {
                "name": "Maria",
                "patronymic": "Martint.",
                "birthDate": "02.06.1735",
                "deathDate": null,
                "asChild": "synt. Lohtaja",
                "familySearchId": "K8CD-718",
                "noteMarkers": []
              },
              "marriageDate": "53",
              "fullMarriageDate": "27.11.1753",
              "children": [
                {
                  "name": "Matti",
                  "birthDate": "14.03.1756",
                  "deathDate": null,
                  "marriageDate": "79",
                  "spouse": "Kaarin Bjömheim synt. Veteli",
                  "asParent": "Tikkanen II 1 synt. Veteli",
                  "familySearchId": "LHH6-W2P",
                  "spouseFamilySearchId": "K8JR-2W8",
                  "noteMarkers": []
                }
              ],
              "childrenDiedInfancy": null,
              "coupleNotes": ["synt. Lohtaja"]
            }
          ],
          "notes": ["synt. Veteli", "Lapsena kuollut 6."],
          "noteDefinitions": {"*": "synt. Lohtaja", "**": "real note"}
        }
        """))

        let family = try await service.parseFamily(familyId: "TIKKANEN 6", familyText: "ignored")

        XCTAssertEqual(family.notes, ["Lapsena kuollut 6."])
        XCTAssertEqual(family.noteDefinitions, ["**": "real note"])
        XCTAssertEqual(family.primaryCouple?.coupleNotes, [])
        XCTAssertEqual(family.primaryCouple?.husband.deathDate, "27.02.1797")
        XCTAssertEqual(family.primaryCouple?.husband.asChild, "Tikkanen 4")
        XCTAssertNil(family.primaryCouple?.wife.asChild)
        XCTAssertEqual(family.primaryCouple?.children.first?.spouse, "Kaarin Bjömheim")
        XCTAssertEqual(family.primaryCouple?.children.first?.spouseFamilySearchId, "K8JR-2W8")
        XCTAssertEqual(family.primaryCouple?.children.first?.asParent, "Tikkanen II 1")
    }

    func testPromptRequestsChildSpouseFamilySearchIdSeparatelyFromChildId() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let aiServicesSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Kalvian Roots/App/AIServices.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(aiServicesSource.contains(#""spouseFamilySearchId": "string or null (spouse's <ID> after spouse name)""#))
    }
    
    func testServiceNameAfterConfiguration() throws {
        try service.configure(apiKey: "test-key")
        XCTAssertEqual(service.currentServiceName, "DeepSeek", "Service name should match configured service")
    }
    
    // MARK: - Error Handling Tests
    
    func testParseWithoutAPIKeyFails() async {
        // Given: No API key set
        XCTAssertFalse(service.isConfigured)
        
        // When/Then: Parse should fail with appropriate error
        // (Would be tested in integration mode)
    }
    
    func testParseWithInvalidFamilyText() async {
        // Integration test - would test handling of invalid input
    }
    
    func testParseWithNetworkError() async {
        // Integration test - would test network error handling
    }
    
    // MARK: - API Key Management Tests
    
    func testAPIKeyCanBeChanged() throws {
        // When: Setting initial key
        try service.configure(apiKey: "key1")
        XCTAssertTrue(service.isConfigured)
        
        // When: Changing key
        try service.configure(apiKey: "key2")
        
        // Then: Service should remain configured
        XCTAssertTrue(service.isConfigured, "Service should remain configured with new key")
    }
    
    func testEmptyAPIKeyDoesNotClearExistingConfiguration() throws {
        // Given: Configured service
        try service.configure(apiKey: "test-key")
        XCTAssertTrue(service.isConfigured)
        
        // When: Attempting to configure with an empty key
        XCTAssertThrowsError(try service.configure(apiKey: "")) { error in
            guard case AIServiceError.apiKeyMissing = error else {
                XCTFail("Expected apiKeyMissing, got \(error)")
                return
            }
        }
        
        // Then: Existing configuration remains intact; the app has no clear-key API.
        XCTAssertTrue(service.isConfigured, "Empty key should not clear an existing configuration")
    }
}

private final class MockAIService: AIService {
    let name = "Mock"
    var isConfigured: Bool { true }
    private let response: String

    init(response: String) {
        self.response = response
    }

    func configure(apiKey: String) throws {}

    func parseFamily(familyId: String, familyText: String) async throws -> String {
        response
    }
}
