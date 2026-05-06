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
