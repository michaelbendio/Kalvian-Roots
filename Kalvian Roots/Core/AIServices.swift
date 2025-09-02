//
//  AIServices.swift
//  Kalvian Roots
//
//  Streamlined AI services with iCloud sync for API keys
//

import Foundation

// MARK: - AI Service Protocol

protocol AIService {
    var name: String { get }
    var isConfigured: Bool { get }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String
    func configure(apiKey: String) throws
}

// MARK: - DeepSeek Service (Your Primary Service)

/**
 * DeepSeek API service - excellent for Finnish genealogical data
 * Now with iCloud Key-Value Storage for syncing API keys across devices
 */
class DeepSeekService: AIService {
    let name = "DeepSeek"
    private var apiKey: String?
    private let baseURL = "https://api.deepseek.com/v1/chat/completions"
    
    // Storage keys
    private let apiKeyStorageKey = "AIService_DeepSeek_APIKey"
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    
    init() {
        // First check iCloud store for synced key
        if let cloudKey = iCloudStore.string(forKey: apiKeyStorageKey),
           !cloudKey.isEmpty {
            self.apiKey = cloudKey
            logInfo(.ai, "✅ DeepSeek auto-configured with iCloud synced API key")
        }
        // Fall back to local UserDefaults if no cloud key
        else if let localKey = UserDefaults.standard.string(forKey: apiKeyStorageKey),
                !localKey.isEmpty {
            self.apiKey = localKey
            // Migrate to iCloud
            iCloudStore.set(localKey, forKey: apiKeyStorageKey)
            iCloudStore.synchronize()
            logInfo(.ai, "📤 Migrated DeepSeek API key to iCloud")
        } else {
            logDebug(.ai, "No saved API key found for DeepSeek")
        }
        
        // Listen for iCloud changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudKeysChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore
        )
    }
    
    @objc private func iCloudKeysChanged(_ notification: Notification) {
        if let cloudKey = iCloudStore.string(forKey: apiKeyStorageKey),
           !cloudKey.isEmpty {
            self.apiKey = cloudKey
            logInfo(.ai, "🔄 DeepSeek API key updated from iCloud")
        }
    }
    
    var isConfigured: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }
    
    func configure(apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw AIServiceError.apiKeyMissing
        }
        
        self.apiKey = apiKey
        
        // Save to both iCloud and local storage
        iCloudStore.set(apiKey, forKey: apiKeyStorageKey)
        iCloudStore.synchronize()
        UserDefaults.standard.set(apiKey, forKey: apiKeyStorageKey)
        
        #if os(iOS)
        UserDefaults.standard.synchronize()
        #endif
        
        logInfo(.ai, "✅ DeepSeek API key saved to iCloud (will sync to all devices)")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        guard let apiKey = apiKey else {
            throw AIServiceError.notConfigured("DeepSeek API key not configured")
        }
        
        logInfo(.ai, "🤖 DeepSeek parsing family: \(familyId)")
        
        let prompt = """
        Extract genealogical information from this Finnish family record and return ONLY a valid JSON object.
        
        CRITICAL: Your response must be ONLY the JSON object, with no markdown formatting, no explanation, no ```json tags.
        
        Family ID: \(familyId)
        
        Text:
        \(familyText)
        
        Return a JSON object with this exact structure:
        {
          "familyId": "string",
          "pageReferences": ["string"],
          "father": { person object or null },
          "mother": { person object or null },
          "additionalSpouses": [array of person objects],
          "children": [array of person objects],
          "notes": ["string"],
          "childrenDiedInfancy": number
        }
        
        Person object structure:
        {
          "name": "string",
          "patronymic": "string or null",
          "birthDate": "string or null",
          "deathDate": "string or null",
          "marriageDate": "string or null",
          "spouse": "string or null",
          "asChildReference": "string or null",
          "asParentReference": "string or null",
          "familySearchId": "string or null",
          "noteMarkers": ["string"],
          "fatherName": "string or null",
          "motherName": "string or null",
          "fullMarriageDate": "string or null",
          "spouseBirthDate": "string or null",
          "spouseParentsFamilyId": "string or null"
        }
        """
        
        let requestBody: [String: Any] = [
            "model": "deepseek-chat" as String,
            "messages": [
                ["role": "system" as String, "content": "You are a genealogy expert. Extract information and return ONLY valid JSON." as String] as [String: String],
                ["role": "user" as String, "content": prompt as String] as [String: String]
            ] as [[String: String]],
            "temperature": 0.1 as Double,
            "max_tokens": 4000 as Int
        ]
        
        guard let url = URL(string: baseURL) else {
            throw AIServiceError.invalidConfiguration("Invalid API endpoint URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logError(.ai, "❌ DeepSeek API error: \(errorMessage)")
            throw AIServiceError.apiError("DeepSeek API error: \(errorMessage)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.invalidResponse("No content in DeepSeek response")
        }
        
        logInfo(.ai, "✅ DeepSeek successfully returned response")
        return cleanJSONResponse(content)
    }
    
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response
        if cleaned.contains("```json") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Mock AI Service (For Testing Only)

/**
 * Mock AI service for testing without API calls
 */
class MockAIService: AIService {
    let name = "Mock AI"
    let isConfigured = true
    
    func configure(apiKey: String) throws {
        // No-op for mock service
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        // Simulate processing delay
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Return a simple test response
        return """
        {
          "familyId": "\(familyId)",
          "pageReferences": ["999"],
          "father": {
            "name": "Test Father",
            "birthDate": "01.01.1700",
            "deathDate": "31.12.1780",
            "noteMarkers": []
          },
          "mother": {
            "name": "Test Mother",
            "birthDate": "01.01.1705",
            "deathDate": "31.12.1785",
            "noteMarkers": []
          },
          "additionalSpouses": [],
          "children": [
            {
              "name": "Test Child",
              "birthDate": "01.01.1730",
              "noteMarkers": []
            }
          ],
          "notes": ["Mock data for testing"],
          "childrenDiedInfancy": 0
        }
        """
    }
}

// MARK: - Helper Extension for iCloud Availability

extension NSUbiquitousKeyValueStore {
    static var isAvailable: Bool {
        // Use Foundation.FileManager explicitly to avoid conflict with custom FileManager class
        if Foundation.FileManager.default.ubiquityIdentityToken != nil {
            return true
        }
        return false
    }
}

// Note: When a suitable local AI becomes available (like an improved MLX model
// or a Finnish-optimized LLM), you can add it here. For now, DeepSeek provides
// excellent accuracy for Finnish genealogical data at a reasonable cost.
