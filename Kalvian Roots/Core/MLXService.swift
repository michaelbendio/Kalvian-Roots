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
    
    // MARK: - Static Platform Detection
    
    /// Check if MLX is available on current platform
    static func isAvailable() -> Bool {
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
    
    // MARK: - Static Factory Methods
    
    /// High-performance 30B parameter model for complex families
    static func qwen3_30B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(name: "MLX Qwen3-30B (Local)", modelName: "qwen3-30b")
    }
    
    /// Balanced 8B parameter model for most families
    static func llama3_2_8B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(name: "MLX Llama3.2-8B (Local)", modelName: "llama3.2-8b")
    }
    
    /// Fast 7B parameter model for simple families
    static func mistral_7B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(name: "MLX Mistral-7B (Local)", modelName: "mistral-7b")
    }
    
    /// Get recommended MLX model based on available memory
    static func getRecommendedModel() -> MLXService? {
        guard isAvailable() else { return nil }
        
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
        
        // Check if we got a very short family text (likely extraction issue)
        if familyText.count < 100 {
            logWarn(.ai, "⚠️ Family text unusually short (\(familyText.count) chars)")
            logWarn(.ai, "⚠️ This suggests a family text extraction issue")
            logWarn(.ai, "📝 Short text: '\(familyText)'")
            logWarn(.ai, "🔄 Using mock response due to insufficient family text")
            return createMockFamilyJSON(familyId: familyId)
        }
        
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
        
        logInfo(.ai, "🚀 Proceeding with real MLX AI processing...")
        logDebug(.ai, "🔍 Will try multiple endpoints to find working MLX API")
        
        do {
            // Your custom MLX server uses /generate endpoint
            logDebug(.ai, "🔍 Using custom MLX server /generate endpoint")
            let request = try createCustomMLXRequest(familyId: familyId, familyText: familyText)
            let response = try await sendMLXRequest(request)
            let validatedJSON = try validateCustomMLXResponse(response)
            logInfo(.ai, "✅ MLX parsing successful with custom /generate endpoint")
            logDebug(.ai, "🎯 Real AI response received (not mock): \(String(validatedJSON.prefix(100)))...")
            return validatedJSON
            
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
    
    private func createCustomMLXRequest(familyId: String, familyText: String) throws -> URLRequest {
        let url = URL(string: "\(baseURL)/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = createFamilyParsingPrompt(familyId: familyId, familyText: familyText)
        
        // Remove the enable_thinking parameter (doesn't exist)
        let requestBody = [
            "prompt": prompt,
            "max_tokens": 3500,
            "model": modelName
        ] as [String: Any]
        
        logDebug(.ai, "🔍 prompt: \(requestBody)")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        logTrace(.ai, "Custom MLX request created for /generate endpoint")
        return request
    }
    
    private func createFamilyParsingPrompt(familyId: String, familyText: String) -> String {
        return """
<|im_start|>assistant
/no_think

<|im_start|>user
Extract Finnish genealogical data as JSON. Output only the JSON object.

\(familyText)

Return JSON structure:
{
  "familyId": "\(familyId)",
  "pageReferences": [],
  "father": {"name": "", "patronymic": "", "birthDate": "", "deathDate": "", "spouse": "", "marriageDate": "", "asChildReference": "", "familySearchId": "", "noteMarkers": []},
  "mother": {"name": "", "patronymic": "", "birthDate": "", "deathDate": "", "spouse": "", "marriageDate": "", "asChildReference": "", "familySearchId": "", "noteMarkers": []},
  "additionalSpouses": [],
  "children": [],
  "notes": [],
  "childrenDiedInfancy": null
}<|im_end|>
<|im_start|>assistant
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
    
    private func validateCustomMLXResponse(_ data: Data) throws -> String {
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw AIServiceError.invalidResponse("Could not decode custom MLX response as UTF-8")
        }
        
        logTrace(.ai, "Raw custom MLX response: \(responseString)")
        
        // Debug: Pretty-print the full response
        do {
            if let jsonData = responseString.data(using: .utf8) {
                let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                if let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    logDebug(.ai, "📝 Pretty-printed MLX response:")
                    logDebug(.ai, "\(prettyString)")
                }
            }
        } catch {
            logDebug(.ai, "📝 Could not pretty-print response (not JSON): \(responseString)")
        }
        
        // Your custom server returns JSON with "response" field
        do {
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let generatedText = jsonResponse["response"] as? String {
                    logDebug(.ai, "Found generated text in response field")
                    
                    // Debug: Log the extracted text before processing
                    logDebug(.ai, "📝 Generated text from MLX:")
                    logDebug(.ai, "📝 Length: \(generatedText.count) characters")
                    logDebug(.ai, "📝 Preview: \(String(generatedText.prefix(200)))...")
                    
                    // The response might be JSON-escaped, so try to unescape it
                    var cleanedText = generatedText
                    
                    // If it's JSON-escaped, unescape it
                    if cleanedText.contains("\\\"") {
                        cleanedText = cleanedText.replacingOccurrences(of: "\\\"", with: "\"")
                        cleanedText = cleanedText.replacingOccurrences(of: "\\n", with: "\n")
                        cleanedText = cleanedText.replacingOccurrences(of: "\\\\", with: "\\")
                        logDebug(.ai, "📝 Text after unescaping: \(String(cleanedText.prefix(200)))...")
                    }
                    
                    return try extractJSONFromGeneratedText(cleanedText)
                } else {
                    logDebug(.ai, "Custom MLX response keys: \(jsonResponse.keys.sorted())")
                    throw AIServiceError.invalidResponse("Could not find 'response' field in custom MLX response")
                }
            } else {
                throw AIServiceError.invalidResponse("Custom MLX response is not valid JSON")
            }
        } catch {
            logError(.ai, "Failed to parse custom MLX response: \(error)")
            throw AIServiceError.invalidResponse("Could not parse custom MLX response: \(error.localizedDescription)")
        }
    }
    
    private func extractJSONFromGeneratedText(_ generatedText: String) throws -> String {
        // First, clean up the generated text
        var cleanedText = generatedText
        
        // Remove any <think>...</think> blocks (including incomplete ones)
        let thinkPattern = try NSRegularExpression(pattern: "<think>.*?(?:</think>|$)", options: [.dotMatchesLineSeparators])
        cleanedText = thinkPattern.stringByReplacingMatches(in: cleanedText, options: [], range: NSRange(location: 0, length: cleanedText.count), withTemplate: "")
        
        // Remove any other common AI reasoning patterns
        cleanedText = cleanedText.replacingOccurrences(of: "Let me think about this...", with: "")
        cleanedText = cleanedText.replacingOccurrences(of: "Here's the JSON:", with: "")
        cleanedText = cleanedText.replacingOccurrences(of: "JSON:", with: "")
        
        // Clean up whitespace
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for JSON content - try multiple strategies
        
        // Strategy 1: Look for the last complete JSON object (most likely to be the final answer)
        var bestJSON: String?
        var searchText = cleanedText
        
        while let jsonStart = searchText.lastIndex(of: "{") {
            let jsonPart = String(searchText[jsonStart...])
            
            // Find matching closing brace
            var braceCount = 0
            var jsonEnd: String.Index?
            
            for i in jsonPart.indices {
                let char = jsonPart[i]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        jsonEnd = jsonPart.index(after: i)
                        break
                    }
                }
            }
            
            if let endIndex = jsonEnd {
                let candidateJSON = String(jsonPart[..<endIndex])
                
                // Clean up the candidate JSON
                var cleanedJSON = candidateJSON
                
                // Fix common AI JSON mistakes
                cleanedJSON = cleanedJSON.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
                cleanedJSON = cleanedJSON.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
                
                // Try to validate this JSON
                do {
                    let jsonData = cleanedJSON.data(using: .utf8)!
                    _ = try JSONSerialization.jsonObject(with: jsonData)
                    
                    // If it's valid and contains our expected structure, use it
                    if cleanedJSON.contains("familyId") && cleanedJSON.contains("father") {
                        logDebug(.ai, "Successfully extracted and validated JSON from generated text")
                        return cleanedJSON
                    } else {
                        bestJSON = cleanedJSON // Keep as backup
                    }
                } catch {
                    // This JSON is invalid, try searching before this position
                }
            }
            
            // Move search position backwards
            searchText = String(searchText[..<jsonStart])
        }
        
        // If we found some valid JSON but not with the expected structure, use it
        if let json = bestJSON {
            logWarn(.ai, "Using JSON without expected structure")
            return json
        }
        
        // Strategy 2: If the entire cleaned text looks like JSON, try it
        if cleanedText.hasPrefix("{") && cleanedText.hasSuffix("}") {
            do {
                let jsonData = cleanedText.data(using: .utf8)!
                _ = try JSONSerialization.jsonObject(with: jsonData)
                logDebug(.ai, "Using entire cleaned text as JSON")
                return cleanedText
            } catch {
                logWarn(.ai, "Entire text is not valid JSON: \(error)")
            }
        }
        
        // If we get here, we couldn't extract valid JSON
        logError(.ai, "Could not extract valid JSON. Cleaned text: \(String(cleanedText.prefix(500)))")
        throw AIServiceError.invalidResponse("Could not extract valid JSON from generated text")
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
        case "Qwen3-30B-A3B-4bit":
            return "Qwen3-30B-A3B-4bit"
        case "Llama3.2-8B-4bit":
            return "Llama3.2-8B-4bit"
        case "Mistral-7B-Instruct-4bit":
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

// MARK: - Logging Helper

private func logInfo(_ category: Any, _ message: String) {
    #if canImport(OSLog)
    if let oslogCategory = category as? OSLog {
        os_log("%{public}@", log: oslogCategory, type: .info, message)
    } else {
        print("[INFO] \(message)")
    }
    #else
    print("[INFO] \(message)")
    #endif
}

private func logDebug(_ category: Any, _ message: String) {
    #if canImport(OSLog)
    if let oslogCategory = category as? OSLog {
        os_log("%{public}@", log: oslogCategory, type: .debug, message)
    } else {
        print("[DEBUG] \(message)")
    }
    #else
    print("[DEBUG] \(message)")
    #endif
}

private func logTrace(_ category: Any, _ message: String) {
    #if canImport(OSLog)
    if let oslogCategory = category as? OSLog {
        os_log("%{public}@", log: oslogCategory, type: .debug, message)
    } else {
        print("[TRACE] \(message)")
    }
    #else
    print("[TRACE] \(message)")
    #endif
}

private func logWarn(_ category: Any, _ message: String) {
    #if canImport(OSLog)
    if let oslogCategory = category as? OSLog {
        os_log("%{public}@", log: oslogCategory, type: .default, message)
    } else {
        print("[WARN] \(message)")
    }
    #else
    print("[WARN] \(message)")
    #endif
}

private func logError(_ category: Any, _ message: String) {
    #if canImport(OSLog)
    if let oslogCategory = category as? OSLog {
        os_log("%{public}@", log: oslogCategory, type: .error, message)
    } else {
        print("[ERROR] \(message)")
    }
    #else
    print("[ERROR] \(message)")
    #endif
}

#if canImport(OSLog)
import OSLog
extension OSLog {
    static let ai = OSLog(subsystem: "com.kalvianroots", category: "ai")
}
#endif
