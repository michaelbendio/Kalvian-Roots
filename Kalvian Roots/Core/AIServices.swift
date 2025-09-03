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
        
        // IMPROVED PROMPT that matches your existing Family and Person structs
        let prompt = """
        You are a Finnish genealogy expert. Extract structured data from this family record and return ONLY a valid JSON object.
        
        CRITICAL: Your response must be ONLY the JSON object, with no markdown formatting, no explanation, no ```json tags.
        
        EXTRACTION RULES:
        1. FAMILY ID: Extract the main family identifier (e.g., "PIENI-PORKOLA 5")
        2. PAGE REFERENCES: Extract all page numbers from format like "page 268-269" as ["268", "269"]
        3. COUPLES: The first couple listed are the primary parents. Additional sections with "II puoliso", "III puoliso" indicate additional couples
        4. CHILDREN: The "Lapset" section contains children. Children belong to the most recent couple mentioned
        5. NOTES: Extract general notes and note definitions (markers like "*)" with their explanations)
        6. CHILDREN DIED INFANCY: Extract numbers from phrases like "Lapsena kuollut 3"
        
        SYMBOL MEANINGS:
        - ★ = Birth date (format: "22.12.1701")
        - † = Death date (format: "27.05.1764")  
        - ∞ = Marriage information
        - {Family ID} = asChild reference (where person was born)
        - Family ID after child = asParent reference (where person became parent)
        - <ID> = FamilySearch ID
        - *) **) etc. = Note markers
        
        MARRIAGE DATE HANDLING:
        - If marriage date is 2 digits (e.g., "48"), put in "marriageDate"
        - If full date (e.g., "28.11.1725"), put in "fullMarriageDate"
        - If both formats exist, use the full date in "fullMarriageDate"
        
        Family record to parse:
        \(familyText)
        
        Return a JSON object with this exact structure that matches the Swift Family struct:
        {
          "familyId": "string",
          "pageReferences": ["string"],
          "couples": [
            {
              "husband": { ... } or null,
              "wife": { ... } or null,
              "marriageDate": "string or null",
              "children": [{ ... }]
            }
          ],
          "notes": ["string"],
          "noteDefinitions": {"marker": "definition"} or null
        }
        
        Person object structure (matches Swift Person struct):
        {
          "name": "string",
          "patronymic": "string or null",
          "birthDate": "string or null",
          "deathDate": "string or null",
          "marriageDate": "string or null",
          "fullMarriageDate": "string or null",
          "spouse": "string or null",
          "asChild": "string or null",
          "asParent": "string or null",
          "familySearchId": "string or null",
          "noteMarkers": ["string"] or null,
          "fatherName": "string or null",
          "motherName": "string or null",
          "spouseBirthDate": "string or null",
          "spouseParentsFamilyId": "string or null"
        }
        
        EXAMPLES:
        Input: "★ 18.06.1732 Juho Paavalinp. <L71Z-4G1> {Haapaniemi 3} † 04.04.1809"
        Output: {
          "name": "Juho",
          "patronymic": "Paavalinp.",
          "birthDate": "18.06.1732",
          "deathDate": "04.04.1809",
          "familySearchId": "L71Z-4G1",
          "asChild": "Haapaniemi 3"
        }
        
        Input: "★ 03.03.1759 Antti ∞ 78 Malin Korpi Korvela 3"
        Output: {
          "name": "Antti",
          "birthDate": "03.03.1759",
          "marriageDate": "78",
          "spouse": "Malin Korpi",
          "asParent": "Korvela 3"
        }
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
            throw AIServiceError.invalidResponse("No content in DeepSeek response")
        }
        
        logInfo(.ai, "✅ DeepSeek successfully returned response")
        return cleanJSONResponse(content)
    }
    
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response
        // Remove any markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // Remove any explanatory text before or after JSON
        if let jsonStart = cleaned.firstIndex(of: "{"),
           let jsonEnd = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[jsonStart...jsonEnd])
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
