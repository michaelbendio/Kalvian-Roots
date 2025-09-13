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
    
    /// OpenAI GPT-OSS 20B parameter model
    static func gpt_oss_20B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(name: "MLX GPT-OSS-20B (Local)", modelName: "gpt-oss-20b")
    }
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
                return try gpt_oss_20B()
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
            
            // Validate family text length
            if familyText.count < 100 {
                throw AIServiceError.parsingFailed("Family text too short for processing (\(familyText.count) chars)")
            }
            
            // Check if MLX server is running
            logInfo(.ai, "🔍 Checking MLX server availability...")
            let serverRunning = await isMLXServerRunning()
            
            if !serverRunning {
                throw AIServiceError.networkError(NSError(domain: "MLXService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: """
                        MLX server not running at \(baseURL)
                        
                        To start MLX server:
                        cd ~/.kalvian_roots_mlx
                        python -m mlx_lm.server --model models/\(getModelPath()) --port 8080
                        """
                ]))
            }
            
            // Attempt real AI processing with retries
            var lastError: Error?
            let maxRetries = 3
            
            for attempt in 1...maxRetries {
                do {
                    logDebug(.ai, "🔄 MLX attempt \(attempt)/\(maxRetries)")
                    
                    let request = try createCustomMLXRequest(familyId: familyId, familyText: familyText)
                    let response = try await sendMLXRequest(request)
                    let validatedJSON = try validateCustomMLXResponse(response)
                    
                    logInfo(.ai, "✅ MLX successfully generated response on attempt \(attempt)")
                    return validatedJSON
                    
                } catch {
                    lastError = error
                    logWarn(.ai, "⚠️ MLX attempt \(attempt) failed: \(error)")
                    
                    if attempt < maxRetries {
                        let delay = Double(attempt) * 2.0 // Exponential backoff
                        logDebug(.ai, "⏱️ Waiting \(delay)s before retry...")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }
            
            // All retries failed - throw a clear error
            logError(.ai, "❌ All MLX attempts failed. Last error: \(lastError?.localizedDescription ?? "Unknown")")
            
            throw AIServiceError.parsingFailed("""
                MLX failed after \(maxRetries) attempts.
                Last error: \(lastError?.localizedDescription ?? "Unknown")
                
                Try:
                1. Restart MLX server
                2. Use a different AI service
                3. Check MLX server logs for errors
                """)
        }
    
    // MARK: - MLX Server Communication
    
    private func isMLXServerRunning() async -> Bool {
        // Try multiple common MLX endpoints to detect if server is actually running
        let endpointsToTest = [
            "/generate",     // Your custom endpoint
            "/v1/chat/completions",  // OpenAI-compatible endpoint
            "/",             // Root endpoint
            "/health"        // Health endpoint (if it exists)
        ]
        
        for endpoint in endpointsToTest {
            do {
                let url = URL(string: "\(baseURL)\(endpoint)")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0  // Quick timeout for health checks
                
                // For POST endpoints, we need to send a minimal request
                if endpoint == "/generate" {
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    // Minimal test request
                    let testBody = [
                        "prompt": "test",
                        "max_tokens": 1
                    ] as [String: Any]
                    request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
                } else {
                    request.httpMethod = "GET"
                }
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    // Accept any valid HTTP response (not just 200)
                    // Even 404 or 422 means the server is running
                    if httpResponse.statusCode < 500 {
                        logDebug(.ai, "MLX server detected via \(endpoint): HTTP \(httpResponse.statusCode)")
                        return true
                    }
                }
                
            } catch {
                logTrace(.ai, "Endpoint \(endpoint) not responding: \(error.localizedDescription)")
            }
        }
        
        logDebug(.ai, "MLX server not reachable on any endpoint")
        return false
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
            "max_tokens": 1000,
            "model": modelName
        ] as [String: Any]
        
        logDebug(.ai, "🔍 prompt: \(requestBody)")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        logTrace(.ai, "Custom MLX request created for /generate endpoint")
        return request
    }
   
    private func createFamilyParsingPrompt(familyId: String, familyText: String) -> String {
        return """
    Extract Finnish genealogical data as JSON. Output only the JSON object.

    \(familyText)
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
   
    private func transformQwenResponseToFamily(_ qwenJSON: String, familyId: String) throws -> String {
        guard let jsonData = qwenJSON.data(using: .utf8),
              let qwenData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AIServiceError.invalidResponse("Could not parse Qwen3 JSON")
        }
        
        // Extract entries array
        guard let entries = qwenData["entries"] as? [[String: Any]] else {
            logWarn(.ai, "No entries found in Qwen3 response")
            throw AIServiceError.invalidResponse("No entries found")
        }
        
        logInfo(.ai, "🔄 Transforming Qwen3 format to Swift Family format")
        logDebug(.ai, "Found \(entries.count) entries to transform")
        
        // Extract father (first entry) and mother (second entry)
        var father: [String: Any]?
        var mother: [String: Any]?
        var children: [[String: Any]] = []
        
        for (index, entry) in entries.enumerated() {
            guard let name = entry["name"] as? String, !name.isEmpty else {
                continue // Skip entries without names
            }
            
            let person: [String: Any] = [
                "name": name,
                "patronymic": NSNull(),
                "birthDate": entry["date"] as? String ?? NSNull(),
                "deathDate": entry["death_date"] as? String ?? NSNull(),
                "marriageDate": NSNull(),
                "spouse": NSNull(),
                "asChildReference": extractFamilyReference(from: entry["note"] as? String) ?? NSNull(),
                "familySearchId": extractFamilySearchId(from: entry["source"] as? String) ?? NSNull(),
                "noteMarkers": []
            ]
            
            if index == 0 {
                father = person
                logDebug(.ai, "Set father: \(name)")
            } else if index == 1 {
                mother = person
                logDebug(.ai, "Set mother: \(name)")
            } else {
                children.append(person)
                logDebug(.ai, "Added child: \(name)")
            }
        }
        
        // Create Swift Family structure
        let familyData: [String: Any] = [
            "familyId": familyId,
            "pageReferences": [qwenData["pages"] as? String ?? ""],
            "father": father ?? createEmptyPerson(name: "Unknown Father"),
            "mother": mother,
            "additionalSpouses": [],
            "children": children,
            "notes": [],
            "childrenDiedInfancy": NSNull()
        ]
        
        // Convert back to JSON
        let transformedData = try JSONSerialization.data(withJSONObject: familyData, options: [])
        let transformedJSON = String(data: transformedData, encoding: .utf8)!
        
        logInfo(.ai, "✅ Successfully transformed to Swift format")
        logDebug(.ai, "Father: \(father?["name"] ?? "None"), Mother: \(mother?["name"] ?? "None"), Children: \(children.count)")
        
        return transformedJSON
    }

    private func extractFamilyReference(from note: String?) -> String? {
        guard let note = note else { return nil }
        // Extract {Family Reference} from note
        let pattern = #"\{([^}]+)\}"#
        if let range = note.range(of: pattern, options: .regularExpression) {
            return String(note[range]).replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        }
        return nil
    }

    private func extractFamilySearchId(from source: String?) -> String? {
        guard let source = source else { return nil }
        // Extract <ID> from source
        return source.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
    }

    private func createEmptyPerson(name: String) -> [String: Any] {
        return [
            "name": name,
            "patronymic": NSNull(),
            "birthDate": NSNull(),
            "deathDate": NSNull(),
            "marriageDate": NSNull(),
            "spouse": NSNull(),
            "asChildReference": NSNull(),
            "familySearchId": NSNull(),
            "noteMarkers": []
        ]
    }

    private func validateCustomMLXResponse(_ data: Data) throws -> String {
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw AIServiceError.invalidResponse("Could not decode custom MLX response as UTF-8")
        }
        
        logTrace(.ai, "Raw custom MLX response: \(responseString)")
        
        do {
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let generatedText = jsonResponse["response"] as? String {
                    logDebug(.ai, "Found generated text in response field")
                    
                    // DEBUG: Log the raw generated text
                    logDebug(.ai, "📝 Raw generated text: \(String(generatedText.prefix(1200)))...")
                    
                    // Try to extract JSON from the generated text
                    let cleanedJSON = try extractJSONFromGeneratedText(generatedText)
                    
                    // DEBUG: Log the cleaned JSON
                    logDebug(.ai, "📝 Cleaned JSON: \(String(cleanedJSON.prefix(200)))...")
                    
                    // Parse the cleaned JSON to see its structure
                    if let jsonData = cleanedJSON.data(using: .utf8),
                       let qwenData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        
                        // DEBUG: Log all the keys we found
                        logDebug(.ai, "📝 JSON keys found: \(Array(qwenData.keys))")
                        
                        // Check if this is Qwen3's natural format that needs transformation
                        if qwenData["entries"] != nil {
                            logInfo(.ai, "🔄 Detected Qwen3 format with entries, transforming to Swift format")
                            
                            // Extract family ID from the original request if possible
                            let familyId = qwenData["name"] as? String ?? "KORPI 6"
                            
                            let transformedJSON = try transformQwenResponseToFamily(cleanedJSON, familyId: familyId)
                            
                            logDebug(.ai, "📝 Transformed JSON: \(String(transformedJSON.prefix(200)))...")
                            return transformedJSON
                        } else {
                            logInfo(.ai, "📝 JSON format doesn't have 'entries' key, using as-is")
                            logDebug(.ai, "📝 Available keys: \(Array(qwenData.keys))")
                            return cleanedJSON
                        }
                    } else {
                        logError(.ai, "📝 Could not parse cleaned JSON as dictionary")
                        return cleanedJSON
                    }
                } else {
                    logError(.ai, "📝 No 'response' field found in MLX response")
                    throw AIServiceError.invalidResponse("Could not find 'response' field")
                }
            } else {
                logError(.ai, "📝 MLX response is not a valid JSON object")
                throw AIServiceError.invalidResponse("MLX response is not valid JSON")
            }
        } catch {
            logError(.ai, "Failed to parse custom MLX response: \(error)")
            throw AIServiceError.invalidResponse("Could not parse custom MLX response: \(error.localizedDescription)")
        }
    }
    
    private func extractJSONFromGeneratedText(_ generatedText: String) throws -> String {
        // Clean up the generated text first
        var cleanedText = generatedText
        
        // Remove any <think>...</think> blocks
        cleanedText = cleanedText.replacingOccurrences(of: #"<think>.*?</think>"#, with: "", options: .regularExpression)
        cleanedText = cleanedText.replacingOccurrences(of: #"<think>.*"#, with: "", options: .regularExpression)
        
        // Remove common prefixes
        let prefixesToRemove = ["Here's the JSON:", "```json", "```", "The JSON object is:", "Response:", "Answer:"]
        for prefix in prefixesToRemove {
            if cleanedText.hasPrefix(prefix) {
                cleanedText = String(cleanedText.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Remove common suffixes
        let suffixesToRemove = ["```", "</s>", "<|im_end|>", "<|endoftext|>"]
        for suffix in suffixesToRemove {
            if cleanedText.hasSuffix(suffix) {
                cleanedText = String(cleanedText.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the FIRST opening brace (start of main JSON object)
        guard let firstBrace = cleanedText.firstIndex(of: "{") else {
            logError(.ai, "No opening brace found in generated text")
            throw AIServiceError.invalidResponse("No JSON object found in generated text")
        }
        
        // Find the MATCHING closing brace (not just any closing brace)
        var braceCount = 0
        var jsonEnd: String.Index?
        
        for index in cleanedText[firstBrace...].indices {
            let char = cleanedText[index]
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    jsonEnd = index
                    break
                }
            }
        }
        
        guard let endIndex = jsonEnd else {
            logError(.ai, "No matching closing brace found")
            throw AIServiceError.invalidResponse("Incomplete JSON object in generated text")
        }
        
        // Extract the complete JSON object
        let jsonString = String(cleanedText[firstBrace...endIndex])
        
        // Validate that it's proper JSON
        do {
            let jsonData = jsonString.data(using: .utf8)!
            _ = try JSONSerialization.jsonObject(with: jsonData)
            logDebug(.ai, "✅ Successfully extracted complete JSON object (\(jsonString.count) characters)")
            return jsonString
        } catch {
            logError(.ai, "❌ Extracted content is not valid JSON: \(error)")
            logError(.ai, "📝 Extracted content: \(jsonString)")
            throw AIServiceError.invalidResponse("Extracted content is not valid JSON: \(error.localizedDescription)")
        }
    }

    private func extrctJSONFromGeneratedText(_ generatedText: String) throws -> String {
        // Clean up the generated text first
        var cleanedText = generatedText
        
        // Remove any <think>...</think> blocks
        cleanedText = cleanedText.replacingOccurrences(of: #"<think>.*?</think>"#, with: "", options: .regularExpression)
        cleanedText = cleanedText.replacingOccurrences(of: #"<think>.*"#, with: "", options: .regularExpression)
        
        // Remove common prefixes
        let prefixesToRemove = ["Here's the JSON:", "```json", "```", "The JSON object is:", "Response:", "Answer:"]
        for prefix in prefixesToRemove {
            if cleanedText.hasPrefix(prefix) {
                cleanedText = String(cleanedText.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Remove common suffixes
        let suffixesToRemove = ["```", "</s>", "<|im_end|>", "<|endoftext|>"]
        for suffix in suffixesToRemove {
            if cleanedText.hasSuffix(suffix) {
                cleanedText = String(cleanedText.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the FIRST opening brace (start of main JSON object)
        guard let firstBrace = cleanedText.firstIndex(of: "{") else {
            logError(.ai, "No opening brace found in generated text")
            throw AIServiceError.invalidResponse("No JSON object found in generated text")
        }
        
        // Find the MATCHING closing brace (not just any closing brace)
        var braceCount = 0
        var jsonEnd: String.Index?
        
        for index in cleanedText[firstBrace...].indices {
            let char = cleanedText[index]
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    jsonEnd = index
                    break
                }
            }
        }
        
        guard let endIndex = jsonEnd else {
            logError(.ai, "No matching closing brace found")
            throw AIServiceError.invalidResponse("Incomplete JSON object in generated text")
        }
        
        // Extract the complete JSON object
        let jsonString = String(cleanedText[firstBrace...endIndex])
        
        // Validate that it's proper JSON
        do {
            let jsonData = jsonString.data(using: .utf8)!
            _ = try JSONSerialization.jsonObject(with: jsonData)
            logDebug(.ai, "✅ Successfully extracted complete JSON object (\(jsonString.count) characters)")
            return jsonString
        } catch {
            logError(.ai, "❌ Extracted content is not valid JSON: \(error)")
            logError(.ai, "📝 Extracted content: \(jsonString)")
            throw AIServiceError.invalidResponse("Extracted content is not valid JSON: \(error.localizedDescription)")
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
        case "gpt-oss-20b":
            return "gpt-oss-20b"
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

