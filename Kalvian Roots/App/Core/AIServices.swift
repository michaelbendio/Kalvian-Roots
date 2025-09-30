// AIServices.swift - Improved version with better multiple spouse handling

import Foundation

// MARK: - AIService Protocol
protocol AIService {
    var name: String { get }
    var isConfigured: Bool { get }
    func configure(apiKey: String) throws
    func parseFamily(familyId: String, familyText: String) async throws -> String
}

// MARK: - DeepSeek Service with Improved Prompt
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
        
        // IMPROVED PROMPT with explicit JSON schema
        let prompt = """
        You are a Finnish genealogy expert. Parse the following family record and return ONLY a valid JSON object.
        
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
              "marriageDate": "string or null (2-digit year)",
              "fullMarriageDate": "string or null (dd.mm.yyyy)",
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
        4. Extract dates exactly as written (including historical periods like "isoviha")
        5. Marriage dates: Store 2-digit as marriageDate, full date as fullMarriageDate
        6. Extract {family references} as asChild or asParent
        7. Extract <IDs> as familySearchId
        8. Note markers (*) go in noteMarkers array, definitions in noteDefinitions
        
        DETERMINING COUPLES:
        - Look for "II puoliso" or "III puoliso" to identify additional marriages
        - The person who survives and remarries appears in multiple couples
        - Use death dates and marriage dates to determine the correct sequence
        - Each "Lapset" (Children) section belongs to the couple above it
        
        Family text to parse:
        \(familyText)
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
        
        // Increase timeout to 120 seconds for complex families
        request.timeoutInterval = 120.0
        
        logDebug(.ai, "📤 Sending request with 120s timeout")
        
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
