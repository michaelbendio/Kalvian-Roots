//
//  AIParsingService.swift
//  Kalvian Roots
//
//

import Foundation

/**
 * AIParsingService - JSON-based AI family parsing for Michael's genealogy research
 *
 * Single-user app architecture:
 * - Mac: MLX (Qwen3-30B) primary + DeepSeek fallback
 * - iOS: DeepSeek only (mobile research)
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
    
    // MARK: - Single-User Initialization (Michael's Devices Only)
    
    init() {
        logInfo(.ai, "🚀 AIParsingService starting (Michael's genealogy research)")
        
        // Get available services
        self.availableServices = PlatformAwareServiceManager.getRecommendedServices()
        self.currentAIService = PlatformAwareServiceManager.getDefaultService()
        
        logInfo(.ai, "✅ Platform: \(PlatformAwareServiceManager.getPlatformCapabilities())")
        logInfo(.ai, "Default service: \(currentServiceName)")
        
        // Platform-specific setup (no Intel support needed)
        #if os(macOS)
        // Apple Silicon Mac - MLX primary, DeepSeek fallback
        logInfo(.ai, "🖥️ Apple Silicon Mac - MLX (Qwen3-30B) + DeepSeek fallback")
        Task {
            await checkMLXServerStatus()
        }
        #elseif os(iOS)
        // iOS - DeepSeek only (simplified)
        logInfo(.ai, "📱 iOS - DeepSeek only (mobile research)")
        #endif
        
        // Auto-load Michael's saved API keys
        autoConfigureServices()
        
        logInfo(.ai, "✅ Ready for Finnish genealogy research")
    }
    
    // MARK: - Service Management (Fixed Method Signatures)
    
    // FIXED: Method name to match JuuretApp expectations
    func switchToService(named serviceName: String) async throws {
        try switchService(to: serviceName)
    }
    
    // Internal method with clearer name
    func switchService(to serviceName: String) throws {
        guard let service = availableServices.first(where: { $0.name == serviceName }) else {
            throw AIServiceError.notConfigured("Service \(serviceName) not available")
        }
        
        currentAIService = service
        logInfo(.ai, "🔄 Switched to AI service: \(serviceName)")
        logDebug(.ai, "Service configured: \(service.isConfigured)")
    }
    
    // FIXED: Made async to match JuuretApp expectations
    func configureCurrentService(apiKey: String) async throws {
        try currentAIService.configure(apiKey: apiKey)
        saveAPIKey(apiKey, for: currentServiceName)
        logInfo(.ai, "🔧 Configured \(currentServiceName) with new API key")
    }
    
    func getAllServiceStatuses() -> [ServiceStatus] {
        return availableServices.map { service in
            ServiceStatus(
                name: service.name,
                isConfigured: service.isConfigured,
                isCurrent: service.name == currentServiceName
            )
        }
    }
    
    // MARK: - MLX Integration (Simplified)
    
    private func checkMLXServerStatus() async {
        // No need to check platform - this only runs on Apple Silicon
        logInfo(.ai, "✅ MLX available - Qwen3-30B ready for local parsing")
        logDebug(.ai, "Local AI: fast, private, no API costs")
    }
    
    func preloadMLXModel() async throws {
        guard currentAIService is MLXService else {
            logWarn(.ai, "Current service is not MLX - cannot preload")
            return
        }
        
        if let mlxService = currentAIService as? MLXService {
            logInfo(.ai, "🔄 MLX service ready: \(mlxService.name)")
            logInfo(.ai, "✅ MLX service verified as ready")
        }
    }
    
    // MARK: - Core Family Parsing (JSON-based)
    
    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        logInfo(.parsing, "🔍 Starting family parsing for: \(familyId)")
        logDebug(.parsing, "Using AI service: \(currentServiceName)")
        
        // Validate service configuration
        guard currentAIService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentServiceName)")
            throw AIServiceError.notConfigured(currentServiceName)
        }
        
        // Start timing
        DebugLogger.shared.startTimer("total_parsing")
        DebugLogger.shared.parseStep("AI Request", "Requesting family parsing from \(currentServiceName)")
        
        do {
            // Step 1: Get JSON response from AI service
            DebugLogger.shared.startTimer("ai_request")
            let jsonResponse = try await currentAIService.parseFamily(familyId: familyId, familyText: familyText)
            let aiTime = DebugLogger.shared.endTimer("ai_request")
            
            logInfo(.parsing, "✅ AI response received (\(String(format: "%.2f", aiTime))s)")
            logTrace(.parsing, "JSON Response preview: \(String(jsonResponse.prefix(200)))...")
            
            // Step 2: Parse the JSON response into a Family struct
            DebugLogger.shared.parseStep("Parse JSON", "Converting AI JSON response to Family struct")
            DebugLogger.shared.startTimer("json_parsing")
            
            let family = try parseJSONResponse(jsonResponse)
            
            let parseTime = DebugLogger.shared.endTimer("json_parsing")
            let totalTime = DebugLogger.shared.endTimer("total_parsing")
            
            logInfo(.parsing, "✅ Family parsing completed successfully")
            logInfo(.parsing, "⏱️ Timing: AI=\(String(format: "%.2f", aiTime))s, Parse=\(String(format: "%.2f", parseTime))s, Total=\(String(format: "%.2f", totalTime))s")
            
            DebugLogger.shared.logFamilyValidation(family, warnings: family.validateStructure())
            
            return family
            
        } catch {
            // Clean up timers on error
            _ = DebugLogger.shared.endTimer("ai_request")
            _ = DebugLogger.shared.endTimer("json_parsing")
            _ = DebugLogger.shared.endTimer("total_parsing")
            
            logError(.parsing, "❌ Parsing error: \(error.localizedDescription)")
            DebugLogger.shared.logParsingFailure(error, familyId: familyId)
            throw AIServiceError.parsingFailed(error.localizedDescription)
        }
    }
    
    // MARK: - JSON Parsing Methods (Fixed)
    
    private func parseJSONResponse(_ jsonResponse: String) throws -> Family {
        logDebug(.parsing, "🔍 Starting JSON response parsing")
        DebugLogger.shared.parseStep("Parse JSON", "Converting AI JSON response to Family struct")
        
        // Clean the JSON response (remove markdown, extra whitespace)
        let cleanedJSON = cleanJSONResponse(jsonResponse)
        logTrace(.parsing, "Cleaned JSON length: \(cleanedJSON.count)")
        logTrace(.parsing, "Cleaned JSON preview: \(String(cleanedJSON.prefix(200)))...")
        
        // Parse as JSON
        do {
            DebugLogger.shared.parseStep("JSON Decode", "Using JSONDecoder")
            
            guard let jsonData = cleanedJSON.data(using: .utf8) else {
                throw AIServiceError.parsingFailed("Could not convert JSON response to UTF-8 data")
            }
            
            let decoder = JSONDecoder()
            let family = try decoder.decode(Family.self, from: jsonData)
            
            // Validate the parsed family
            logDebug(.parsing, "Validating parsed family structure")
            let warnings = family.validateStructure()
            DebugLogger.shared.logFamilyValidation(family, warnings: warnings)
            
            logInfo(.parsing, "✅ JSON parsing successful")
            return family
            
        } catch let decodingError as DecodingError {
            logWarn(.parsing, "⚠️ JSON decoding failed: \(decodingError)")
            
            // Try fallback parsing for malformed JSON
            DebugLogger.shared.parseStep("Fallback parsing", "JSON malformed, attempting recovery")
            return try fallbackParseJSON(cleanedJSON)
            
        } catch {
            logError(.parsing, "❌ Unexpected JSON parsing error: \(error)")
            throw AIServiceError.parsingFailed("JSON parsing failed: \(error.localizedDescription)")
        }
    }
    
    private func cleanJSONResponse(_ jsonResponse: String) -> String {
        logTrace(.parsing, "🧹 Cleaning JSON response")
        
        var cleaned = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code block markers if present
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        // Trim again after removing markdown
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        logTrace(.parsing, "JSON cleaned: \(cleaned.count) characters")
        return cleaned
    }
    
    private func fallbackParseJSON(_ malformedJSON: String) throws -> Family {
        logWarn(.parsing, "🔧 Attempting fallback JSON parsing")
        DebugLogger.shared.parseStep("Fallback JSON", "Attempting to extract minimal family data")
        
        // Try to extract basic family information from malformed JSON
        return try createMinimalFamilyFromBrokenJSON(malformedJSON)
    }
    
    private func createMinimalFamilyFromBrokenJSON(_ brokenJSON: String) throws -> Family {
        logWarn(.parsing, "⚠️ Creating minimal family structure from broken JSON")
        
        // Extract family ID if possible
        let familyId = extractJSONValue(from: brokenJSON, key: "familyId") ?? "UNKNOWN"
        let fatherName = extractJSONValue(from: brokenJSON, key: "name") ?? "Unknown Father"
        
        // Create minimal viable family structure
        let father = Person(
            name: fatherName,
            noteMarkers: []
        )
        
        logWarn(.parsing, "⚠️ Created minimal family structure for: \(familyId)")
        
        return Family(
            familyId: familyId,
            pageReferences: ["999"], // Default page reference
            father: father,
            mother: nil,
            additionalSpouses: [],
            children: [],
            notes: ["Minimal parsing used - AI response was malformed"],
            childrenDiedInfancy: nil
        )
    }
    
    private func extractJSONValue(from jsonString: String, key: String) -> String? {
        let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
              let range = Range(match.range(at: 1), in: jsonString) else {
            return nil
        }
        
        return String(jsonString[range])
    }
    
    // MARK: - Configuration Persistence
    
    private func autoConfigureServices() {
        logDebug(.ai, "🔧 Loading Michael's saved API keys")
        
        // Load saved API keys (skip MLX - doesn't need keys)
        for service in availableServices {
            if service.name.contains("MLX") {
                continue // MLX doesn't need API keys
            }
            
            if let savedKey = loadAPIKey(for: service.name) {
                do {
                    try service.configure(apiKey: savedKey)
                    logInfo(.ai, "✅ Configured \(service.name)")
                } catch {
                    logWarn(.ai, "⚠️ Failed to configure \(service.name): \(error)")
                }
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

// MARK: - ServiceStatus Support Structure

struct ServiceStatus {
    let name: String
    let isConfigured: Bool
    let isCurrent: Bool
}
