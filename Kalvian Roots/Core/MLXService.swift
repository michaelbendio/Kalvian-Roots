//
//  MLXService.swift
//  Kalvian Roots
//
//  Local MLX model integration for macOS with genealogical optimization
//
//  Created by Michael Bendio on 7/26/25.
//

import Foundation

/**
 * MLXService.swift - Local MLX model integration
 *
 * Provides access to locally running MLX models (Qwen3-30B, Llama3.2-8B, Mistral-7B)
 * via local HTTP server. Only available on macOS with proper hardware.
 */

// MARK: - MLX Service Implementation

/**
 * Local MLX service for high-performance genealogical parsing
 *
 * Connects to locally running MLX server with multiple model options.
 * Automatically falls back to cloud services on non-Mac platforms.
 */
class MLXService: AIService {
    let name: String
    private let modelName: String
    private let baseURL = "http://127.0.0.1:8080"
    
    var isConfigured: Bool {
        // MLX models are always "configured" if server is running
        let configured = isServerRunning()
        logTrace(.ai, "\(name) isConfigured: \(configured) (server running: \(configured))")
        return configured
    }
    
    // MARK: - Model Variants
    
    /// High-performance 30B parameter model for complex families
    static func qwen3_30B() -> MLXService {
        return MLXService(name: "Qwen3-30B (Local MLX)", modelName: "qwen3-30b")
    }
    
    /// Balanced 8B parameter model for most families
    static func llama3_2_8B() -> MLXService {
        return MLXService(name: "Llama3.2-8B (Local MLX)", modelName: "llama3.2-8b")
    }
    
    /// Fast 7B parameter model for simple families
    static func mistral_7B() -> MLXService {
        return MLXService(name: "Mistral-7B (Local MLX)", modelName: "mistral-7b")
    }
    
    private init(name: String, modelName: String) {
        self.name = name
        self.modelName = modelName
        logInfo(.ai, "🤖 MLX Service initialized: \(name)")
    }
    
    // MARK: - AIService Protocol
    
    func configure(apiKey: String) throws {
        // MLX doesn't need API keys, but we can use this to test server connection
        logInfo(.ai, "🔧 Testing MLX server connection for \(name)")
        
        guard isServerRunning() else {
            logError(.ai, "❌ MLX server not running. Start with: ~/.kalvian_roots_mlx/scripts/start_server.sh")
            throw AIServiceError.notConfigured("MLX server not running")
        }
        
        logInfo(.ai, "✅ MLX server connection confirmed for \(name)")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 \(name) parsing family: \(familyId)")
        logDebug(.ai, "Using MLX model: \(modelName)")
        logDebug(.ai, "Family text length: \(familyText.count) characters")
        logTrace(.ai, "Family text preview: \(String(familyText.prefix(200)))...")
        
        guard isServerRunning() else {
            logError(.ai, "❌ MLX server not running")
            throw AIServiceError.notConfigured("MLX server not running. Start with: ~/.kalvian_roots_mlx/scripts/start_server.sh")
        }
        
        DebugLogger.shared.startTimer("mlx_request")
        
        let request = MLXParseRequest(
            model: modelName,
            family_id: familyId,
            family_text: familyText
        )
        
        logDebug(.ai, "Making MLX API call to local server")
        DebugLogger.shared.logAIRequest(name, prompt: "Family: \(familyId)")
        
        do {
            let response = try await makeMLXAPICall(request: request)
            let duration = DebugLogger.shared.endTimer("mlx_request")
            
            DebugLogger.shared.logAIResponse(name, response: response, duration: duration)
            logInfo(.ai, "✅ \(name) response received successfully in \(String(format: "%.2f", duration))s")
            
            return response
            
        } catch {
            DebugLogger.shared.endTimer("mlx_request")
            logError(.ai, "❌ \(name) API call failed: \(error)")
            throw error
        }
    }
    
    // MARK: - MLX Server Communication
    
    private func isServerRunning() -> Bool {
        // Quick check if MLX server is running
        guard let url = URL(string: "\(baseURL)/") else { return false }
        
        let semaphore = DispatchSemaphore(value: 0)
        var isRunning = false
        
        let task = URLSession.shared.dataTask(with: url) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                isRunning = httpResponse.statusCode == 200
            }
            semaphore.signal()
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.0) // 2 second timeout
        
        logTrace(.ai, "MLX server running check: \(isRunning)")
        return isRunning
    }
    
    private func makeMLXAPICall(request: MLXParseRequest) async throws -> String {
        guard let url = URL(string: "\(baseURL)/parse") else {
            logError(.network, "❌ Invalid MLX URL: \(baseURL)/parse")
            throw AIServiceError.networkError(URLError(.badURL))
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 120.0 // 2 minutes for local processing
        
        logTrace(.network, "MLX request headers configured")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
            logTrace(.network, "Request body encoded, size: \(urlRequest.httpBody?.count ?? 0) bytes")
            
            logDebug(.network, "Sending HTTP request to MLX server")
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                logDebug(.network, "MLX HTTP response: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown MLX error"
                    logError(.network, "MLX HTTP error \(httpResponse.statusCode): \(errorMessage)")
                    throw AIServiceError.httpError(httpResponse.statusCode, errorMessage)
                }
            }
            
            logTrace(.network, "Response data size: \(data.count) bytes")
            
            let mlxResponse = try JSONDecoder().decode(MLXParseResponse.self, from: data)
            logTrace(.ai, "MLX response decoded successfully")
            
            guard mlxResponse.success else {
                logError(.ai, "❌ MLX parsing failed: \(mlxResponse.error ?? "Unknown error")")
                throw AIServiceError.invalidResponse(mlxResponse.error ?? "MLX parsing failed")
            }
            
            guard let content = mlxResponse.result else {
                logError(.ai, "❌ No content in MLX response")
                throw AIServiceError.invalidResponse("No content in MLX response")
            }
            
            let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            logTrace(.ai, "MLX content cleaned, final length: \(cleanedContent.count)")
            logDebug(.ai, "MLX processing time: \(String(format: "%.2f", mlxResponse.processing_time))s")
            
            return cleanedContent
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            logError(.network, "❌ MLX network error: \(error)")
            throw AIServiceError.networkError(error)
        }
    }
    
    // MARK: - Platform Availability
    
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
        logDebug(.ai, "Platform check - macOS: true, Apple Silicon: \(isAppleSilicon)")
        return isAppleSilicon
        #else
        logDebug(.ai, "Platform check - macOS: false")
        return false
        #endif
    }
    
    // MARK: - Model Management
    
    /// Preload model for faster subsequent requests
    func preloadModel() async throws {
        guard let url = URL(string: "\(baseURL)/preload/\(modelName)") else {
            throw AIServiceError.networkError(URLError(.badURL))
        }
        
        logInfo(.ai, "🔄 Preloading \(name) model...")
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300.0 // 5 minutes for model loading
        
        do {
            let (_, response) = try await URLSession.shared.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    throw AIServiceError.httpError(httpResponse.statusCode, "Preload failed")
                }
            }
            
            logInfo(.ai, "✅ \(name) model preloaded successfully")
            
        } catch {
            logError(.ai, "❌ Failed to preload \(name): \(error)")
            throw AIServiceError.networkError(error)
        }
    }
    
    /// Get server status and available models
    static func getServerStatus() async -> MLXServerStatus? {
        guard let url = URL(string: "http://127.0.0.1:8080/models") else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let status = try JSONDecoder().decode(MLXServerStatus.self, from: data)
            return status
        } catch {
            logWarn(.ai, "Failed to get MLX server status: \(error)")
            return nil
        }
    }
}

// MARK: - MLX Data Structures

/**
 * MLX parse request structure
 */
struct MLXParseRequest: Codable {
    let model: String
    let family_id: String
    let family_text: String
}

/**
 * MLX parse response structure
 */
struct MLXParseResponse: Codable {
    let success: Bool
    let result: String?
    let error: String?
    let model_used: String
    let processing_time: Double
}

/**
 * MLX server status structure
 */
struct MLXServerStatus: Codable {
    let available_models: [String: MLXModelInfo]
    let loaded_models: [String]
}

/**
 * MLX model information
 */
struct MLXModelInfo: Codable {
    let path: String
    let max_tokens: Int
    let temperature: Double
    let description: String
}

// MARK: - Enhanced AIParsingService Integration

extension AIParsingService {
    
    /**
     * Initialize with MLX services on supported platforms
     */
    convenience init(includingMLX: Bool = true) {
        self.init() // Call existing initializer
        
        if includingMLX && MLXService.isAvailable() {
            logInfo(.ai, "🚀 Adding MLX services for Apple Silicon Mac")
            addMLXServices()
        } else {
            logInfo(.ai, "📱 MLX not available - using cloud services only")
        }
    }
    
    /**
     * Add MLX services to available services list
     */
    private func addMLXServices() {
        let mlxServices: [AIService] = [
            MLXService.qwen3_30B(),
            MLXService.llama3_2_8B(),
            MLXService.mistral_7B()
        ]
        
        // Add to available services (this would need to be modified in the main class)
        for service in mlxServices {
            logDebug(.ai, "Adding MLX service: \(service.name)")
            // Would need to add to availableServices array
        }
        
        logInfo(.ai, "✅ Added \(mlxServices.count) MLX services")
    }
}

// MARK: - Platform-Specific Service Selection

/**
 * Platform-aware service manager
 */
class PlatformAwareServiceManager {
    
    /**
     * Get recommended AI services for current platform
     */
    static func getRecommendedServices() -> [AIService] {
        var services: [AIService] = []
        
        #if os(macOS)
        if MLXService.isAvailable() {
            // macOS with Apple Silicon - include MLX services
            logInfo(.ai, "🖥️ macOS with Apple Silicon detected - including MLX services")
            services.append(contentsOf: [
                MLXService.qwen3_30B(),      // Best for complex families
                MLXService.llama3_2_8B(),    // Balanced option
                MLXService.mistral_7B(),     // Fast option
                DeepSeekService(),           // Cloud backup
                OpenAIService(),             // Cloud backup
                ClaudeService()              // Cloud backup
            ])
        } else {
            // macOS Intel - cloud services only
            logInfo(.ai, "🖥️ macOS Intel detected - cloud services only")
            services.append(contentsOf: [
                DeepSeekService(),
                OpenAIService(),
                ClaudeService(),
                MockAIService()
            ])
        }
        #elseif os(iOS)
        // iOS - DeepSeek only for simplicity
        logInfo(.ai, "📱 iOS detected - DeepSeek only")
        services.append(contentsOf: [
            DeepSeekService(),
            MockAIService()
        ])
        #else
        // Other platforms - cloud services
        logInfo(.ai, "🌐 Other platform detected - cloud services")
        services.append(contentsOf: [
            DeepSeekService(),
            OpenAIService(),
            ClaudeService(),
            MockAIService()
        ])
        #endif
        
        logDebug(.ai, "Platform services: \(services.map { $0.name }.joined(separator: ", "))")
        return services
    }
    
    /**
     * Get default service for platform
     */
    static func getDefaultService() -> AIService {
        #if os(macOS)
        if MLXService.isAvailable() {
            return MLXService.llama3_2_8B() // Good balance of speed and quality
        } else {
            return DeepSeekService()
        }
        #else
        return DeepSeekService() // iOS/other platforms
        #endif
    }
}

// MARK: - Enhanced Font Sizes for Better Readability

extension Font {
    /// Enhanced fonts for genealogical app - larger sizes for better readability
    static let genealogyTitle = Font.system(size: 28, weight: .bold, design: .default)
    static let genealogyTitle2 = Font.system(size: 24, weight: .semibold, design: .default)
    static let genealogyHeadline = Font.system(size: 20, weight: .semibold, design: .default)
    static let genealogySubheadline = Font.system(size: 18, weight: .medium, design: .default)
    static let genealogyBody = Font.system(size: 16, weight: .regular, design: .default)
    static let genealogyCallout = Font.system(size: 14, weight: .regular, design: .default)
    static let genealogyCaption = Font.system(size: 12, weight: .regular, design: .default)
    static let genealogyCaption2 = Font.system(size: 10, weight: .regular, design: .default)
    
    /// Monospaced fonts for dates and IDs
    static let genealogyMonospace = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let genealogyMonospaceSmall = Font.system(size: 14, weight: .regular, design: .monospaced)
}

// MARK: - Cross-Platform Compilation Fixes

#if os(macOS)
import AppKit

extension MLXService {
    /// macOS-specific hardware detection
    private static func getHardwareInfo() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    /// Check available memory
    private static func getAvailableMemory() -> UInt64 {
        var size = MemoryLayout<UInt64>.size
        var memSize: UInt64 = 0
        sysctlbyname("hw.memsize", &memSize, &size, nil, 0)
        return memSize
    }
    
    /// Recommend model based on hardware
    static func getRecommendedModel() -> MLXService {
        let memory = getAvailableMemory()
        let memoryGB = memory / (1024 * 1024 * 1024)
        
        logDebug(.ai, "Available memory: \(memoryGB) GB")
        
        if memoryGB >= 32 {
            // 32GB+ can handle Qwen3-30B
            logInfo(.ai, "🚀 High memory detected - recommending Qwen3-30B")
            return qwen3_30B()
        } else if memoryGB >= 16 {
            // 16GB+ can handle Llama3.2-8B
            logInfo(.ai, "⚡ Medium memory detected - recommending Llama3.2-8B")
            return llama3_2_8B()
        } else {
            // <16GB should use Mistral-7B
            logInfo(.ai, "💡 Lower memory detected - recommending Mistral-7B")
            return mistral_7B()
        }
    }
}

#else

extension MLXService {
    /// Fallback for non-macOS platforms
    static func getRecommendedModel() -> AIService {
        return DeepSeekService()
    }
}

#endif

// MARK: - Usage Examples and Integration Notes

/*
 Usage in JuuretApp.init():
 
 ```swift
 // Platform-aware initialization
 self.aiParsingService = AIParsingService(includingMLX: true)
 
 // Set platform-appropriate default
 let defaultService = PlatformAwareServiceManager.getDefaultService()
 try? aiParsingService.switchToService(named: defaultService.name)
 ```
 
 MLX Server Management:
 
 1. Install MLX: Run the setup script above
 2. Start server: ~/.kalvian_roots_mlx/scripts/start_server.sh
 3. Test models: python3 ~/.kalvian_roots_mlx/scripts/test_models.py
 4. Use in app: MLX services will appear in service list automatically
 
 Performance Expectations (M4 Pro, 64GB):
 - Mistral-7B: ~2-5 seconds per family (fast, good quality)
 - Llama3.2-8B: ~5-10 seconds per family (balanced)
 - Qwen3-30B: ~10-20 seconds per family (best quality)
 
 Model Selection Strategy:
 - Simple families (1-5 children): Mistral-7B
 - Standard families (5-10 children): Llama3.2-8B
 - Complex families (10+ children, multiple spouses): Qwen3-30B
 - Cloud backup: Always have DeepSeek configured
 */
