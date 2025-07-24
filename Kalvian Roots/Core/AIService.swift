//
//  AIService.swift
//  Kalvian Roots
//
//  AI service abstraction for multiple providers
//
//  Created by Michael Bendio on 7/23/25.
//

import Foundation

/**
 * AIService.swift - Flexible AI service abstraction
 *
 * Supports multiple AI providers (OpenAI, Claude, DeepSeek) with unified interface.
 * Each provider implements the AIService protocol for genealogical text parsing.
 */

// MARK: - AI Service Protocol

/**
 * Unified interface for AI services that can parse genealogical text
 *
 * Supports OpenAI, Claude, DeepSeek, and mock implementations
 * Returns Swift struct initialization code as strings
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
        }
    }
}

// MARK: - Mock AI Service

/**
 * Mock AI service for testing and development
 *
 * Returns hardcoded family structures based on family ID
 * Useful for testing the architecture without API calls
 */
class MockAIService: AIService {
    let name = "Mock AI"
    let isConfigured = true
    
    func configure(apiKey: String) throws {
        // Mock doesn't need configuration
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        print("🤖 MockAI parsing family: \(familyId)")
        
        // Simulate AI processing time
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Return hardcoded responses for known families
        switch familyId.uppercased() {
        case "KORPI 6":
            return mockKorpi6Response()
        case "TEST 1":
            return mockTest1Response()
        default:
            return mockGenericResponse(familyId: familyId)
        }
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

// MARK: - OpenAI Service

/**
 * OpenAI ChatGPT API service for genealogical parsing
 *
 * Uses GPT-4 for parsing Finnish genealogical text into Swift structs
 * Handles API authentication, rate limiting, and response validation
 */
class OpenAIService: AIService {
    let name = "OpenAI GPT-4"
    private var apiKey: String?
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    var isConfigured: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    func configure(apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw AIServiceError.apiKeyMissing
        }
        self.apiKey = apiKey
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        guard isConfigured else {
            throw AIServiceError.notConfigured(name)
        }
        
        let prompt = createGenealogyPrompt(familyId: familyId, familyText: familyText)
        
        let request = OpenAIRequest(
            model: "gpt-4",
            messages: [
                OpenAIMessage(role: "system", content: getSystemPrompt()),
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.1, // Low temperature for consistent parsing
            max_tokens: 2000
        )
        
        return try await makeAPICall(request: request)
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
                    throw AIServiceError.networkError(URLError(.badServerResponse))
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

// MARK: - Claude Service

/**
 * Anthropic Claude API service for genealogical parsing
 *
 * Uses Claude for parsing Finnish genealogical text into Swift structs
 * Alternative to OpenAI with different strengths in text analysis
 */
class ClaudeService: AIService {
    let name = "Claude"
    private var apiKey: String?
    private let baseURL = "https://api.anthropic.com/v1/messages"
    
    var isConfigured: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    func configure(apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw AIServiceError.apiKeyMissing
        }
        self.apiKey = apiKey
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        guard isConfigured else {
            throw AIServiceError.notConfigured(name)
        }
        
        let prompt = createGenealogyPrompt(familyId: familyId, familyText: familyText)
        
        let request = ClaudeRequest(
            model: "claude-3-5-sonnet-20241022",
            max_tokens: 2000,
            messages: [
                ClaudeMessage(role: "user", content: prompt)
            ],
            system: getSystemPrompt()
        )
        
        return try await makeAPICall(request: request)
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
                    throw AIServiceError.networkError(URLError(.badServerResponse))
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

// MARK: - DeepSeek Service

/**
 * DeepSeek API service for genealogical parsing
 *
 * Uses DeepSeek for parsing Finnish genealogical text into Swift structs
 * Cost-effective alternative with good performance on structured tasks
 */
class DeepSeekService: AIService {
    let name = "DeepSeek"
    private var apiKey: String?
    private let baseURL = "https://api.deepseek.com/v1/chat/completions"
    
    var isConfigured: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    func configure(apiKey: String) throws {
        guard !apiKey.isEmpty else {
            throw AIServiceError.apiKeyMissing
        }
        self.apiKey = apiKey
    }
    
    func parseFamily(familyId: String, familyText: String) async throws -> String {
        guard isConfigured else {
            throw AIServiceError.notConfigured(name)
        }
        
        let prompt = createGenealogyPrompt(familyId: familyId, familyText: familyText)
        
        let request = OpenAIRequest( // DeepSeek uses OpenAI-compatible format
            model: "deepseek-chat",
            messages: [
                OpenAIMessage(role: "system", content: getSystemPrompt()),
                OpenAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.1,
            max_tokens: 2000
        )
        
        return try await makeAPICall(request: request)
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
                    throw AIServiceError.networkError(URLError(.badServerResponse))
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

// MARK: - Shared Prompt Generation

extension AIService {
    func getSystemPrompt() -> String {
        return """
        You are an expert genealogist parsing Finnish family records from the book "Juuret Kälviällä".
        
        Your task is to parse genealogical text into Swift struct initialization code.
        Return ONLY the Swift struct code, no explanations or markdown.
        
        Key patterns in Finnish genealogical text:
        - ★ = birth date (format DD.MM.YYYY)
        - † = death date (format DD.MM.YYYY)
        - ∞ = marriage date (format DD.MM.YYYY or ∞ YY for 2-digit year)
        - {FAMILY_ID} = family cross-reference
        - <ID> = FamilySearch ID
        - Patronymics: "Erikinp." = Erik's son, "Matint." = Matti's daughter
        - "II puoliso" = additional spouse
        - "Lapset" = children section
        - "Lapsena kuollut N" = N children died in infancy
        
        Extract all available data including notes, spouse names, and family references.
        """
    }
    
    func createGenealogyPrompt(familyId: String, familyText: String) -> String {
        return """
        Parse this Finnish genealogical record into Swift struct format:

        Family ID: \(familyId)
        
        Text:
        \(familyText)
        
        Return Swift struct initialization code using these structures:
        
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
            // Optional fields...
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
        
        Return ONLY the Family(...) initialization code.
        """
    }
}

// MARK: - API Data Structures

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
