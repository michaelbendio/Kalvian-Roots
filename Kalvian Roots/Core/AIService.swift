//
//  AIService.swift
//  Kalvian Roots
//
//  Complete AI service implementations updated for JSON parsing
//

import Foundation

// MARK: - AI Service Protocol

/**
 * Unified interface for AI services with JSON parsing
 */
protocol AIService {
    var name: String { get }
    var isConfigured: Bool { get }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String
    func configure(apiKey: String) throws
}

// MARK: - AI Service Errors

enum AIServiceError: LocalizedError {
    case notConfigured(String)
    case invalidResponse(String)
    case networkError(Error)
    case parsingFailed(String)
    case rateLimited
    case apiKeyMissing
    case httpError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured(let service):
            return "\(service) not configured. Please add API key."
        case .invalidResponse(let details):
            return "Invalid AI response: \(details)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingFailed(let details):
            return "Failed to parse AI response: \(details)"
        case .rateLimited:
            return "AI service rate limit reached. Please try again later."
        case .apiKeyMissing:
            return "API key required for AI service"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        }
    }
}

// MARK: - Mock AI Service (Updated for JSON)

/**
 * Mock AI service for testing with JSON responses
 */
class MockAIService: AIService {
    let name = "Mock AI"
    let isConfigured = true
    
    func configure(apiKey: String) throws {
        logDebug(.ai, "MockAI configure called (no-op)")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 MockAI JSON parsing family: \(familyId)")
        logTrace(.ai, "Family text length: \(familyText.count) characters")
        
        DebugLogger.shared.startTimer("mock_ai_processing")
        
        // Simulate AI processing time
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let duration = DebugLogger.shared.endTimer("mock_ai_processing")
        logDebug(.ai, "MockAI JSON processing completed in \(String(format: "%.3f", duration))s")
        
        // Return hardcoded JSON responses for known families
        let response: String
        switch familyId.uppercased() {
        case "KORPI 6":
            response = mockKorpi6JSONResponse()
            logDebug(.ai, "Returning KORPI 6 mock JSON response")
        case "TEST 1":
            response = mockTest1JSONResponse()
            logDebug(.ai, "Returning TEST 1 mock JSON response")
        default:
            response = mockGenericJSONResponse(familyId: familyId)
            logDebug(.ai, "Returning generic mock JSON response for \(familyId)")
        }
        
        logTrace(.ai, "Mock JSON response length: \(response.count) characters")
        return response
    }
    
    private func mockKorpi6JSONResponse() -> String {
        return """
        {
          "familyId": "KORPI 6",
          "pageReferences": ["105", "106"],
          "father": {
            "name": "Matti",
            "patronymic": "Erikinp.",
            "birthDate": "09.09.1727",
            "deathDate": "22.08.1812",
            "marriageDate": "14.10.1750",
            "spouse": "Brita Matint.",
            "asChildReference": "KORPI 5",
            "asParentReference": null,
            "familySearchId": "LCJZ-BH3",
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "mother": {
            "name": "Brita",
            "patronymic": "Matint.",
            "birthDate": "05.09.1731",
            "deathDate": "11.07.1769",
            "marriageDate": "14.10.1750",
            "spouse": "Matti Erikinp.",
            "asChildReference": "SIKALA 5",
            "asParentReference": null,
            "familySearchId": "KCJW-98X",
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "additionalSpouses": [],
          "children": [
            {
              "name": "Maria",
              "patronymic": null,
              "birthDate": "10.02.1752",
              "deathDate": null,
              "marriageDate": "1773",
              "spouse": "Elias Iso-Peitso",
              "asChildReference": null,
              "asParentReference": "ISO-PEITSO III 2",
              "familySearchId": "KJJH-2R9",
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            },
            {
              "name": "Kaarin",
              "patronymic": null,
              "birthDate": "01.02.1753",
              "deathDate": "17.04.1795",
              "marriageDate": null,
              "spouse": null,
              "asChildReference": null,
              "asParentReference": null,
              "familySearchId": "LJKQ-PLT",
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            },
            {
              "name": "Abraham",
              "patronymic": null,
              "birthDate": "08.01.1764",
              "deathDate": null,
              "marriageDate": "1787",
              "spouse": "Anna Sikala",
              "asChildReference": null,
              "asParentReference": "JÄNESNIEMI 5",
              "familySearchId": null,
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            }
          ],
          "notes": ["Lapsena kuollut 4."],
          "childrenDiedInfancy": 4
        }
        """
    }
    
    private func mockTest1JSONResponse() -> String {
        return """
        {
          "familyId": "TEST 1",
          "pageReferences": ["1"],
          "father": {
            "name": "Test",
            "patronymic": "Matinp.",
            "birthDate": "01.01.1700",
            "deathDate": null,
            "marriageDate": null,
            "spouse": null,
            "asChildReference": null,
            "asParentReference": null,
            "familySearchId": null,
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "mother": {
            "name": "Example",
            "patronymic": "Juhont.",
            "birthDate": "01.01.1705",
            "deathDate": null,
            "marriageDate": null,
            "spouse": null,
            "asChildReference": null,
            "asParentReference": null,
            "familySearchId": null,
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "additionalSpouses": [],
          "children": [
            {
              "name": "Child",
              "patronymic": null,
              "birthDate": "01.01.1725",
              "deathDate": null,
              "marriageDate": null,
              "spouse": null,
              "asChildReference": null,
              "asParentReference": null,
              "familySearchId": null,
              "noteMarkers": [],
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            }
          ],
          "notes": ["Mock family for testing"],
          "childrenDiedInfancy": 0
        }
        """
    }
    
    private func mockGenericJSONResponse(familyId: String) -> String {
        return """
        {
          "familyId": "\(familyId)",
          "pageReferences": ["999"],
          "father": {
            "name": "Unknown",
            "patronymic": "Matinp.",
            "birthDate": "01.01.1700",
            "deathDate": null,
            "marriageDate": null,
            "spouse": null,
            "asChildReference": null,
            "asParentReference": null,
            "familySearchId": null,
            "noteMarkers": [],
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "mother": null,
          "additionalSpouses": [],
          "children": [],
          "notes": ["Mock data for \(familyId)"],
          "childrenDiedInfancy": 0
        }
        """
    }
}

// MARK: - DeepSeek Service (Enhanced with JSON)

/**
 * DeepSeek API service updated for JSON responses
 */
class DeepSeekService: AIService {
    let name = "DeepSeek"
    private var apiKey: String?
    private let baseURL = "https://api.deepseek.com/v1/chat/completions"
    
    var isConfigured: Bool {
        let configured = apiKey != nil && !apiKey!.isEmpty
        logTrace(.ai, "DeepSeek isConfigured: \(configured)")
        return configured
    }
    
    func configure(apiKey: String) throws {
        logInfo(.ai, "🔧 Configuring DeepSeek with API key")
        logTrace(.ai, "API key length: \(apiKey.count) characters")
        
        guard !apiKey.isEmpty else {
            logError(.ai, "❌ Empty API key provided to DeepSeek")
            throw AIServiceError.apiKeyMissing
        }
        
        self.apiKey = apiKey
        logInfo(.ai, "✅ DeepSeek configured successfully")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 DeepSeek JSON parsing family: \(familyId)")
        logDebug(.ai, "Family text length: \(familyText.count) characters")
        logTrace(.ai, "Family text preview: \(String(familyText.prefix(200)))...")
        
        guard isConfigured else {
            logError(.ai, "❌ DeepSeek not configured")
            throw AIServiceError.notConfigured(name)
        }
        
        DebugLogger.shared.startTimer("deepseek_request")
        
        let prompt = createGenealogyPrompt(familyId: familyId, familyText: familyText)
        logTrace(.ai, "Generated prompt length: \(prompt.count) characters")
        
        let request = OpenAIRequest( // DeepSeek uses OpenAI-compatible format
            model: "deepseek-chat",
            messages: [
                OpenAIMessage(role: "system", content: getSystemPrompt()),
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.1,
            max_tokens: 2000
        )
        
        logDebug(.ai, "Making DeepSeek API call")
        DebugLogger.shared.logAIRequest("DeepSeek", prompt: prompt)
        
        do {
            let response = try await makeAPICall(request: request)
            let duration = DebugLogger.shared.endTimer("deepseek_request")
            
            DebugLogger.shared.logAIResponse("DeepSeek", response: response, duration: duration)
            logInfo(.ai, "✅ DeepSeek JSON response received successfully")
            
            return response
            
        } catch {
            DebugLogger.shared.endTimer("deepseek_request")
            logError(.ai, "❌ DeepSeek API call failed: \(error)")
            throw error
        }
    }
    
    private func makeAPICall(request: OpenAIRequest) async throws -> String {
        guard let url = URL(string: baseURL) else {
            logError(.network, "❌ Invalid DeepSeek URL: \(baseURL)")
            throw AIServiceError.networkError(URLError(.badURL))
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey!)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        logTrace(.network, "DeepSeek request headers configured")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
            logTrace(.network, "Request body encoded, size: \(urlRequest.httpBody?.count ?? 0) bytes")
            
            logDebug(.network, "Sending HTTP request to DeepSeek")
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                logDebug(.network, "DeepSeek HTTP response: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 429 {
                        logWarn(.network, "DeepSeek rate limit hit (429)")
                        throw AIServiceError.rateLimited
                    }
                    
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    logError(.network, "DeepSeek HTTP error \(httpResponse.statusCode): \(errorMessage)")
                    throw AIServiceError.httpError(httpResponse.statusCode, errorMessage)
                }
            }
            
            logTrace(.network, "Response data size: \(data.count) bytes")
            
            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            logTrace(.ai, "DeepSeek response decoded successfully")
            
            guard let content = openAIResponse.choices.first?.message.content else {
                logError(.ai, "❌ No content in DeepSeek response")
                throw AIServiceError.invalidResponse("No content in response")
            }
            
            let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            logTrace(.ai, "DeepSeek content cleaned, final length: \(cleanedContent.count)")
            
            return cleanedContent
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            logError(.network, "❌ DeepSeek network error: \(error)")
            throw AIServiceError.networkError(error)
        }
    }
}

// MARK: - OpenAI Service (Updated for JSON)

/**
 * OpenAI ChatGPT API service updated for JSON responses
 */
class OpenAIService: AIService {
    let name = "OpenAI GPT-4"
    private var apiKey: String?
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    var isConfigured: Bool {
        let configured = apiKey != nil && !apiKey!.isEmpty
        logTrace(.ai, "OpenAI isConfigured: \(configured)")
        return configured
    }
    
    func configure(apiKey: String) throws {
        logInfo(.ai, "🔧 Configuring OpenAI with API key")
        
        guard !apiKey.isEmpty else {
            logError(.ai, "❌ Empty API key provided to OpenAI")
            throw AIServiceError.apiKeyMissing
        }
        
        self.apiKey = apiKey
        logInfo(.ai, "✅ OpenAI configured successfully")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 OpenAI JSON parsing family: \(familyId)")
        
        guard isConfigured else {
            logError(.ai, "❌ OpenAI not configured")
            throw AIServiceError.notConfigured(name)
        }
        
        DebugLogger.shared.startTimer("openai_request")
        
        let prompt = createGenealogyPrompt(familyId: familyId, familyText: familyText)
        
        let request = OpenAIRequest(
            model: "gpt-4o",  // FIXED: Changed from "gpt-4" to "gpt-4o"
            messages: [
                OpenAIMessage(role: "system", content: getSystemPrompt()),
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.1,
            max_tokens: 2000
        )
        
        DebugLogger.shared.logAIRequest("OpenAI", prompt: prompt)
        
        do {
            let response = try await makeAPICall(request: request)
            let duration = DebugLogger.shared.endTimer("openai_request")
            
            DebugLogger.shared.logAIResponse("OpenAI", response: response, duration: duration)
            return response
            
        } catch {
            DebugLogger.shared.endTimer("openai_request")
            throw error
        }
    }
    
    private func makeAPICall(request: OpenAIRequest) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw AIServiceError.networkError(URLError(.badURL))
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey!)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 429 {
                        throw AIServiceError.rateLimited
                    }
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw AIServiceError.httpError(httpResponse.statusCode, errorMessage)
                }
            }
            
            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let content = openAIResponse.choices.first?.message.content else {
                throw AIServiceError.invalidResponse("No content in response")
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw AIServiceError.networkError(error)
        }
    }
}

// MARK: - Claude Service (Updated for JSON)

/**
 * Anthropic Claude API service updated for JSON responses
 */
class ClaudeService: AIService {
    let name = "Claude"
    private var apiKey: String?
    private let baseURL = "https://api.anthropic.com/v1/messages"
    
    var isConfigured: Bool {
        let configured = apiKey != nil && !apiKey!.isEmpty
        logTrace(.ai, "Claude isConfigured: \(configured)")
        return configured
    }
    
    func configure(apiKey: String) throws {
        logInfo(.ai, "🔧 Configuring Claude with API key")
        
        guard !apiKey.isEmpty else {
            logError(.ai, "❌ Empty API key provided to Claude")
            throw AIServiceError.apiKeyMissing
        }
        
        self.apiKey = apiKey
        logInfo(.ai, "✅ Claude configured successfully")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 Claude JSON parsing family: \(familyId)")
        
        guard isConfigured else {
            logError(.ai, "❌ Claude not configured")
            throw AIServiceError.notConfigured(name)
        }
        
        DebugLogger.shared.startTimer("claude_request")
        
        let prompt = createGenealogyPrompt(familyId: familyId, familyText: familyText)
        
        let request = ClaudeRequest(
            model: "claude-3-5-sonnet-20241022",
            max_tokens: 2000,
            messages: [
                ClaudeMessage(role: "user", content: prompt)
            ],
            system: getSystemPrompt()
        )
        
        DebugLogger.shared.logAIRequest("Claude", prompt: prompt)
        
        do {
            let response = try await makeAPICall(request: request)
            let duration = DebugLogger.shared.endTimer("claude_request")
            
            DebugLogger.shared.logAIResponse("Claude", response: response, duration: duration)
            return response
            
        } catch {
            DebugLogger.shared.endTimer("claude_request")
            throw error
        }
    }
    
    private func makeAPICall(request: ClaudeRequest) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw AIServiceError.networkError(URLError(.badURL))
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey!, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 429 {
                        throw AIServiceError.rateLimited
                    }
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw AIServiceError.httpError(httpResponse.statusCode, errorMessage)
                }
            }
            
            let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            
            guard let content = claudeResponse.content.first?.text else {
                throw AIServiceError.invalidResponse("No content in response")
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw AIServiceError.networkError(error)
        }
    }
}

// MARK: - Shared JSON Prompt Generation (Updated for JSON)

extension AIService {
    func getSystemPrompt() -> String {
        return """
        You are an expert Finnish genealogist parsing records from "Juuret Kälviällä".
        
        Your task is to parse genealogical text into JSON format.
        Return ONLY valid JSON, no explanations or markdown formatting.
        
        Key Finnish genealogical patterns:
        - ★ = birth date (format DD.MM.YYYY)
        - † = death date (format DD.MM.YYYY)
        - ∞ = marriage date (format DD.MM.YYYY or ∞ YY for 2-digit year)
        - {FAMILY_ID} = family cross-reference where person is a child
        - <ID> = FamilySearch ID (optional)
        - Patronymics: "Erikinp." = Erik's son, "Matint." = Matti's daughter
        - "II puoliso" = additional spouse, "III puoliso" = third spouse
        - "Lapset" = children section
        - "Lapsena kuollut N" = N children died in infancy
        - Notes marked with *) or **) appear after family data
        
        Extract all available data including:
        - All dates in original DD.MM.YYYY format as strings
        - All names with patronymics as strings
        - Family cross-references from {FAMILY_ID} notation as strings
        - FamilySearch IDs from <ID> notation as strings (without < >)
        - Marriage partners and dates as strings
        - Note markers (* or **) as string arrays
        - All family notes and historical information as string arrays
        
        Return exactly the JSON object with no other text.
        """
    }
    
    func createGenealogyPrompt(familyId: String, familyText: String) -> String {
        return """
        Parse this Finnish genealogical record into JSON format:

        Family ID: \(familyId)
        
        Source Text:
        \(familyText)
        
        Return JSON using this exact structure:
        
        {
          "familyId": "string",
          "pageReferences": ["string"],
          "father": {
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
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "mother": {
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
            "fatherName": null,
            "motherName": null,
            "enhancedDeathDate": null,
            "enhancedMarriageDate": null,
            "spouseBirthDate": null,
            "spouseParentsFamilyId": null
          },
          "additionalSpouses": [
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
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            }
          ],
          "children": [
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
              "fatherName": null,
              "motherName": null,
              "enhancedDeathDate": null,
              "enhancedMarriageDate": null,
              "spouseBirthDate": null,
              "spouseParentsFamilyId": null
            }
          ],
          "notes": ["string"],
          "childrenDiedInfancy": "number or null"
        }
        
        Rules:
        - Use null for missing values, not empty strings
        - All dates as strings in original format (e.g. "09.09.1727")
        - Page references as string array (e.g. ["105", "106"])
        - If no mother, set mother to null
        - Extract family references from {FAMILY_ID} notation (e.g. {Korpi 5} becomes "KORPI 5")
        - Extract FamilySearch IDs from <ID> notation (e.g. <LCJZ-BH3> becomes "LCJZ-BH3")
        - Set enhancement fields (fatherName, motherName, etc.) to null for now
        
        Return ONLY the JSON object. No markdown, no explanations.
        """
    }
}

// MARK: - API Data Structures (unchanged)

// OpenAI API structures
struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let max_tokens: Int
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

// Claude API structures
struct ClaudeRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
    let system: String
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeResponse: Codable {
    let content: [ClaudeContent]
}

struct ClaudeContent: Codable {
    let text: String
}
