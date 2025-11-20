//
//  PlatformAwareServiceManager.swift
//  Kalvian Roots
//
//  Streamlined platform-aware service management
//
//  Created by Michael Bendio on 8/31/25.
//

import Foundation

/**
 * Manager for platform-specific AI service recommendations
 * Currently focused on DeepSeek across all platforms
 */
class PlatformAwareServiceManager {
    
    /**
     * Get recommended services for the current platform
     */
    static func getRecommendedServices() -> [AIService] {
        // For now, just use the factory directly
        // In the future, this could add platform-specific logic
        return AIServiceFactory.createAvailableServices()
    }
    
    /**
     * Get the default service for the current platform
     */
    static func getDefaultService() -> AIService {
        // DeepSeek is our default across all platforms
        // It provides the best accuracy for Finnish genealogical data
        
        if let deepSeek = AIServiceFactory.getService(named: "DeepSeek") {
            logInfo(.ai, "✅ Using DeepSeek as default service")
            return deepSeek
        }
        
        // Fallback to mock if DeepSeek somehow fails to initialize
        logWarn(.ai, "⚠️ DeepSeek unavailable, falling back to Mock AI")
        return MockAIService()
    }
    
    /**
     * Check if we're on a platform that could support local AI
     */
    static func canSupportLocalAI() -> Bool {
        #if os(macOS) && arch(arm64)
        // Apple Silicon Mac - could support local AI
        return true
        #else
        // iPad, iPhone, or Intel Mac - no local AI
        return false
        #endif
    }
    
    /**
     * Get platform description for logging
     */
    static func getPlatformDescription() -> String {
        #if os(macOS)
            #if arch(arm64)
            return "Apple Silicon Mac (Local AI capable)"
            #else
            return "Intel Mac (Cloud only)"
            #endif
        #else
        return "Unknown Platform"
        #endif
    }
}

