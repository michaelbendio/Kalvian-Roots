//
//  AIServiceFactory.swift
//  Kalvian Roots
//
//  Streamlined factory for creating AI services
//

import Foundation

/**
 * Factory for creating AI services
 * Currently focused on DeepSeek with option for local MLX when available
 */
class AIServiceFactory {
    
    /**
     * Create all available AI services for the current platform
     */
    static func createAvailableServices() -> [AIService] {
        logInfo(.ai, "🏭 Creating available AI services")
        
        var services: [AIService] = []
        
        // Primary service: DeepSeek
        services.append(DeepSeekService())

        logInfo(.ai, "✅ Created \(services.count) AI services")
        logDebug(.ai, "Available services: \(services.map { $0.name }.joined(separator: ", "))")
        
        return services
    }
    
    /**
     * Get the recommended default service
     */
    static func getRecommendedService() -> String {
        // DeepSeek is currently the best for Finnish genealogical data
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
     * Get setup instructions for missing services
     */
    static func getSetupInstructions(for serviceName: String) -> String? {
        if serviceName.contains("DeepSeek") {
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
        
        // Check DeepSeek specifically
        if let deepSeek = services.first(where: { $0.name == "DeepSeek" }),
           !deepSeek.isConfigured {
            issues.append("DeepSeek not configured - add API key in settings")
        }
        
        return issues
    }
}
