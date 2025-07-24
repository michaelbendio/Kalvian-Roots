//
//  AIService.swift
//  Kalvian Roots
//
//  AI service abstraction with comprehensive debug logging
//

import Foundation

// MARK: - AI Service Protocol

/**
 * Unified interface for AI services with debug logging integration
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

// MARK: - Mock AI Service

/**
 * Mock AI service for testing with debug logging
 */
class MockAIService: AIService {
    let name = "Mock AI"
    let isConfigured = true
    
    func configure(apiKey: String) throws {
        logDebug(.ai, "MockAI configure called (no-op)")
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        logInfo(.ai, "🤖 MockAI parsing family: \(familyId)")
        logTrace(.ai, "Family text length: \(familyText.count) characters")
        
        DebugLogger.shared.startTimer("mock_ai_processing")
        
        // Simulate AI processing time
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let duration = DebugLogger.shared.endTimer("mock_ai_processing")
        logDebug(.ai, "MockAI processing completed in \(String(format: "%.3f", duration))s")
        
        // Return hardcoded responses for known families
        let response: String
        switch familyId.uppercased() {
        case "KORPI 6":
            response = mockKorpi6Response()
            logDebug(.ai, "Returning KORPI 6 mock response")
        case "TEST 1":
            response = mockTest1Response()
            logDebug(.ai, "Returning TEST 1 mock response")
        default:
            response = mockGenericResponse(familyId: familyId)
            logDebug(.ai, "Returning generic mock response for \(familyId)")
        }
        
        logTrace(.ai, "Mock response length: \(response.count) characters")
        return response
    }
    
    private func mockKorpi6Response() -> String {
        return """
        Family(
            familyId: "KORPI 6",
            pageReferences: ["105", "106"],
            father: Person(
                name: "Matti",
                patronymic: "Erikinp.",
                birthDate: "09.09.1727",
                deathDate: "22.08.1812",
                marriageDate: "14.10.1750",
                spouse: "Brita Matint.",
                asChildReference: "KORPI 5",
                familySearchId: "LCJZ-BH3",
                noteMarkers: []
            ),
            mother: Person(
                name: "Brita",
                patronymic: "Matint.",
                birthDate: "05.09.1731",
                deathDate: "11.07.1769",
                marriageDate: "14.10.1750",
                spouse: "Matti Erikinp.",
                asChildReference: "SIKALA 5",
                familySearchId: "KCJW-98X",
                noteMarkers: []
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Maria",
                    birthDate: "10.02.1752",
                    marriageDate: "1773",
                    spouse: "Elias Iso-Peitso",
                    asParentReference: "ISO-PEITSO III 2",
                    familySearchId: "KJJH-2R9",
                    noteMarkers: []
                ),
                Person(
                    name: "Kaarin",
                    birthDate: "01.02.1753",
                    deathDate: "17.04.1795",
                    noteMarkers: []
                ),
                Person(
                    name: "Abraham",
                    birthDate: "08.01.1764",
                    marriageDate: "1787",
                    spouse: "Anna Sikala",
                    asParentReference: "JÄNESNIEMI 5",
                    noteMarkers: []
                )
            ],
            notes: ["Lapsena kuollut 4."],
            childrenDiedInfancy: 4
        )
        """
    }
    
    private func mockTest1Response() -> String {
        return """
        Family(
            familyId: "TEST 1",
            pageReferences: ["1"],
            father: Person(
                name: "Test",
                patronymic: "Matinp.",
                birthDate: "01.01.1700",
                noteMarkers: []
            ),
            mother: Person(
                name: "Example",
                patronymic: "Juhont.",
                birthDate: "01.01.1705",
                noteMarkers: []
            ),
            additionalSpouses: [],
            children: [
                Person(
                    name: "Child",
                    birthDate: "01.01.1725",
                    noteMarkers: []
                )
            ],
            notes: ["Mock family for testing"],
            childrenDiedInfancy: 0
        )
        """
    }
    
    private func mockGenericResponse(familyId: String) -> String {
        return """
        Family(
            familyId: "\(familyId)",
            pageReferences: ["999"],
            father: Person(
                name: "Unknown",
                patronymic: "Matinp.",
                birthDate: "01.01.1700",
                noteMarkers: []
            ),
            mother: nil,
            additionalSpouses: [],
            children: [],
            notes: ["Mock data for \(familyId)"],
            childrenDiedInfancy: 0
        )
        """
    }
}

// MARK: - DeepSeek Service (Enhanced with Debug Logging)

/**
 * DeepSeek API service with comprehensive debug logging
 *
 * Primary AI service for genealogical parsing with detailed tracing
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
        logInfo(.ai, "🤖 DeepSeek parsing family: \(familyId)")
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
            logInfo(.ai, "✅ DeepSeek response received successfully")
            
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

// MARK: - OpenAI Service (With Debug Logging)

/**
 * OpenAI ChatGPT API service with debug logging
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
        logInfo(.ai, "🤖 OpenAI parsing family: \(familyId)")
        
        guard isConfigured else {
            logError(.ai, "❌ OpenAI not configured")
            throw AIServiceError.notConfigured(name)
        }
        
        DebugLogger.shared.startTimer("openai_request")
        
        let prompt = createGenealogyPrompt(familyId: familyId, familyText: familyText)
        
        let request = OpenAIRequest(
            model: "gpt-4",
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

// MARK: - Claude Service (With Debug Logging)

/**
 * Anthropic Claude API service with debug logging
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
        logInfo(.ai, "🤖 Claude parsing family: \(familyId)")
        
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

// MARK: - Shared Prompt Generation (Enhanced)

extension AIService {
    func getSystemPrompt() -> String {
        return """
        You are an expert Finnish genealogist parsing records from "Juuret Kälviällä".
        
        Your task is to parse genealogical text into Swift struct initialization code.
        Return ONLY the Swift struct code, no explanations or markdown formatting.
        
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
        - All dates in original DD.MM.YYYY format
        - All names with patronymics
        - Family cross-references from {FAMILY_ID} notation
        - FamilySearch IDs from <ID> notation
        - Marriage partners and dates
        - Note markers (* or **)
        - All family notes and historical information
        
        Return exactly the Swift Family(...) initialization code with no other text.
        """
    }
    
    func createGenealogyPrompt(familyId: String, familyText: String) -> String {
        return """
        Parse this Finnish genealogical record into Swift struct format:

        Family ID: \(familyId)
        
        Source Text:
        \(familyText)
        
        Return Swift struct initialization using these exact structures:
        
        struct Person {
            var name: String
            var patronymic: String?
            var birthDate: String?
            var deathDate: String?
            var marriageDate: String?
            var spouse: String?
            var asChildReference: String?
            var asParentReference: String?
            var familySearchId: String?
            var noteMarkers: [String]
            // Additional fields with nil defaults
        }
        
        struct Family {
            var familyId: String
            var pageReferences: [String]
            var father: Person
            var mother: Person?
            var additionalSpouses: [Person]
            var children: [Person]
            var notes: [String]
            var childrenDiedInfancy: Int?
        }
        
        Return ONLY the Family(...) struct initialization code. No markdown, no explanations.
        """
    }
}

// MARK: - API Data Structures (unchanged but documented)

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
