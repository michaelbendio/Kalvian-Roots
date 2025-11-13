//
//  AIServiceFactory.swift
//  Kalvian Roots
//
//  Factory for creating AI services with MLX auto-start support
//

import Foundation

/**
 * Factory for creating AI services
 * Supports cloud (DeepSeek) and local MLX models with auto-start
 */
class AIServiceFactory {
    
    /**
     * Create all available AI services for the current platform
     */
    static func createAvailableServices() -> [AIService] {
        logInfo(.ai, "🏭 Creating available AI services")
        
        var services: [AIService] = []
        
        // Cloud service: DeepSeek
        services.append(DeepSeekService())
        
        // Local MLX services (only on Apple Silicon macOS)
        #if os(macOS) && arch(arm64)
        if MLXService.isAvailable() {
            do {
                // Add only the three chosen models
                services.append(try MLXService.qwen3_30B())
                services.append(try MLXService.qwen2_5_14B())
                services.append(try MLXService.llama3_1_8B())
                
                logInfo(.ai, "✅ Added 3 MLX models to available services")
            } catch {
                logError(.ai, "❌ Failed to create MLX services: \(error)")
            }
        }
        #endif
        
        logInfo(.ai, "✅ Created \(services.count) AI services")
        logDebug(.ai, "Available services: \(services.map { $0.name }.joined(separator: ", "))")
        
        return services
    }
    
    /**
     * Get the recommended default service
     */
    static func getRecommendedService() -> String {
        #if os(macOS) && arch(arm64)
        // On Apple Silicon, recommend based on memory
        if MLXService.isAvailable() {
            let memory = getSystemMemory() / (1024 * 1024 * 1024)
            
            if memory >= 48 {
                logInfo(.ai, "🖥️ Recommending Qwen3-30B (48GB+ RAM)")
                return "MLX Qwen3-30B (Local)"
            } else if memory >= 24 {
                logInfo(.ai, "🖥️ Recommending Qwen2.5-14B (24-48GB RAM)")
                return "MLX Qwen2.5-14B (Local)"
            } else {
                logInfo(.ai, "🖥️ Recommending Llama-3.1-8B (<24GB RAM)")
                return "MLX Llama-3.1-8B (Local)"
            }
        }
        #endif
        
        // Default to DeepSeek for non-Apple Silicon or as fallback
        logInfo(.ai, "🖥️ Recommending DeepSeek as default AI service")
        return "DeepSeek"
    }
    
    /**
     * Get service by name
     */
    static func getService(named serviceName: String) -> AIService? {
        let services = createAvailableServices()
        return services.first { $0.name == serviceName }
    }
    
    /**
     * Check if a service is available
     */
    static func isServiceAvailable(_ serviceName: String) -> Bool {
        return getService(named: serviceName) != nil
    }
    
    /**
     * Get services grouped by type for UI display
     */
    static func getServicesByType() -> (local: [AIService], cloud: [AIService]) {
        let services = createAvailableServices()
        let local = services.filter { service in
            service.name.contains("MLX") || service.name.contains("Ollama")
        }
        let cloud = services.filter { service in
            !service.name.contains("MLX") &&
            !service.name.contains("Ollama") &&
            !service.name.contains("Mock")
        }
        return (local: local, cloud: cloud)
    }
    
    /**
     * Get MLX model name from service name
     */
    static func getMLXModelName(from serviceName: String) -> String? {
        // Map service names to MLX model identifiers
        let mapping: [String: String] = [
            "MLX Qwen3-30B (Local)": "qwen3-30b",
            "MLX Qwen2.5-14B (Local)": "qwen2.5-14b",
            "MLX Llama-3.1-8B (Local)": "llama-3.1-8b"
        ]
        
        return mapping[serviceName]
    }
    
    /**
     * Check if service is an MLX service
     */
    static func isMLXService(_ serviceName: String) -> Bool {
        return serviceName.contains("MLX")
    }
    
    /**
     * Get setup instructions for missing services
     */
    static func getSetupInstructions(for serviceName: String) -> String? {
        if serviceName.contains("DeepSeek") {
            return "DeepSeek API key required. Get one at: https://platform.deepseek.com/"
        }
        
        if serviceName.contains("MLX") {
            return """
                MLX requires:
                1. Apple Silicon Mac
                2. MLX installed: pip install mlx-lm
                3. Models downloaded to ~/.kalvian_roots_mlx/models/
                
                Server will auto-start when you select a model.
                """
        }
        
        return nil
    }
    
    /**
     * Validate service configuration
     */
    static func validateServiceConfiguration() -> [String] {
        var issues: [String] = []
        let services = createAvailableServices()
        
        // Check if any services are configured
        let configuredServices = services.filter { $0.isConfigured }
        if configuredServices.isEmpty {
            issues.append("No AI services are configured. Please add API keys or enable MLX.")
        }
        
        // Check for specific service issues
        for service in services {
            if !service.isConfigured {
                if let setupInstructions = getSetupInstructions(for: service.name) {
                    issues.append("\(service.name): \(setupInstructions)")
                }
            }
        }
        
        return issues
    }
    
    // MARK: - Private Helpers
    
    /**
     * Get system memory in bytes
     */
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
