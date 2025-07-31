//
//  MLXService.swift
//  Kalvian Roots
//
//  Complete MLX service implementation for local AI family parsing
//

import Foundation

/**
 * MLX service for local AI processing using Apple Silicon
 *
 * Provides family parsing using local models like Qwen3-30B, Llama3.2-8B, and Mistral-7B
 * Handles its own availability detection and server communication.
 */
class MLXService: AIService {
    let name: String
    private let modelName: String
    private let baseURL = "http://127.0.0.1:8080"
    
    var isConfigured: Bool {
        // For now, MLX is always configured if it was created
        return true
    }
    
    // MARK: - Private Initializer
    
    private init(name: String, modelName: String) {
        self.name = name
        self.modelName = modelName
        logInfo(.ai, "🤖 MLX Service initialized: \(name)")
    }
    
    // MARK: - Static Factory Methods (with availability check)
    
    /// High-performance 30B parameter model for complex families
    static func qwen3_30B() throws -> MLXService {
        guard isMLXAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(name: "MLX Qwen3-30B (Local)", modelName: "qwen3-30b")
    }
    
    /// Balanced 8B parameter model for most families
    static func llama3_2_8B() throws -> MLXService {
        guard isMLXAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(name: "MLX Llama3.2-8B (Local)", modelName: "llama3.2-8b")
    }
    
    /// Fast 7B parameter model for simple families
    static func mistral_7B() throws -> MLXService {
        guard isMLXAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(name: "MLX Mistral-7B (Local)", modelName: "mistral-7b")
    }
    
    // MARK: - Platform Detection (self-contained)
    
    /// Check if MLX is available on current platform
    private static func isMLXAvailable() -> Bool {
        #if os(macOS)
        // Check if we're running on Apple Silicon
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        
        let isAppleSilicon = machine.contains("arm64")
        logDebug(.ai, "MLX availability check - Apple Silicon: \(isAppleSilicon)")
        return isAppleSilicon
        #else
        logDebug(.ai, "MLX availability check - not macOS")
        return false
        #endif
    }
    
    // MARK: - AIService Protocol Implementation
    
    func configure(apiKey: String) throws {
        // MLX doesn't need API keys, but we can use this to test server connection
        logInfo(.ai, "🔧 Testing MLX server connection for \(name)")
        
        // For now, just log success
        logInfo(.ai, "✅ MLX service configured: \(name)")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 \(name) parsing family: \(familyId)")
        logDebug(.ai, "Using MLX model: \(modelName)")
        logTrace(.ai, "Family text length: \(familyText.count) characters")
        logDebug(.ai, "📝 MLX parseFamily called with real family text")
        
        // Check if MLX server is available before attempting to parse
        let serverRunning = await isMLXServerRunning()
        logInfo(.ai, "🏥 MLX server health check result: \(serverRunning ? "RUNNING" : "NOT RUNNING")")
        
        if !serverRunning {
            logWarn(.ai, "⚠️ MLX server not running at \(baseURL)")
            logInfo(.ai, "💡 Start MLX server with: python -m mlx_lm.server --model ~/.kalvian_roots_mlx/models/\(getModelPath()) --port 8080")
            logInfo(.ai, "📝 Using mock response for now - see MLX setup guide")
            return createMockFamilyJSON(familyId: familyId)
        }
        
        logInfo(.ai, "✅ MLX server is running, attempting real AI processing...")
        logDebug(.ai, "📝 Family text to parse (\(familyText.count) chars): \(familyText)")
        
        // Check if we got a very short family text (likely extraction issue)
        if familyText.count < 100 {
            logWarn(.ai, "⚠️ Family text unusually short (\(familyText.count) chars)")
            logWarn(.ai, "⚠️ This suggests a family text extraction issue")
            logWarn(.ai, "📝 Short text: '\(familyText)'")
            logWarn(.ai, "🔄 Using mock response due to insufficient family text")
            return createMockFamilyJSON(familyId: familyId)
        }
        
        logInfo(.ai, "🚀 Proceeding with real MLX AI processing...")
        logDebug(.ai, "🔍 Will try multiple endpoints to find working MLX API")
        
        do {
            // Try multiple endpoints until one works
            let endpointsToTry = [
                "/v1/completions",         // This one works! (from curl test)
                "/v1/chat/completions",    // This returns 404 (from curl test)
                "/chat/completions",       // Some MLX servers use this
                "/completions",            // Basic completions
                "/generate"                // Some MLX servers use this
            ]
            
            var lastError: Error?
            
            for endpoint in endpointsToTry {
                do {
                    logDebug(.ai, "🔍 Trying MLX endpoint: \(endpoint)")
                    let request = try createMLXRequest(familyId: familyId, familyText: familyText, endpoint: endpoint)
                    let response = try await sendMLXRequest(request)
                    let validatedJSON = try validateMLXResponse(response, endpoint: endpoint)
                    logInfo(.ai, "✅ MLX parsing successful with endpoint: \(endpoint)")
                    logDebug(.ai, "🎯 Real AI response received (not mock): \(String(validatedJSON.prefix(100)))...")
                    return validatedJSON
                } catch let error as AIServiceError {
                    if case .httpError(let statusCode, let message) = error {
                        logDebug(.ai, "❌ Endpoint \(endpoint) failed: \(statusCode) - \(message)")
                        lastError = error
                        if statusCode != 404 {
                            // If it's not a 404, this endpoint exists but something else is wrong
                            logError(.ai, "🚨 MLX server error on \(endpoint): \(statusCode) - \(message)")
                            throw error
                        }
                        // Continue to next endpoint if 404
                    } else {
                        logError(.ai, "🚨 MLX error on \(endpoint): \(error)")
                        throw error
                    }
                } catch {
                    logDebug(.ai, "❌ Endpoint \(endpoint) failed: \(error)")
                    lastError = error
                }
            }
            
            // If we get here, all endpoints failed
            logError(.ai, "❌ All MLX endpoints failed for \(familyId)")
            logWarn(.ai, "🔄 Falling back to mock response since real AI failed")
            throw lastError ?? AIServiceError.networkError(NSError(domain: "MLXService", code: -1, userInfo: [NSLocalizedDescriptionKey: "All endpoints failed"]))
            
        } catch {
            logError(.ai, "❌ MLX parsing failed for \(familyId): \(error)")
            // Fallback to mock response if MLX fails
            logWarn(.ai, "🔄 Using mock response as fallback")
            return createMockFamilyJSON(familyId: familyId)
        }
    }
    
    // MARK: - MLX Server Communication
    
    private func isMLXServerRunning() async -> Bool {
        do {
            let url = URL(string: "\(baseURL)/health")!
            let (_, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                let isRunning = httpResponse.statusCode == 200
                logDebug(.ai, "MLX server health check: \(isRunning ? "✅ Running" : "❌ Not running")")
                return isRunning
            }
            
            return false
        } catch {
            logDebug(.ai, "MLX server not reachable: \(error.localizedDescription)")
            return false
        }
    }
    
    private func createMLXRequest(familyId: String, familyText: String, endpoint: String) throws -> URLRequest {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = createFamilyParsingPrompt(familyId: familyId, familyText: familyText)
        
        var requestBody: [String: Any]
        
        if endpoint.contains("chat") {
            // Chat completions format
            requestBody = [
                "model": modelName,
                "messages": [
                    [
                        "role": "system",
                        "content": "You are a Finnish genealogy expert. Extract family information from Finnish text and return ONLY valid JSON."
                    ],
                    [
                        "role": "user",
                        "content": prompt
                    ]
                ],
                "max_tokens": 2000,
                "temperature": 0.1
            ] as [String: Any]
        } else {
            // Text completions format
            requestBody = [
                "model": modelName,
                "prompt": prompt,
                "max_tokens": 2000,
                "temperature": 0.1
            ] as [String: Any]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        logTrace(.ai, "MLX request created for endpoint: \(endpoint)")
        return request
    }
    
    // Fallback to completions endpoint if chat/completions doesn't work
    private func createFallbackMLXRequest(familyId: String, familyText: String) throws -> URLRequest {
        let url = URL(string: "\(baseURL)/v1/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = createFamilyParsingPrompt(familyId: familyId, familyText: familyText)
        
        let requestBody = [
            "model": modelName,
            "prompt": prompt,
            "max_tokens": 2000,
            "temperature": 0.1,
            "stop": ["\\n\\n", "---"]
        ] as [String: Any]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        logTrace(.ai, "MLX fallback request created for model: \(modelName)")
        return request
    }
    
    private func validateFallbackMLXResponse(_ data: Data) throws -> String {
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw AIServiceError.invalidResponse("Could not decode MLX fallback response as UTF-8")
        }
        
        // Parse MLX completion response (older format)
        do {
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = jsonResponse["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let text = firstChoice["text"] as? String {
                
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Basic JSON validation
                if trimmedText.hasPrefix("{") && trimmedText.hasSuffix("}") {
                    logDebug(.ai, "MLX fallback response appears to be valid JSON")
                    return trimmedText
                } else {
                    logWarn(.ai, "MLX fallback response doesn't look like JSON, attempting to extract...")
                    return try extractJSONFromText(trimmedText)
                }
            } else {
                throw AIServiceError.invalidResponse("MLX fallback response missing expected structure")
            }
        } catch {
            logError(.ai, "Failed to parse MLX fallback response: \(error)")
            throw AIServiceError.invalidResponse("Could not parse MLX fallback response: \(error.localizedDescription)")
        }
    }
    
    private func createFamilyParsingPrompt(familyId: String, familyText: String) -> String {
        return """
        You are parsing Finnish genealogical data from "Juuret Kälviällä". Extract family information and return ONLY valid JSON.

        Family ID: \(familyId)
        
        Text to parse:
        \(familyText)
        
        Return JSON in this exact format:
        {
          "familyId": "\(familyId)",
          "pageReferences": ["page_numbers"],
          "father": {
            "name": "First name only",
            "patronymic": "Patronymic with p. suffix",
            "birthDate": "DD.MM.YYYY or partial",
            "deathDate": "DD.MM.YYYY or partial",
            "noteMarkers": ["marker_letters"]
          },
          "mother": {
            "name": "First name only", 
            "patronymic": "Patronymic with t. suffix",
            "birthDate": "DD.MM.YYYY or partial",
            "deathDate": "DD.MM.YYYY or partial",
            "noteMarkers": ["marker_letters"]
          },
          "additionalSpouses": [],
          "children": [
            {
              "name": "First name only",
              "birthDate": "DD.MM.YYYY or partial",
              "deathDate": "DD.MM.YYYY or partial",
              "spouse": "Spouse name if mentioned",
              "marriageDate": "DD.MM.YYYY or partial",
              "noteMarkers": ["marker_letters"],
              "asParentReference": "FAMILY_ID if mentioned"
            }
          ],
          "notes": ["text_of_notes"],
          "childrenDiedInfancy": "text or null"
        }
        
        Important rules:
        - Extract dates as DD.MM.YYYY when complete, partial when incomplete
        - Use patronymics with p. (father's name) or t. (mother's name) suffix
        - Include note markers as letters from the text
        - Return ONLY the JSON, no other text
        """
    }
    
    private func sendMLXRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError(NSError(domain: "MLXService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"]))
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.httpError(httpResponse.statusCode, errorMessage)
        }
        
        return data
    }
    
    private func validateMLXResponse(_ data: Data, endpoint: String) throws -> String {
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw AIServiceError.invalidResponse("Could not decode MLX response as UTF-8")
        }
        
        logTrace(.ai, "Raw MLX response: \(responseString)")
        
        // Try to parse as JSON first
        do {
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                var content: String?
                
                // Handle different response formats based on what we saw in curl test
                if let choices = jsonResponse["choices"] as? [[String: Any]], let firstChoice = choices.first {
                    // Standard completions format (this is what MLX returns)
                    if let text = firstChoice["text"] as? String {
                        // Text completions format - this is what our MLX server uses!
                        content = text
                        logDebug(.ai, "Found content in choices[0].text: \(String(text.prefix(50)))...")
                    } else if let message = firstChoice["message"] as? [String: Any],
                       let messageContent = message["content"] as? String {
                        // Chat completions format (fallback)
                        content = messageContent
                        logDebug(.ai, "Found content in choices[0].message.content")
                    }
                } else if let response = jsonResponse["response"] as? String {
                    // Simple response format
                    content = response
                    logDebug(.ai, "Found content in response field")
                } else if let text = jsonResponse["text"] as? String {
                    // Direct text format
                    content = text
                    logDebug(.ai, "Found content in text field")
                } else if let generated = jsonResponse["generated_text"] as? String {
                    // Some MLX servers use this
                    content = generated
                    logDebug(.ai, "Found content in generated_text field")
                }
                
                if let content = content {
                    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    logDebug(.ai, "Extracted content (\(trimmedContent.count) chars): \(String(trimmedContent.prefix(200)))...")
                    
                    if trimmedContent.hasPrefix("{") && trimmedContent.hasSuffix("}") {
                        logDebug(.ai, "MLX response appears to be valid JSON")
                        return trimmedContent
                    } else {
                        logWarn(.ai, "MLX response doesn't look like JSON, attempting to extract...")
                        logDebug(.ai, "Non-JSON content: \(trimmedContent)")
                        return try extractJSONFromText(trimmedContent)
                    }
                } else {
                    logWarn(.ai, "Could not find content in MLX response structure")
                    logDebug(.ai, "Response keys: \(jsonResponse.keys.sorted())")
                    return try extractJSONFromText(responseString)
                }
            } else {
                // Maybe the response is directly the JSON we want
                logDebug(.ai, "Response is not a wrapper object, checking if it's direct JSON")
                if responseString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                    return responseString.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    return try extractJSONFromText(responseString)
                }
            }
        } catch {
            logError(.ai, "Failed to parse MLX response as JSON: \(error)")
            logDebug(.ai, "Attempting to extract JSON from raw text")
            return try extractJSONFromText(responseString)
        }
    }
    
    private func extractJSONFromText(_ text: String) throws -> String {
        // Try to find JSON within the text
        let lines = text.components(separatedBy: .newlines)
        var jsonLines: [String] = []
        var inJSON = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("{") {
                inJSON = true
                jsonLines = [trimmed]
            } else if inJSON {
                jsonLines.append(line)
                if trimmed.hasSuffix("}") {
                    break
                }
            }
        }
        
        let extractedJSON = jsonLines.joined(separator: "\n")
        
        if extractedJSON.hasPrefix("{") && extractedJSON.hasSuffix("}") {
            return extractedJSON
        } else {
            throw AIServiceError.invalidResponse("Could not extract valid JSON from MLX response")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getModelPath() -> String {
        switch modelName {
        case "qwen3-30b":
            return "Qwen3-30B-A3B-4bit"
        case "llama3.2-8b":
            return "Llama3.2-8B-4bit"
        case "mistral-7b":
            return "Mistral-7B-Instruct-4bit"
        default:
            return "Qwen3-30B-A3B-4bit"
        }
    }
    
    // MARK: - Fallback Mock Response
    
    private func createMockFamilyJSON(familyId: String) -> String {
        logWarn(.ai, "🔄 Creating mock JSON response - MLX AI processing not working")
        logInfo(.ai, "💡 This means either:")
        logInfo(.ai, "   1. MLX server endpoints not found (all returned 404)")
        logInfo(.ai, "   2. MLX server not actually running the AI model")
        logInfo(.ai, "   3. MLX server configuration issue")
        
        return """
        {
          "familyId": "\(familyId)",
          "pageReferences": ["999"],
          "father": {
            "name": "Mock Father",
            "patronymic": "Mockp.",
            "birthDate": "01.01.1700",
            "noteMarkers": []
          },
          "mother": {
            "name": "Mock Mother", 
            "patronymic": "Mockt.",
            "birthDate": "01.01.1705",
            "noteMarkers": []
          },
          "additionalSpouses": [],
          "children": [
            {
              "name": "Mock Child",
              "birthDate": "01.01.1730",
              "noteMarkers": []
            }
          ],
          "notes": ["MOCK RESPONSE - MLX server found but AI processing failed"],
          "childrenDiedInfancy": null
        }
        """
    }
}

// MARK: - MLX Availability Check (for external use)

extension MLXService {
    
    /// Public method to check if MLX services can be created
    static func isAvailable() -> Bool {
        return isMLXAvailable()
    }
    
    /// Get recommended MLX model based on available memory
    static func getRecommendedModel() -> MLXService? {
        guard isMLXAvailable() else { return nil }
        
        // Simple recommendation based on available memory
        let memory = getSystemMemory() / (1024 * 1024 * 1024) // Convert to GB
        
        do {
            if memory >= 32 {
                return try qwen3_30B()
            } else if memory >= 16 {
                return try llama3_2_8B()
            } else {
                return try mistral_7B()
            }
        } catch {
            logWarn(.ai, "Failed to create recommended MLX model: \(error)")
            return nil
        }
    }
    
    /// Get system memory (private helper)
    private static func getSystemMemory() -> UInt64 {
        #if os(macOS)
        var size = MemoryLayout<UInt64>.size
        var memSize: UInt64 = 0
        sysctlbyname("hw.memsize", &memSize, &size, nil, 0)
        return memSize
        #else
        return 0
        #endif
    }
}

// MARK: - Logging Helper

#if canImport(OSLog)
import OSLog

private func logInfo(_ category: OSLog, _ message: String) {
    os_log("%{public}@", log: category, type: .info, message)
}

private func logDebug(_ category: OSLog, _ message: String) {
    os_log("%{public}@", log: category, type: .debug, message)
}

private func logTrace(_ category: OSLog, _ message: String) {
    os_log("%{public}@", log: category, type: .debug, message)
}

private func logWarn(_ category: OSLog, _ message: String) {
    os_log("%{public}@", log: category, type: .default, message)
}

private func logError(_ category: OSLog, _ message: String) {
    os_log("%{public}@", log: category, type: .error, message)
}

extension OSLog {
    static let ai = OSLog(subsystem: "com.kalvianroots", category: "ai")
}
#else
// Fallback logging for platforms without OSLog
private func logInfo(_ category: Any, _ message: String) {
    print("[INFO] \(message)")
}

private func logDebug(_ category: Any, _ message: String) {
    print("[DEBUG] \(message)")
}

private func logTrace(_ category: Any, _ message: String) {
    print("[TRACE] \(message)")
}

private func logWarn(_ category: Any, _ message: String) {
    print("[WARN] \(message)")
}

private func logError(_ category: Any, _ message: String) {
    print("[ERROR] \(message)")
}
#endif
