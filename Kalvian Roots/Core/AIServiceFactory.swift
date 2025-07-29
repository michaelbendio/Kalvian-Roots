//
//  AIServiceFactory.swift
//  Kalvian Roots
//
//  Clean factory for creating platform-appropriate AI services
//

import Foundation

/**
 * Clean factory for creating AI services without duplicate declarations
 *
 * This factory only creates available services - no platform detection logic here.
 * Platform detection is handled by individual service classes.
 */
class AIServiceFactory {
    
    /**
     * Create all available AI services for the current platform
     */
    static func createAvailableServices() -> [AIService] {
        logInfo(.ai, "🏭 Creating available AI services")
        
        var services: [AIService] = []
        
        // Always add cloud services
        services.append(OpenAIService())
        services.append(ClaudeService())
        services.append(DeepSeekService())
        services.append(OllamaService())
        services.append(MockAIService()) // For testing
        
        // Add MLX services if available (MLXService handles its own availability check)
        services.append(contentsOf: createMLXServicesIfAvailable())
        
        logInfo(.ai, "✅ Created \(services.count) AI services")
        logDebug(.ai, "Available services: \(services.map { $0.name }.joined(separator: ", "))")
        
        return services
    }
    
    /**
     * Get the recommended default service name
     */
    static func getRecommendedService() -> String {
        // Check if MLX services are available first
        let mlxServices = createMLXServicesIfAvailable()
        if !mlxServices.isEmpty {
            // Return the first available MLX service
            return mlxServices[0].name
        }
        
        // Fallback to cloud service
        logInfo(.ai, "🖥️ Recommending cloud service")
        return "DeepSeek"
    }
    
    /**
     * Create MLX services if they're available (delegates to MLXService)
     */
    private static func createMLXServicesIfAvailable() -> [AIService] {
        // Try to create MLX services - they handle their own availability
        let potentialMLXServices: [() -> AIService?] = [
            { try? MLXService.qwen3_30B() },
            { try? MLXService.llama3_2_8B() },
            { try? MLXService.mistral_7B() }
        ]
        
        let availableMLXServices = potentialMLXServices.compactMap { $0() }
        
        if !availableMLXServices.isEmpty {
            logInfo(.ai, "🚀 Added \(availableMLXServices.count) MLX services")
        } else {
            logDebug(.ai, "No MLX services available")
        }
        
        return availableMLXServices
    }
    
    /**
     * Get service by name from available services
     */
    static func getService(named serviceName: String) -> AIService? {
        let services = createAvailableServices()
        return services.first { $0.name == serviceName }
    }
    
    /**
     * Check if a service is available on current platform
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
     * Get setup instructions for missing services
     */
    static func getSetupInstructions(for serviceName: String) -> String? {
        if serviceName.contains("MLX") {
            return """
            MLX Local AI Setup:
            
            1. Ensure you're on Apple Silicon Mac
            2. Install MLX server (see MLXService documentation)
            3. Start server and models will be available
            """
        } else if serviceName.contains("OpenAI") {
            return "OpenAI API key required. Get one at: https://platform.openai.com/api-keys"
        } else if serviceName.contains("Claude") {
            return "Anthropic API key required. Get one at: https://console.anthropic.com/"
        } else if serviceName.contains("DeepSeek") {
            return "DeepSeek API key required. Get one at: https://platform.deepseek.com/"
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
            issues.append("No AI services are configured. Please add API keys.")
        }
        
        return issues
    }
}

// MARK: - Simple Platform Manager

/**
 * Simple platform manager that delegates to individual services
 */
class PlatformAwareServiceManager {
    
    /**
     * Get services recommended for current platform
     */
    static func getRecommendedServices() -> [AIService] {
        return AIServiceFactory.createAvailableServices()
    }
    
    /**
     * Get default service for current platform
     */
    static func getDefaultService() -> AIService {
        let services = getRecommendedServices()
        let recommendedName = AIServiceFactory.getRecommendedService()
        return services.first { $0.name == recommendedName } ?? services.first!
    }
    
    /**
     * Get platform capabilities description
     */
    static func getPlatformCapabilities() -> String {
        let services = getRecommendedServices()
        let localServices = services.filter { $0.name.contains("MLX") }
        
        if !localServices.isEmpty {
            return "Apple Silicon Mac - Local MLX + Cloud AI available"
        } else {
            return "Cloud AI services available"
        }
    }
    
    /**
     * Check if local AI services are available
     */
    static func hasLocalServices() -> Bool {
        let services = getRecommendedServices()
        return services.contains { $0.name.contains("MLX") }
    }
}
