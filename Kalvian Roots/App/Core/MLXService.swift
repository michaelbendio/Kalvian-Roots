//
//  MLXService.swift
//  Kalvian Roots
//
//  Complete MLX service implementation for local AI family parsing
//  Updated to support: Phi-3.5-mini, Qwen2.5-14B, Qwen3-30B, Llama-3.1-8B, Mistral-7B
//

import Foundation

/**
 * MLX service for local AI processing using Apple Silicon
 *
 * Provides family parsing using local models
 */
class MLXService: AIService {
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
    
    // MARK: - Static Factory Methods for Your Five Models
    
    /// Phi-3.5-mini-instruct (3.8B) - Fast, structured output optimized
    static func phi3_5_mini() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(
            name: "MLX Phi-3.5-mini (Local)",
            modelName: "phi-3.5-mini",
            modelPath: "~/.kalvian_roots_mlx/models/Phi-3.5-mini-instruct"
        )
    }
    
    /// Qwen2.5-14B-Instruct - Excellent balance of speed and accuracy
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
    
    /// Qwen3-30B-A3B-4bit - High-performance for complex families
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
    
    /// Llama-3.1-8B-Instruct - Balanced general-purpose model
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
    
    /// Mistral-7B-Instruct-4bit - Fast processing for simple families
    static func mistral_7B() throws -> MLXService {
        guard isAvailable() else {
            throw AIServiceError.notConfigured("MLX not available on this platform")
        }
        return MLXService(
            name: "MLX Mistral-7B (Local)",
            modelName: "mistral-7b",
            modelPath: "~/.kalvian_roots_mlx/models/Mistral-7B-Instruct-4bit"
        )
    }
    
    /// Get recommended MLX model based on available memory
    static func getRecommendedModel() -> MLXService? {
        guard isAvailable() else { return nil }
        
        let memory = getSystemMemory() / (1024 * 1024 * 1024) // Convert to GB
        
        do {
            if memory >= 64 {
                // 64GB+ RAM: Use Qwen3-30B for best accuracy
                return try qwen3_30B()
            } else if memory >= 32 {
                // 32-64GB RAM: Use Qwen2.5-14B for balance
                return try qwen2_5_14B()
            } else if memory >= 16 {
                // 16-32GB RAM: Use Llama-3.1-8B
                return try llama3_1_8B()
            } else {
                // <16GB RAM: Use Phi-3.5-mini for speed
                return try phi3_5_mini()
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
        let endpointsToTest = [
            "/v1/chat/completions",
            "/generate",
            "/health"
        ]
        
        for endpoint in endpointsToTest {
            do {
                let url = URL(string: "\(baseURL)\(endpoint)")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                request.httpMethod = "GET"
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode < 500 {
                    logDebug(.ai, "MLX server detected via \(endpoint): HTTP \(httpResponse.statusCode)")
                    return true
                }
            } catch {
                logTrace(.ai, "Endpoint \(endpoint) not responding: \(error.localizedDescription)")
            }
        }
        
        logDebug(.ai, "MLX server not reachable on any endpoint")
        return false
    }
    
    private func createCustomMLXRequest(familyId: String, familyText: String) throws -> URLRequest {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = createFamilyParsingPrompt(familyId: familyId, familyText: familyText)
        
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 2000,
            "temperature": 0.1
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        logTrace(.ai, "MLX request created for OpenAI-compatible endpoint")
        return request
    }
    
    private func createFamilyParsingPrompt(familyId: String, familyText: String) -> String {
        return """
        Parse the following Finnish genealogical family record into JSON format.
        
        CRITICAL: Output ONLY valid JSON - no explanation, no markdown, no code blocks.
        
        Required JSON structure:
        {
          "familyId": "\(familyId)",
          "pageReferences": [],
          "father": { "name": "", "patronymic": "", "birthDate": "", "deathDate": "" },
          "mother": { "name": "", "patronymic": "", "spouse": "" },
          "children": [],
          "notes": []
        }
        
        Family text:
        \(familyText)
        """
    }
    
    private func sendMLXRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
        
        logTrace(.ai, "✅ Validated JSON response from MLX")
        return cleaned
    }
}
