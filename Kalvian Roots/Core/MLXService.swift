//
//  MLXService.swift
//  Kalvian Roots
//
//  Minimal MLX service implementation without conflicts
//

import Foundation

/**
 * Minimal MLX service that handles its own availability detection
 *
 * Only creates instances if MLX is actually available.
 * All platform detection is self-contained.
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
    
    // MARK: - AIService Protocol
    
    func configure(apiKey: String) throws {
        // MLX doesn't need API keys, but we can use this to test server connection
        logInfo(.ai, "🔧 Testing MLX server connection for \(name)")
        
        // For now, just log success
        logInfo(.ai, "✅ MLX service configured: \(name)")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 \(name) parsing family: \(familyId)")
        logDebug(.ai, "Using MLX model: \(modelName)")
        
        // For now, return a mock JSON response
        // TODO: Implement actual MLX server communication
        
        let mockJSON = """
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
          "children": [],
          "notes": ["MLX service is not fully implemented yet"],
          "childrenDiedInfancy": null
        }
        """
        
        logInfo(.ai, "✅ MLX mock response generated for \(familyId)")
        return mockJSON
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
