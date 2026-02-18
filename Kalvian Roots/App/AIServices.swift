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
                Parse the following family record and return ONLY a valid JSON object.

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
                        "noteMarkers": ["array of asterisks: *, **, *** (NO parentheses)"]
                      },
                      "wife": {
                        "name": "string",
                        "patronymic": "string or null",
                        "birthDate": "string or null",
                        "deathDate": "string or null",
                        "asChild": "string or null",
                        "familySearchId": "string or null",
                        "noteMarkers": ["array of asterisks: *, **, ***"]
                      },
                      "marriageDate": "string or null (2-digit year, MAY include 'n' prefix)",
                      "fullMarriageDate": "string or null (dd.mm.yyyy, MAY include 'n' prefix)",
                      "children": [
                        {
                          "name": "string",
                          "birthDate": "string or null",
                          "deathDate": "string or null",
                          "marriageDate": "string or null",
                          "spouse": "string or null",
                          "asParent": "string or null",
                          "familySearchId": "string or null",
                          "noteMarkers": ["array of asterisks: *, **, ***"]
                        }
                      ],
                      "childrenDiedInfancy": null,
                      "coupleNotes": []
                    }
                  ],
                  "notes": ["array of family notes"],
                  "noteDefinitions": {"*": "note text", "**": "another note"}
                }

                EXTRACTION RULES:
                1. Parse ONLY family \(familyId) - ignore any other families in the text
                
                2. Create a separate couple entry for each marriage
                
                3. If a person appears in multiple marriages, they appear in multiple couples
                
                4. Extract dates EXACTLY as written, preserving ALL formatting:
                   - Keep historical periods like "isoviha" as-is
                   - **CRITICAL**: Keep "n" prefix for approximate dates (e.g., "n 1730", "n 30")
                   - Do NOT strip or remove the "n " prefix - it indicates an approximate date
                
                5. Extract family references from {curly braces} as asChild/asParent fields
                
                6. **MISSING SPOUSE DATA - CREATE PLACEHOLDER OBJECTS**:
                   - If only husband data exists (widower family), create a placeholder wife object:
                     {
                       "name": "Unknown",
                       "patronymic": null,
                       "birthDate": null,
                       "deathDate": null,
                       "asChild": null,
                       "familySearchId": null,
                       "noteMarkers": []
                     }
                   - If only wife data exists (widow family), create a placeholder husband object with same structure
                   - **NEVER return null for husband or wife** - always create a valid object
                   - Examples:
                     ✓ CORRECT: Family with only father listed → husband: {...data...}, wife: {"name": "Unknown", ...nulls...}
                     ✗ WRONG: wife: null (will cause parsing failure)
                
                7. **SPOUSE NAMES - STRIP MARRIAGE NUMBER PREFIXES**:
                   - Spouse names may have a marriage sequence prefix like "1. ", "2. ", "3. "
                   - These indicate which marriage number for the child (1st spouse, 2nd spouse)
                   - ALWAYS strip these numeric prefixes from the spouse field
                   - Examples:
                     ✓ CORRECT: "∞ 06 1. Israel Vuolle" → spouse: "Israel Vuolle"
                     ✓ CORRECT: "∞ 32 2. Anna Marttila" → spouse: "Anna Marttila"
                     ✗ WRONG: spouse: "1. Israel Vuolle" (prefix not stripped)
                
                8. **NOTE MARKERS AND DEFINITIONS**:
                   - Note markers appear at the end of person lines: "*)", "**)", "***)", etc.
                   - Note definitions appear AFTER the last child, matching the marker symbol
                   - **CRITICAL**: Store markers as just asterisks ("*", "**") WITHOUT closing parenthesis
                   - Extract note text WITHOUT the marker prefix
                   
                   **Identifying Note Markers on Person Lines**:
                   - Look for "*)", "**)", "***)" at the end of a line
                   - Strip the closing parenthesis ")" when adding to noteMarkers array
                   - Examples:
                     ✓ "★ Juho ∞ Anna Matint. *)" → noteMarkers: ["*"]  (stripped ")")
                     ✓ "★ Liisa **)" → noteMarkers: ["**"]  (stripped ")")
                     ✓ "★ Matti *) **)" → noteMarkers: ["*", "**"]  (both stripped)
                     ✗ WRONG: noteMarkers: ["*)"]  (don't include parenthesis!)
                   
                   **Extracting Note Definitions**:
                   - After parsing all children, look for lines starting with "*)", "**)", etc.
                   - Strip the marker prefix (including parenthesis) from the note text
                   - Store using just asterisks as the key: {"*": "text", "**": "text"}
                   - Examples:
                     ✓ "*) Nurilan isännän veli" → {"*": "Nurilan isännän veli"}  (stripped "*)")
                     ✓ "**) N:o 60 Flinkfelt." → {"**": "N:o 60 Flinkfelt."}  (stripped "**)")
                     ✗ WRONG: {"*)": "text"}  (don't include parenthesis in key!)
                     ✗ WRONG: {"*": "*) text"}  (don't include marker in text!)
                   
                   **Complete Example from KLAPURI 4**:
                   Input text:
                   ```
                   ★ 1703  Maria  ∞ 24 Mikko Hotakka  *)  Klapuri 6
                   ★ 1706  Liisa  ∞ 25 Erik Herronen  **)  Kukkonmäki
                   *) Nurilan isännän veli, ks. Nurila 4.
                   **) N:o 60 Flinkfelt.
                   ```
                   
                   Correct output:
                   ```json
                   {
                     "children": [
                       {
                         "name": "Maria",
                         "marriageDate": "24",
                         "spouse": "Mikko Hotakka",
                         "asParent": "Klapuri 6",
                         "noteMarkers": ["*"]
                       },
                       {
                         "name": "Liisa",
                         "marriageDate": "25",
                         "spouse": "Erik Herronen",
                         "asParent": "Kukkonmäki",
                         "noteMarkers": ["**"]
                       }
                     ],
                     "noteDefinitions": {
                       "*": "Nurilan isännän veli, ks. Nurila 4.",
                       "**": "N:o 60 Flinkfelt."
                     }
                   }
                   ```
                   
                   **Important**:
                   - If no note markers on a person, noteMarkers should be empty array: []
                   - If no note definitions in family, noteDefinitions should be empty object: {}
                   - Store marker keys as "*", "**", "***" (asterisks only, NO parentheses)
                   - Note text should NOT include the marker prefix
                   - Preserve the exact note text after the marker, including dates and punctuation

                9. **DATE FORMAT EXAMPLES**:
                   - "n 1730" → marriageDate: null, fullMarriageDate: "n 1730" (approximate full year)
                   - "n 30" → marriageDate: "n 30", fullMarriageDate: null (approximate 2-digit)
                   - "30" → marriageDate: "30", fullMarriageDate: null (exact 2-digit)
                   - "01.02.1730" → marriageDate: null, fullMarriageDate: "01.02.1730" (exact full date)

                10. **DETERMINING COUPLES**:
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
