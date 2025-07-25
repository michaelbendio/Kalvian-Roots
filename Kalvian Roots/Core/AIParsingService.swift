//
//  AIParsingService.swift
//  Kalvian Roots
//
//  Updated for JSON parsing instead of Swift struct parsing
//

import Foundation

/**
 * AIParsingService.swift - JSON-based AI parsing with detailed tracing
 *
 * Orchestrates AI family extraction with JSON parsing (replacing custom struct parsing)
 * Much more robust and reliable than the previous Swift struct approach.
 */

@Observable
class AIParsingService {
    
    // MARK: - Properties
    
    private var currentAIService: AIService
    private let availableServices: [AIService]
    
    var currentServiceName: String {
        currentAIService.name
    }
    
    var availableServiceNames: [String] {
        availableServices.map { $0.name }
    }
    
    var isConfigured: Bool {
        let configured = currentAIService.isConfigured
        logTrace(.ai, "AIParsingService isConfigured: \(configured) (\(currentServiceName))")
        return configured
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.ai, "🚀 AIParsingService initialization started")
        
        let mockService = MockAIService()
        let openAIService = OpenAIService()
        let claudeService = ClaudeService()
        let deepSeekService = DeepSeekService()
        
        self.availableServices = [deepSeekService, mockService, openAIService, claudeService]
        self.currentAIService = deepSeekService // Start with DeepSeek as primary
        
        logInfo(.ai, "✅ AIParsingService initialized")
        logDebug(.ai, "Available services: \(availableServiceNames.joined(separator: ", "))")
        logInfo(.ai, "Primary service: \(currentServiceName)")
        
        // Try to auto-configure from saved settings
        autoConfigureServices()
    }
    
    // MARK: - Service Management (Unchanged)
    
    /**
     * Switch to a different AI service by name
     */
    func switchToService(named serviceName: String) throws {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        guard let service = availableServices.first(where: { $0.name == serviceName }) else {
            logError(.ai, "❌ Service '\(serviceName)' not found")
            throw AIServiceError.notConfigured("Service '\(serviceName)' not found")
        }
        
        currentAIService = service
        logInfo(.ai, "✅ Successfully switched to: \(serviceName)")
        logDebug(.ai, "New service configured: \(service.isConfigured)")
    }
    
    /**
     * Configure the current AI service with an API key
     */
    func configureCurrentService(apiKey: String) throws {
        logInfo(.ai, "🔧 Configuring \(currentAIService.name) with API key")
        logTrace(.ai, "API key provided with length: \(apiKey.count)")
        
        try currentAIService.configure(apiKey: apiKey)
        
        // Save to UserDefaults for persistence
        saveAPIKey(apiKey, for: currentAIService.name)
        
        logInfo(.ai, "✅ Successfully configured \(currentAIService.name)")
    }
    
    /**
     * Get all available services with their configuration status
     */
    func getServiceStatus() -> [(name: String, configured: Bool)] {
        let status = availableServices.map { (name: $0.name, configured: $0.isConfigured) }
        logTrace(.ai, "Service status requested: \(status.map { "\($0.name)=\($0.configured)" }.joined(separator: ", "))")
        return status
    }
    
    // MARK: - Family Parsing (Updated for JSON)
    
    /**
     * Parse a family from genealogical text using JSON parsing
     *
     * This is the main entry point for AI-based family extraction with JSON parsing
     */
    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        logInfo(.parsing, "🤖 Starting JSON-based AI family parsing for: \(familyId)")
        logDebug(.parsing, "Using AI service: \(currentAIService.name)")
        logDebug(.parsing, "Family text length: \(familyText.count) characters")
        logTrace(.parsing, "Family text preview: \(String(familyText.prefix(300)))...")
        
        DebugLogger.shared.startTimer("total_parsing")
        
        guard currentAIService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentAIService.name)")
            throw AIServiceError.notConfigured(currentAIService.name)
        }
        
        do {
            // Step 1: Get JSON string from AI
            logDebug(.ai, "Step 1: Requesting JSON parsing from \(currentAIService.name)")
            DebugLogger.shared.startTimer("ai_request")
            
            let jsonString = try await currentAIService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            let aiDuration = DebugLogger.shared.endTimer("ai_request")
            logInfo(.ai, "✅ AI response received in \(String(format: "%.2f", aiDuration))s")
            logDebug(.ai, "Response length: \(jsonString.count) characters")
            logTrace(.ai, "Response preview: \(String(jsonString.prefix(500)))...")
            
            // DEBUG: Log the full response for troubleshooting
            print("🐛 ========== AI JSON RESPONSE ==========")
            print(jsonString)
            print("🐛 ========== END AI RESPONSE ==========")
            
            // Step 2: Parse the JSON string into a Family object
            logDebug(.parsing, "Step 2: Parsing JSON string into Family object")
            DebugLogger.shared.startTimer("json_parsing")
            
            let family = try parseJSONString(jsonString)
            
            let parseDuration = DebugLogger.shared.endTimer("json_parsing")
            let totalDuration = DebugLogger.shared.endTimer("total_parsing")
            
            logInfo(.parsing, "✅ JSON parsing completed in \(String(format: "%.3f", parseDuration))s")
            logInfo(.parsing, "🎉 Total parsing completed in \(String(format: "%.2f", totalDuration))s")
            
            // Step 3: Log parsing results
            DebugLogger.shared.logParsingSuccess(family)
            
            return family
            
        } catch let error as AIServiceError {
            _ = DebugLogger.shared.endTimer("ai_request")
            _ = DebugLogger.shared.endTimer("json_parsing")
            _ = DebugLogger.shared.endTimer("total_parsing")
            
            logError(.ai, "❌ AI service error: \(error.localizedDescription)")
            DebugLogger.shared.logParsingFailure(error, familyId: familyId)
            throw error
        } catch {
            _ = DebugLogger.shared.endTimer("ai_request")
            _ = DebugLogger.shared.endTimer("json_parsing")
            _ = DebugLogger.shared.endTimer("total_parsing")
            
            logError(.parsing, "❌ Parsing error: \(error.localizedDescription)")
            DebugLogger.shared.logParsingFailure(error, familyId: familyId)
            throw AIServiceError.parsingFailed(error.localizedDescription)
        }
    }
    
    // MARK: - JSON Parsing (New - Replaces Struct Parsing)
    
    /**
     * Parse AI-generated JSON string into Family object
     *
     * Much more robust than custom struct parsing - uses Swift's built-in JSONDecoder
     */
    private func parseJSONString(_ jsonString: String) throws -> Family {
        logDebug(.parsing, "🔍 Starting JSON string parsing")
        logTrace(.parsing, "JSON string length: \(jsonString.count)")
        
        // Clean the response (remove markdown, extra whitespace)
        let cleanedJSON = cleanJSONString(jsonString)
        logTrace(.parsing, "Cleaned JSON length: \(cleanedJSON.count)")
        
        // Validate basic JSON structure
        guard cleanedJSON.hasPrefix("{") && cleanedJSON.hasSuffix("}") else {
            logError(.parsing, "❌ Response doesn't match JSON object format")
            logTrace(.parsing, "Invalid format - starts with: \(String(cleanedJSON.prefix(50)))")
            throw AIServiceError.parsingFailed("Response doesn't match JSON object format")
        }
        
        logDebug(.parsing, "✅ JSON format validation passed")
        
        // Use JSONDecoder to parse
        do {
            logDebug(.parsing, "Using JSONDecoder for parsing")
            
            let decoder = JSONDecoder()
            let data = cleanedJSON.data(using: .utf8)!
            let family = try decoder.decode(Family.self, from: data)
            
            // Validate the parsed family
            logDebug(.parsing, "Validating parsed family structure")
            let warnings = family.validateStructure()
            DebugLogger.shared.logFamilyValidation(family, warnings: warnings)
            
            logInfo(.parsing, "✅ JSON parsing successful")
            return family
            
        } catch let decodingError as DecodingError {
            logError(.parsing, "❌ JSON decoding failed: \(decodingError.localizedDescription)")
            logTrace(.parsing, "Decoding error details: \(decodingError)")
            
            // Try to provide more helpful error information
            let errorDetails = getDecodingErrorDetails(decodingError)
            logDebug(.parsing, "Error details: \(errorDetails)")
            
            throw AIServiceError.parsingFailed("JSON decoding failed: \(errorDetails)")
            
        } catch {
            logError(.parsing, "❌ Unexpected JSON parsing error: \(error)")
            throw AIServiceError.parsingFailed("JSON parsing failed: \(error.localizedDescription)")
        }
    }
    
    /**
     * Clean AI response to valid JSON format
     */
    private func cleanJSONString(_ response: String) -> String {
        logTrace(.parsing, "Cleaning AI JSON response")
        var cleaned = response
        
        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // Remove extra whitespace and newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure proper JSON object format
        if !cleaned.hasPrefix("{") {
            // Try to find the JSON object start
            if let range = cleaned.range(of: "{") {
                cleaned = String(cleaned[range.lowerBound...])
                logTrace(.parsing, "Found JSON object start, trimmed prefix")
            }
        }
        
        // Ensure proper JSON object end
        if !cleaned.hasSuffix("}") {
            // Try to find the last } and trim after it
            if let range = cleaned.range(of: "}", options: .backwards) {
                cleaned = String(cleaned[..<range.upperBound])
                logTrace(.parsing, "Found JSON object end, trimmed suffix")
            }
        }
        
        logTrace(.parsing, "JSON string cleaning complete")
        return cleaned
    }
    
    /**
     * Get helpful details from JSONDecoder errors
     */
    private func getDecodingErrorDetails(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing required key '\(key)' at \(context.codingPath)"
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(context.codingPath): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Value not found for \(type) at \(context.codingPath): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Configuration Persistence (Unchanged)
    
    private func autoConfigureServices() {
        logDebug(.ai, "🔧 Auto-configuring services from saved settings")
        
        // Try to load saved API keys
        for service in availableServices {
            if let savedKey = loadAPIKey(for: service.name) {
                do {
                    try service.configure(apiKey: savedKey)
                    logInfo(.ai, "✅ Auto-configured \(service.name) from saved API key")
                } catch {
                    logWarn(.ai, "⚠️ Failed to auto-configure \(service.name): \(error)")
                }
            } else {
                logTrace(.ai, "No saved API key for \(service.name)")
            }
        }
    }
    
    private func saveAPIKey(_ apiKey: String, for serviceName: String) {
        logTrace(.ai, "💾 Saving API key for \(serviceName)")
        UserDefaults.standard.set(apiKey, forKey: "AIService_\(serviceName)_APIKey")
    }
    
    private func loadAPIKey(for serviceName: String) -> String? {
        let key = UserDefaults.standard.string(forKey: "AIService_\(serviceName)_APIKey")
        logTrace(.ai, "📂 Loading API key for \(serviceName): \(key != nil ? "found" : "not found")")
        return key
    }
}

// MARK: - Updated MockAIService for JSON

/**
 * Updated Mock AI service for JSON testing
 */
extension MockAIService {
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 MockAI JSON parsing family: \(familyId)")
        logTrace(.ai, "Family text length: \(familyText.count) characters")
        
        DebugLogger.shared.startTimer("mock_ai_processing")
        
        // Simulate AI processing time
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let duration = DebugLogger.shared.endTimer("mock_ai_processing")
        logDebug(.ai, "MockAI JSON processing completed in \(String(format: "%.3f", duration))s")
        
        // Return hardcoded JSON responses for known families
        let response: String
        switch familyId.uppercased() {
        case "KORPI 6":
            response = mockKorpi6JSONResponse()
            logDebug(.ai, "Returning KORPI 6 mock JSON response")
        case "TEST 1":
            response = mockTest1JSONResponse()
            logDebug(.ai, "Returning TEST 1 mock JSON response")
        default:
            response = mockGenericJSONResponse(familyId: familyId)
            logDebug(.ai, "Returning generic mock JSON response for \(familyId)")
        }
        
        logTrace(.ai, "Mock JSON response length: \(response.count) characters")
        return response
    }
    
    private func mockKorpi6JSONResponse() -> String {
        return """
        {
          "familyId": "KORPI 6",
          "pageReferences": ["105", "106"],
          "father": {
            "name": "Matti",
            "patronymic": "Erikinp.",
            "birthDate": "09.09.1727",
            "deathDate": "22.08.1812",
            "marriageDate": "14.10.1750",
            "spouse": "Brita Matint.",
            "asChildReference": "KORPI 5",
            "asParentReference": null,
            "familySearchId": "LCJZ-BH3",
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "mother": {
            "name": "Brita",
            "patronymic": "Matint.",
            "birthDate": "05.09.1731",
            "deathDate": "11.07.1769",
            "marriageDate": "14.10.1750",
            "spouse": "Matti Erikinp.",
            "asChildReference": "SIKALA 5",
            "asParentReference": null,
            "familySearchId": "KCJW-98X",
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "additionalSpouses": [],
          "children": [
            {
              "name": "Maria",
              "patronymic": null,
              "birthDate": "10.02.1752",
              "deathDate": null,
              "marriageDate": "1773",
              "spouse": "Elias Iso-Peitso",
              "asChildReference": null,
              "asParentReference": "ISO-PEITSO III 2",
              "familySearchId": "KJJH-2R9",
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            },
            {
              "name": "Kaarin",
              "patronymic": null,
              "birthDate": "01.02.1753",
              "deathDate": "17.04.1795",
              "marriageDate": null,
              "spouse": null,
              "asChildReference": null,
              "asParentReference": null,
              "familySearchId": "LJKQ-PLT",
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            },
            {
              "name": "Abraham",
              "patronymic": null,
              "birthDate": "08.01.1764",
              "deathDate": null,
              "marriageDate": "1787",
              "spouse": "Anna Sikala",
              "asChildReference": null,
              "asParentReference": "JÄNESNIEMI 5",
              "familySearchId": null,
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            }
          ],
          "notes": ["Lapsena kuollut 4."],
          "childrenDiedInfancy": 4
        }
        """
    }
    
    private func mockTest1JSONResponse() -> String {
        return """
        {
          "familyId": "TEST 1",
          "pageReferences": ["1"],
          "father": {
            "name": "Test",
            "patronymic": "Matinp.",
            "birthDate": "01.01.1700",
            "deathDate": null,
            "marriageDate": null,
            "spouse": null,
            "asChildReference": null,
            "asParentReference": null,
            "familySearchId": null,
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "mother": {
            "name": "Example",
            "patronymic": "Juhont.",
            "birthDate": "01.01.1705",
            "deathDate": null,
            "marriageDate": null,
            "spouse": null,
            "asChildReference": null,
            "asParentReference": null,
            "familySearchId": null,
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "additionalSpouses": [],
          "children": [
            {
              "name": "Child",
              "patronymic": null,
              "birthDate": "01.01.1725",
              "deathDate": null,
              "marriageDate": null,
              "spouse": null,
              "asChildReference": null,
              "asParentReference": null,
              "familySearchId": null,
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            }
          ],
          "notes": ["Mock family for testing"],
          "childrenDiedInfancy": 0
        }
        """
    }
    
    private func mockGenericJSONResponse(familyId: String) -> String {
        return """
        {
          "familyId": "\(familyId)",
          "pageReferences": ["999"],
          "father": {
            "name": "Unknown",
            "patronymic": "Matinp.",
            "birthDate": "01.01.1700",
            "deathDate": null,
            "marriageDate": null,
            "spouse": null,
            "asChildReference": null,
            "asParentReference": null,
            "familySearchId": null,
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "mother": null,
          "additionalSpouses": [],
          "children": [],
          "notes": ["Mock data for \(familyId)"],
          "childrenDiedInfancy": 0
        }
        """
    }
}
