// MARK: - DeepSeek Service

import Foundation

// MARK: - AIService Protocol
protocol AIService {
    var name: String { get }
    var isConfigured: Bool { get }
    func configure(apiKey: String) throws
    func parseFamily(familyId: String, familyText: String) async throws -> String
}

// MARK: - DeepSeek Service
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
        
        // IMPROVED PROMPT with better multiple spouse handling
        let prompt = """
        You are a Finnish genealogy expert. Extract structured data from this family record and return ONLY a valid JSON object.
        
        CRITICAL: Your response must be ONLY the JSON object, with no markdown formatting, no explanation, no ```json tags.
        
        EXTRACTION RULES:
        1. FAMILY ID: Extract the main family identifier (e.g., "PIENI-PORKOLA 5")
        2. PAGE REFERENCES: Extract all page numbers from format like "page 268-269" as ["268", "269"]
        
        3. COUPLES STRUCTURE - CRITICAL FOR CORRECT PARSING:
           - The PRIMARY COUPLE is the first couple listed (primary husband + primary wife)
           - "II puoliso" or "III puoliso" means ADDITIONAL WIFE for the SAME HUSBAND
           - Create separate couple entries but REUSE THE SAME HUSBAND for each additional spouse
           - Children listed after "Lapset" belong to the most recent couple mentioned
        
        4. MULTIPLE SPOUSES HANDLING:
           Example family structure:
           - Husband: Matti (primary)
           - Wife 1: Malin (primary wife)
           - Their children...
           - "II puoliso" → Wife 2: Maria (Matti's second wife)
           - Their children...
           
           This should produce TWO couples:
           Couple 1: {husband: Matti, wife: Malin, children: [...]}
           Couple 2: {husband: Matti, wife: Maria, children: [...]}
           
           NEVER create "Unknown Father" for additional spouses!
        
        5. CHILDREN: The "Lapset" section contains children for the current couple
        6. NOTES: Extract general notes and note definitions
        7. CHILDREN DIED INFANCY: Extract from "Lapsena kuollut X"
        
        SYMBOL MEANINGS:
        - ★ = Birth date
        - † = Death date  
        - ∞ = Marriage information
        - {Family ID} = asChild reference
        - Family ID after child = asParent reference
        - <ID> = FamilySearch ID
        - *) **) = Note markers
        
        MARRIAGE DATE HANDLING:
        - 2 digits (e.g., "48") → "marriageDate"
        - Full date (e.g., "28.11.1725") → "fullMarriageDate"
        
        Family record to parse:
        \(familyText)
        
        Return JSON with this structure:
        {
          "familyId": "string",
          "pageReferences": ["string"],
          "couples": [
            {
              "husband": {
                "name": "string",
                "patronymic": "string or null",
                "birthDate": "string or null",
                "deathDate": "string or null",
                "asChild": "string or null",
                "familySearchId": "string or null"
              },
              "wife": {
                "name": "string",
                "patronymic": "string or null",
                "birthDate": "string or null",
                "deathDate": "string or null",
                "asChild": "string or null",
                "familySearchId": "string or null"
              },
              "marriageDate": "string or null",
              "fullMarriageDate": "string or null",
              "children": [
                {
                  "name": "string",
                  "birthDate": "string or null",
                  "deathDate": "string or null",
                  "marriageDate": "string or null",
                  "spouse": "string or null",
                  "asParent": "string or null",
                  "familySearchId": "string or null"
                }
              ],
              "childrenDiedInfancy": number or null
            }
          ],
          "notes": ["string"],
          "noteDefinitions": {"marker": "definition"} or null,
          "childrenDiedInfancy": number or null
        }
        
        IMPORTANT EXAMPLES FOR MULTIPLE SPOUSES:
        
        Input text with "II puoliso":
        ★ 1708 Matti Olavinp. † 07.04.1766
        ★ 1698 Malin Erikint. † 29.01.1757
        ∞ 28.05.1728
        Lapset
        ★ 03.05.1733 Magdaleena
        II puoliso
        ★ 14.01.1726 Maria Henrikint. † 12.09.1805
        ∞ 24.07.1757
        Lapset
        ★ 06.05.1759 Erik
        
        Correct output couples array:
        "couples": [
          {
            "husband": {"name": "Matti", "patronymic": "Olavinp.", "birthDate": "1708", "deathDate": "07.04.1766"},
            "wife": {"name": "Malin", "patronymic": "Erikint.", "birthDate": "1698", "deathDate": "29.01.1757"},
            "marriageDate": null,
            "fullMarriageDate": "28.05.1728",
            "children": [{"name": "Magdaleena", "birthDate": "03.05.1733"}]
          },
          {
            "husband": {"name": "Matti", "patronymic": "Olavinp.", "birthDate": "1708", "deathDate": "07.04.1766"},
            "wife": {"name": "Maria", "patronymic": "Henrikint.", "birthDate": "14.01.1726", "deathDate": "12.09.1805"},
            "marriageDate": null,
            "fullMarriageDate": "24.07.1757",
            "children": [{"name": "Erik", "birthDate": "06.05.1759"}]
          }
        ]
        
        NEVER create an "Unknown Father" - always reuse the primary husband for additional spouses!
        """
        
        let requestBody: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": "You are a Finnish genealogy data extraction expert. Return ONLY valid JSON with no additional text."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 4000
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
            throw AIServiceError.invalidResponse("Invalid response structure")
        }
        
        logInfo(.ai, "✅ DeepSeek successfully returned response")
        logTrace(.ai, "Raw response: \(content.prefix(500))...")
        
        return content
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
