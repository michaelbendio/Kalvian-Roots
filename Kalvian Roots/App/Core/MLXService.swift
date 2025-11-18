//
//  MLXService.swift
//  Kalvian Roots
//
//  Complete MLX service implementation for local AI family parsing
//  Optimized for: Qwen3-30B, Qwen2.5-14B, Llama-3.1-8B
//

import Foundation

/**
 * MLX service for local AI processing using Apple Silicon
 *
 * Provides family parsing using local models optimized for genealogical text
 */
class MLXService: AIService {
    #if DEBUG
    /// Enable to write request/response payloads to temporary files for inspection
    static var debugLoggingEnabled: Bool = false
    #endif

    #if DEBUG
    /// Writes data to a temporary file and logs the path; returns the URL if successful
    @discardableResult
    private static func writeTempFile(named name: String, data: Data) -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        do {
            try data.write(to: url)
            print("[MLXService] Wrote temp file:", url.path)
            return url
        } catch {
            print("[MLXService] Failed to write temp file \(name):", error.localizedDescription)
            return nil
        }
    }

    /// Writes string to a temporary file using UTF-8 encoding
    @discardableResult
    private static func writeTempFile(named name: String, text: String) -> URL? {
        guard let data = text.data(using: .utf8) else { return nil }
        return writeTempFile(named: name, data: data)
    }
    #endif

    let name: String
    private let modelName: String
    private let modelPath: String
    private let baseURL = "http://127.0.0.1:8080"
    
    var isConfigured: Bool {
        // MLX is always configured if it was created
        return true
    }
    
    // MARK: - Private Initializer
    
    private init(name: String, modelName: String, modelPath: String) {
        self.name = name
        self.modelName = modelName
        self.modelPath = modelPath
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
    
    // MARK: - Static Factory Methods for Three Chosen Models
    
    /// Qwen3-30B-A3B-4bit - Best accuracy for complex families
    static func qwen3_30B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(
            name: "MLX Qwen3-30B (Local)",
            modelName: "qwen3-30b",
            modelPath: "~/.kalvian_roots_mlx/models/Qwen3-30B-A3B-4bit"
        )
    }
    
    /// Qwen2.5-14B-Instruct - Balanced speed and accuracy
    static func qwen2_5_14B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(
            name: "MLX Qwen2.5-14B (Local)",
            modelName: "qwen2.5-14b",
            modelPath: "~/.kalvian_roots_mlx/models/Qwen2.5-14B-Instruct"
        )
    }
    
    /// Llama-3.1-8B-Instruct - Fast processing for simple families
    static func llama3_1_8B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(
            name: "MLX Llama-3.1-8B (Local)",
            modelName: "llama-3.1-8b",
            modelPath: "~/.kalvian_roots_mlx/models/Llama-3.1-8B-Instruct"
        )
    }
    
    /// Get recommended MLX model based on available memory
    static func getRecommendedModel() -> MLXService? {
        guard isAvailable() else { return nil }
        
        let memory = getSystemMemory() / (1024 * 1024 * 1024) // Convert to GB
        
        do {
            if memory >= 48 {
                // 48GB+ RAM: Use Qwen3-30B for best accuracy
                return try qwen3_30B()
            } else if memory >= 24 {
                // 24-48GB RAM: Use Qwen2.5-14B for balance
                return try qwen2_5_14B()
            } else {
                // <24GB RAM: Use Llama-3.1-8B for speed
                return try llama3_1_8B()
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
        // MLX doesn't need API keys
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
                    
                    The server should auto-start when you select this model.
                    If it doesn't, check:
                    1. MLX is installed (pip install mlx-lm)
                    2. Model exists at: \(modelPath)
                    3. No firewall blocking localhost:8080
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
        
        // All retries failed
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
        // First try a quick HEAD on root
        do {
            if let url = URL(string: "\(baseURL)/") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                request.httpMethod = "HEAD"
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    logDebug(.ai, "✅ MLX server HEAD / responded: HTTP \(http.statusCode)")
                    return http.statusCode > 0
                }
            }
        } catch {
            // ignore and try next probe
        }
        
        // Try GET /health (commonly exposed by mlx_lm.server)
        do {
            if let url = URL(string: "\(baseURL)/health") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                request.httpMethod = "GET"
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    logDebug(.ai, "✅ MLX server GET /health responded: HTTP \(http.statusCode)")
                    return http.statusCode > 0
                }
            }
        } catch {
            // ignore and try next probe
        }
        
        // Final fallback: POST a minimal body to /v1/chat/completions and
        // consider any HTTP response as proof that the server is reachable
        do {
            if let url = URL(string: "\(baseURL)/v1/chat/completions") {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 5.0
                let minimalBody: [String: Any] = [
                    "model": NSString(string: modelPath).expandingTildeInPath,
                    "messages": [],
                    "max_tokens": 1
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: minimalBody)
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    logDebug(.ai, "✅ MLX server POST /v1/chat/completions responded: HTTP \(http.statusCode)")
                    return true
                }
            }
        } catch {
            logTrace(.ai, "❌ MLX server not responding to probes: \(error.localizedDescription)")
        }
        
        return false
    }
    
    private func createCustomMLXRequest(familyId: String, familyText: String) throws -> URLRequest {
        // Create the prompt for MLX with OpenAI-compatible format
        let systemPrompt = """
            You are a Finnish genealogy expert specializing in extracting structured data.
            Extract the family information and return ONLY valid JSON with no additional text.
            Use the couples-based structure to handle remarriages properly.
            PRESERVE all original formatting including 'n' prefixes for approximate dates.
            """
        
        let userPrompt = createPrompt(familyId: familyId, familyText: familyText)
        
        let requestBody: [String: Any] = [
            "model": NSString(string: modelPath).expandingTildeInPath,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.1,
            "max_tokens": 4000
        ]
        
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw AIServiceError.invalidConfiguration("Invalid MLX server URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120.0 // 2 minutes for complex families

        #if DEBUG
        if MLXService.debugLoggingEnabled {
            if let body = request.httpBody {
                _ = MLXService.writeTempFile(named: "mlx_request_body.json", data: body)
            }
            let headers = request.allHTTPHeaderFields ?? [:]
            let meta = [
                "url": request.url?.absoluteString ?? "<nil>",
                "method": request.httpMethod ?? "<nil>",
                "timeout": String(request.timeoutInterval),
                "headers": headers
            ] as [String : Any]
            if let metaData = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
                _ = MLXService.writeTempFile(named: "mlx_request_meta.json", data: metaData)
            }
        }
        #endif

        return request
    }
    
    private func createPrompt(familyId: String, familyText: String) -> String {
        return """
        Extract family \(familyId) into this EXACT JSON structure.
        CRITICAL: Return ONLY the JSON object - no markdown, no explanation, no ```json tags.

        JSON SCHEMA TO USE:
        {
          "familyId": "string",
          "pageReferences": ["array of page numbers as strings"],
          "couples": [
            {
              "husband": {
                "name": "string (given name only)",
                "patronymic": "string or null",
                "birthDate": "string or null", 
                "deathDate": "string or null (keep 'isoviha' as-is)",
                "asChild": "string or null (from {family ref})",
                "familySearchId": "string or null (from <ID>)",
                "noteMarkers": []
              },
              "wife": {
                "name": "string",
                "patronymic": "string or null",
                "birthDate": "string or null",
                "deathDate": "string or null",
                "asChild": "string or null",
                "familySearchId": "string or null",
                "noteMarkers": []
              },
              "marriageDate": "string or null (2-digit year, MAY include 'n' prefix)",
              "fullMarriageDate": "string or null (dd.mm.yyyy, MAY include 'n' prefix)",
              "children": [
                {
                  "name": "string",
                  "birthDate": "string or null",
                  "deathDate": "string or null",
                  "marriageDate": "string or null",
                  "spouse": "string or null",
                  "asParent": "string or null",
                  "familySearchId": "string or null",
                  "noteMarkers": []
                }
              ],
              "childrenDiedInfancy": null,
              "coupleNotes": []
            }
          ],
          "notes": ["array of family notes"],
          "noteDefinitions": {"*": "note text"}
        }

        EXTRACTION RULES:
        1. Parse ONLY family \(familyId) - ignore any other families in the text
        2. Create a separate couple entry for each marriage
        3. If a person appears in multiple marriages, they appear in multiple couples
        4. Extract dates EXACTLY as written, preserving ALL formatting:
           - Keep historical periods like "isoviha" as-is
           - **CRITICAL**: Keep "n" prefix for approximate dates (e.g., "n 1730", "n 30")
           - Do NOT strip or remove the "n " prefix - it indicates an approximate date
        5. **DEATH DATES - CRITICAL**:
           - Death dates ONLY appear after the † symbol
           - Lines ending with codes like "-94 Kokkola" or "-92 Veteli" are NOT death dates
           - These codes indicate migration/relocation, not death
           - ONLY extract deathDate if explicitly preceded by † symbol
        6. Marriage dates: 
           - Store 2-digit as marriageDate (e.g., "30" or "n 30")
           - Store full date as fullMarriageDate (e.g., "01.02.1730" or "n 1730")
           - **PRESERVE** the "n " prefix in BOTH fields if present
        7. Extract {family references} as asChild or asParent (strip the curly braces)
        8. Extract <IDs> as familySearchId (strip the angle brackets)
        9. Note markers (*) go in noteMarkers array, definitions in noteDefinitions

        DETERMINING COUPLES:
        - Look for "II puoliso" or "III puoliso" to identify additional marriages
        - The person who survives and remarries appears in multiple couples
        - Use death dates and marriage dates to determine the correct sequence
        - Each "Lapset" (Children) section belongs to the couple above it

        Family text to parse:
        \(familyText)
        """
    }
    
    private func sendMLXRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        #if DEBUG
        if MLXService.debugLoggingEnabled {
            if let http = response as? HTTPURLResponse {
                let headers = http.allHeaderFields
                let meta: [String: Any] = [
                    "statusCode": http.statusCode,
                    "url": http.url?.absoluteString ?? "<nil>",
                    "headers": headers
                ]
                if let metaData = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
                    _ = MLXService.writeTempFile(named: "mlx_response_meta.json", data: metaData)
                }
            }
            _ = MLXService.writeTempFile(named: "mlx_response_raw.bin", data: data)
            if let asText = String(data: data, encoding: .utf8) {
                _ = MLXService.writeTempFile(named: "mlx_response_raw.txt", text: asText)
            }
        }
        #endif
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.networkError(NSError(domain: "MLXService", code: -1))
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logError(.ai, "❌ MLX API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AIServiceError.apiError("MLX returned status \(httpResponse.statusCode)")
        }
        
        return data
    }
    
    private func validateCustomMLXResponse(_ data: Data) throws -> String {
        #if DEBUG
        if MLXService.debugLoggingEnabled {
            _ = MLXService.writeTempFile(named: "mlx_envelope_raw.json", data: data)
        }
        #endif

        // Parse OpenAI-compatible response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.invalidResponse("Invalid MLX response structure")
        }
        
        // Clean any markdown formatting
        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate it's actual JSON
        guard let jsonData = cleaned.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: jsonData) else {
            throw AIServiceError.invalidResponse("Response is not valid JSON")
        }

        #if DEBUG
        if MLXService.debugLoggingEnabled {
            _ = MLXService.writeTempFile(named: "mlx_cleaned.json", text: cleaned)
        }
        #endif
        
        logTrace(.ai, "✅ Validated JSON response from MLX")
        return cleaned
    }
}

