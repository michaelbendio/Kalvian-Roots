// DeepSeekService.swift - Improved version with better multiple spouse handling

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
        
        // IMPROVED PROMPT with better multiple spouse handling
        let prompt = """
        You are a Finnish genealogy expert. Extract structured data from this family record and return ONLY a valid JSON object.
        
        CRITICAL: Your response must be ONLY the JSON object, with no markdown formatting, no explanation, no ```json tags.
        
        EXTRACTION RULES:
        1. FAMILY ID: Extract the main family identifier (e.g., "PIENI-PORKOLA 5")
        2. PAGE REFERENCES: Extract all page numbers from format like "page 268-269" as ["268", "269"]
        
        3. COUPLES STRUCTURE - INTELLIGENT SPOUSE DETERMINATION:
           - The PRIMARY COUPLE is the first couple listed (primary husband + primary wife)
           - "II puoliso" or "III puoliso" means ADDITIONAL SPOUSE for the surviving partner
           
           CRITICAL LOGIC FOR DETERMINING WHO REMARRIED:
           a) Check death dates:
              - If HUSBAND died before the additional spouse's marriage → WIFE remarried (keep same wife, new husband)
              - If WIFE died before the additional spouse's marriage → HUSBAND remarried (keep same husband, new wife)
           b) If no death date is available, look for contextual clues:
              - "leski" (widow/widower) indicates who survived
              - Position in text and children's dates can provide hints
           c) Default only if no information: assume husband remarried
        
        4. MULTIPLE SPOUSES HANDLING EXAMPLES:
           
           Example 1 - Husband dies, wife remarries:
           ★ 1726 Jaakko Jaakonp. † 1735
           ★ 1700 Malin Matint. † 1771
           ∞ 1724
           II puoliso
           ★ 1689 Erik Jaakonp. † 1778
           ∞ 1736
           
           Creates TWO couples:
           Couple 1: {husband: Jaakko (d.1735), wife: Malin, marriage: 1724}
           Couple 2: {husband: Erik, wife: Malin (same), marriage: 1736}
           
           Example 2 - Wife dies, husband remarries:
           ★ 1726 Jaakko Jaakonp. † 1789
           ★ 1733 Maria Jaakont. † 1753
           ∞ 1752
           II puoliso
           ★ 1732 Brita Eliant. † 1767
           ∞ 1754
           
           Creates TWO couples:
           Couple 1: {husband: Jaakko, wife: Maria (d.1753), marriage: 1752}
           Couple 2: {husband: Jaakko (same), wife: Brita, marriage: 1754}
        
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
        
        DECISION TREE FOR ADDITIONAL SPOUSES:
        1. Is there a death date for primary husband before additional marriage? → Wife remarried (new husband)
        2. Is there a death date for primary wife before additional marriage? → Husband remarried (new wife)
        3. Does text say "[name] leski" (widow/widower)? → That person is the survivor who remarried
        4. Are there contextual date clues? → Use them to determine who survived
        5. Only if no information available → Default to husband remarried (but try to avoid this)
        
        ALWAYS analyze the dates to determine the correct couple structure!
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
