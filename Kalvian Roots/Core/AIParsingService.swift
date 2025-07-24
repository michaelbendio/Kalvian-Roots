//
//  AIParsingService.swift
//  Kalvian Roots
//
//  Core AI parsing service with struct parsing
//

import Foundation

/**
 * AIParsingService.swift - Core AI parsing and struct instantiation
 *
 * Orchestrates AI family extraction with Swift struct parsing.
 * Handles multiple AI providers and converts AI responses into Family structs.
 */

/**
 * Main service for parsing genealogical text using AI providers
 *
 * Architecture: AIParsingService → AIService → Swift struct parsing
 * Supports OpenAI, Claude, DeepSeek, and mock implementations
 */
@Observable
class AIParsingService {
    
    // MARK: - Properties
    
    private var currentAIService: AIService
    private let availableServices: [AIService]
    
    var currentServiceName: String {
        currentAIService.name
    }
    
    var availableServiceNames: [String] {
        availableServices.map { $0.name }
    }
    
    var isConfigured: Bool {
        currentAIService.isConfigured
    }
    
    // MARK: - Initialization
    
    init() {
        let mockService = MockAIService()
        let openAIService = OpenAIService()
        let claudeService = ClaudeService()
        let deepSeekService = DeepSeekService()
        
        self.availableServices = [mockService, openAIService, claudeService, deepSeekService]
        self.currentAIService = mockService // Start with mock for testing
        
        // Try to auto-configure from environment or UserDefaults
        autoConfigureServices()
    }
    
    // MARK: - Service Management
    
    /**
     * Switch to a different AI service by name
     */
    func switchToService(named serviceName: String) throws {
        guard let service = availableServices.first(where: { $0.name == serviceName }) else {
            throw AIServiceError.notConfigured("Service '\(serviceName)' not found")
        }
        
        currentAIService = service
        print("🔄 Switched to AI service: \(serviceName)")
    }
    
    /**
     * Configure the current AI service with an API key
     */
    func configureCurrentService(apiKey: String) throws {
        try currentAIService.configure(apiKey: apiKey)
        
        // Optionally save to UserDefaults for persistence
        saveAPIKey(apiKey, for: currentAIService.name)
        
        print("✅ Configured \(currentAIService.name) with API key")
    }
    
    /**
     * Get all available services with their configuration status
     */
    func getServiceStatus() -> [(name: String, configured: Bool)] {
        return availableServices.map { ($0.name, $0.isConfigured) }
    }
    
    // MARK: - Family Parsing
    
    /**
     * Parse a family from genealogical text using the current AI service
     *
     * Flow: AI prompt → Swift struct string → parsed Family struct
     */
    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        print("🤖 AIParsingService parsing family: \(familyId) using \(currentAIService.name)")
        
        guard currentAIService.isConfigured else {
            throw AIServiceError.notConfigured(currentAIService.name)
        }
        
        do {
            // Get Swift struct string from AI
            let structString = try await currentAIService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            print("📄 AI response (\(structString.count) chars)")
            print("Response preview: \(String(structString.prefix(200)))...")
            
            // Parse the struct string into a Family object
            let family = try parseStructString(structString)
            
            print("✅ Successfully parsed family: \(family.familyId)")
            print("   Father: \(family.father.displayName)")
            print("   Mother: \(family.mother?.displayName ?? "nil")")
            print("   Children: \(family.children.count)")
            
            return family
            
        } catch let error as AIServiceError {
            print("❌ AI service error: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Parsing error: \(error.localizedDescription)")
            throw AIServiceError.parsingFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Struct Parsing
    
    /**
     * Parse AI-generated Swift struct string into Family object
     *
     * This is the critical function that converts string like:
     * "Family(familyId: "KORPI 6", father: Person(...)...)"
     * into actual Family struct instance
     */
    private func parseStructString(_ structString: String) throws -> Family {
        print("🔍 Parsing struct string...")
        
        // Clean the response (remove markdown, extra whitespace)
        let cleanedString = cleanStructString(structString)
        
        // Validate basic structure
        guard cleanedString.hasPrefix("Family(") && cleanedString.hasSuffix(")") else {
            throw AIServiceError.parsingFailed("Response doesn't match Family(...) format")
        }
        
        // Use Swift evaluation to parse the struct
        // This is safe because we control the input format
        do {
            let family = try evaluateStructString(cleanedString)
            
            // Validate the parsed family
            let warnings = family.validateStructure()
            if !warnings.isEmpty {
                print("⚠️ Family validation warnings:")
                for warning in warnings {
                    print("   - \(warning)")
                }
            }
            
            return family
            
        } catch {
            print("❌ Struct evaluation failed: \(error)")
            
            // Try fallback parsing if direct evaluation fails
            return try fallbackParseStruct(cleanedString)
        }
    }
    
    /**
     * Clean AI response to valid Swift struct format
     */
    private func cleanStructString(_ response: String) -> String {
        var cleaned = response
        
        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```swift", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // Remove extra whitespace and newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure proper formatting
        if !cleaned.hasPrefix("Family(") {
            // Try to find the Family( start
            if let range = cleaned.range(of: "Family(") {
                cleaned = String(cleaned[range.lowerBound...])
            }
        }
        
        return cleaned
    }
    
    /**
     * Evaluate Swift struct string using controlled string parsing
     *
     * This replaces unsafe eval() with manual struct parsing
     */
    private func evaluateStructString(_ structString: String) throws -> Family {
        // For now, use a simplified approach that manually parses key fields
        // This can be enhanced with more sophisticated parsing if needed
        
        let parser = StructParser(structString)
        return try parser.parseFamily()
    }
    
    /**
     * Fallback parsing when direct evaluation fails
     */
    private func fallbackParseStruct(_ structString: String) throws -> Family {
        print("🔧 Attempting fallback parsing...")
        
        // Extract basic fields using regex patterns
        let familyId = try extractField(from: structString, field: "familyId") ?? "UNKNOWN"
        let pageRefs = try extractArrayField(from: structString, field: "pageReferences") ?? ["999"]
        
        // Create minimal family structure
        let father = Person(
            name: try extractNestedField(from: structString, path: "father.name") ?? "Unknown",
            noteMarkers: []
        )
        
        print("⚠️ Using fallback parsing for family: \(familyId)")
        
        return Family(
            familyId: familyId,
            pageReferences: pageRefs,
            father: father,
            mother: nil,
            additionalSpouses: [],
            children: [],
            notes: ["Fallback parsing used - may be incomplete"],
            childrenDiedInfancy: nil
        )
    }
    
    // MARK: - Field Extraction Helpers
    
    private func extractField(from text: String, field: String) throws -> String? {
        let pattern = "\(field):\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        
        let matchRange = Range(match.range(at: 1), in: text)!
        return String(text[matchRange])
    }
    
    private func extractArrayField(from text: String, field: String) throws -> [String]? {
        let pattern = "\(field):\\s*\\[([^\\]]*)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        
        let matchRange = Range(match.range(at: 1), in: text)!
        let arrayContent = String(text[matchRange])
        
        // Parse array content
        return arrayContent
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
    }
    
    private func extractNestedField(from text: String, path: String) throws -> String? {
        // Simple nested field extraction for paths like "father.name"
        let components = path.components(separatedBy: ".")
        guard components.count == 2 else { return nil }
        
        let objectField = components[0]
        let propertyField = components[1]
        
        // Find the object section
        let objectPattern = "\(objectField):\\s*Person\\("
        guard let objectRange = text.range(of: objectPattern, options: .regularExpression) else { return nil }
        
        // Extract from that point to the end of the Person(...)
        let fromObject = String(text[objectRange.lowerBound...])
        
        return try extractField(from: fromObject, field: propertyField)
    }
    
    // MARK: - Configuration Persistence
    
    private func autoConfigureServices() {
        // Try to load saved API keys
        for service in availableServices {
            if let savedKey = loadAPIKey(for: service.name) {
                try? service.configure(apiKey: savedKey)
            }
        }
    }
    
    private func saveAPIKey(_ apiKey: String, for serviceName: String) {
        UserDefaults.standard.set(apiKey, forKey: "AIService_\(serviceName)_APIKey")
    }
    
    private func loadAPIKey(for serviceName: String) -> String? {
        return UserDefaults.standard.string(forKey: "AIService_\(serviceName)_APIKey")
    }
}

// MARK: - Struct Parser

/**
 * Dedicated parser for Swift struct strings
 *
 * Handles the complex task of converting AI-generated struct strings
 * into actual Swift struct instances
 */
private class StructParser {
    private let structString: String
    private var position = 0
    
    init(_ structString: String) {
        self.structString = structString
    }
    
    func parseFamily() throws -> Family {
        // Skip to Family(
        guard let familyStart = structString.range(of: "Family(") else {
            throw AIServiceError.parsingFailed("No Family( found in response")
        }
        
        position = structString.distance(from: structString.startIndex, to: familyStart.upperBound)
        
        // Parse Family fields
        var familyId: String = ""
        var pageReferences: [String] = []
        var father: Person = Person(name: "Unknown", noteMarkers: [])
        var mother: Person? = nil
        var additionalSpouses: [Person] = []
        var children: [Person] = []
        var notes: [String] = []
        var childrenDiedInfancy: Int? = nil
        
        while position < structString.count {
            skipWhitespace()
            
            if peek() == ")" {
                break // End of Family
            }
            
            let fieldName = try parseIdentifier()
            try expect(":")
            skipWhitespace()
            
            switch fieldName {
            case "familyId":
                familyId = try parseString()
            case "pageReferences":
                pageReferences = try parseStringArray()
            case "father":
                father = try parsePerson()
            case "mother":
                if peekString() == "nil" {
                    try expect("nil")
                    mother = nil
                } else {
                    mother = try parsePerson()
                }
            case "additionalSpouses":
                additionalSpouses = try parsePersonArray()
            case "children":
                children = try parsePersonArray()
            case "notes":
                notes = try parseStringArray()
            case "childrenDiedInfancy":
                if peekString() == "nil" {
                    try expect("nil")
                    childrenDiedInfancy = nil
                } else {
                    childrenDiedInfancy = try parseNumber()
                }
            default:
                // Skip unknown fields
                try skipValue()
            }
            
            skipWhitespace()
            if peek() == "," {
                position += 1
            }
        }
        
        return Family(
            familyId: familyId,
            pageReferences: pageReferences,
            father: father,
            mother: mother,
            additionalSpouses: additionalSpouses,
            children: children,
            notes: notes,
            childrenDiedInfancy: childrenDiedInfancy
        )
    }
    
    private func parsePerson() throws -> Person {
        try expect("Person(")
        
        var name: String = ""
        var patronymic: String? = nil
        var birthDate: String? = nil
        var deathDate: String? = nil
        var marriageDate: String? = nil
        var spouse: String? = nil
        var asChildReference: String? = nil
        var asParentReference: String? = nil
        var familySearchId: String? = nil
        var noteMarkers: [String] = []
        var fatherName: String? = nil
        var motherName: String? = nil
        
        while position < structString.count {
            skipWhitespace()
            
            if peek() == ")" {
                position += 1
                break
            }
            
            let fieldName = try parseIdentifier()
            try expect(":")
            skipWhitespace()
            
            switch fieldName {
            case "name":
                name = try parseString()
            case "patronymic":
                patronymic = try parseOptionalString()
            case "birthDate":
                birthDate = try parseOptionalString()
            case "deathDate":
                deathDate = try parseOptionalString()
            case "marriageDate":
                marriageDate = try parseOptionalString()
            case "spouse":
                spouse = try parseOptionalString()
            case "asChildReference":
                asChildReference = try parseOptionalString()
            case "asParentReference":
                asParentReference = try parseOptionalString()
            case "familySearchId":
                familySearchId = try parseOptionalString()
            case "noteMarkers":
                noteMarkers = try parseStringArray()
            case "fatherName":
                fatherName = try parseOptionalString()
            case "motherName":
                motherName = try parseOptionalString()
            default:
                try skipValue()
            }
            
            skipWhitespace()
            if peek() == "," {
                position += 1
            }
        }
        
        return Person(
            name: name,
            patronymic: patronymic,
            birthDate: birthDate,
            deathDate: deathDate,
            marriageDate: marriageDate,
            spouse: spouse,
            asChildReference: asChildReference,
            asParentReference: asParentReference,
            familySearchId: familySearchId,
            noteMarkers: noteMarkers,
            fatherName: fatherName,
            motherName: motherName
        )
    }
    
    private func parsePersonArray() throws -> [Person] {
        try expect("[")
        var persons: [Person] = []
        
        while position < structString.count {
            skipWhitespace()
            
            if peek() == "]" {
                position += 1
                break
            }
            
            let person = try parsePerson()
            persons.append(person)
            
            skipWhitespace()
            if peek() == "," {
                position += 1
            }
        }
        
        return persons
    }
    
    private func parseString() throws -> String {
        try expect("\"")
        let start = position
        
        while position < structString.count && peek() != "\"" {
            if peek() == "\\" {
                position += 1 // Skip escape character
            }
            position += 1
        }
        
        let endPos = position
        try expect("\"")
        
        let startIndex = structString.index(structString.startIndex, offsetBy: start)
        let endIndex = structString.index(structString.startIndex, offsetBy: endPos)
        
        return String(structString[startIndex..<endIndex])
    }
    
    private func parseOptionalString() throws -> String? {
        if peekString() == "nil" {
            try expect("nil")
            return nil
        } else {
            return try parseString()
        }
    }
    
    private func parseStringArray() throws -> [String] {
        try expect("[")
        var strings: [String] = []
        
        while position < structString.count {
            skipWhitespace()
            
            if peek() == "]" {
                position += 1
                break
            }
            
            let string = try parseString()
            strings.append(string)
            
            skipWhitespace()
            if peek() == "," {
                position += 1
            }
        }
        
        return strings
    }
    
    private func parseNumber() throws -> Int {
        let start = position
        
        while position < structString.count && peek().isWholeNumber {
            position += 1
        }
        
        let startIndex = structString.index(structString.startIndex, offsetBy: start)
        let endIndex = structString.index(structString.startIndex, offsetBy: position)
        let numberString = String(structString[startIndex..<endIndex])
        
        guard let number = Int(numberString) else {
            throw AIServiceError.parsingFailed("Invalid number: \(numberString)")
        }
        
        return number
    }
    
    private func parseIdentifier() throws -> String {
        let start = position
        
        while position < structString.count && (peek().isLetter || peek().isWholeNumber || peek() == "_") {
            position += 1
        }
        
        let startIndex = structString.index(structString.startIndex, offsetBy: start)
        let endIndex = structString.index(structString.startIndex, offsetBy: position)
        
        return String(structString[startIndex..<endIndex])
    }
    
    private func expect(_ expected: String) throws {
        let endPos = position + expected.count
        guard endPos <= structString.count else {
            throw AIServiceError.parsingFailed("Expected '\(expected)' at end of string")
        }
        
        let startIndex = structString.index(structString.startIndex, offsetBy: position)
        let endIndex = structString.index(structString.startIndex, offsetBy: endPos)
        let actual = String(structString[startIndex..<endIndex])
        
        guard actual == expected else {
            throw AIServiceError.parsingFailed("Expected '\(expected)' but found '\(actual)'")
        }
        
        position = endPos
    }
    
    private func peek() -> Character {
        guard position < structString.count else { return "\0" }
        let index = structString.index(structString.startIndex, offsetBy: position)
        return structString[index]
    }
    
    private func peekString(length: Int = 10) -> String {
        guard position < structString.count else { return "" }
        let startIndex = structString.index(structString.startIndex, offsetBy: position)
        let endIndex = structString.index(startIndex, offsetBy: min(length, structString.count - position))
        return String(structString[startIndex..<endIndex])
    }
    
    private func skipWhitespace() {
        while position < structString.count && peek().isWhitespace {
            position += 1
        }
    }
    
    private func skipValue() throws {
        // Skip any value (string, number, object, array)
        skipWhitespace()

        // Handle multi-character object prefix
        if peekString(length: 7) == "Person(" {
            try skipObject()
            return
        }

        let startChar = peek()
        switch startChar {
        case "\"":
            _ = try parseString()
        case "[":
            try skipArray()
        default:
            if startChar.isNumber {
                _ = try parseNumber()
            } else if startChar.isLetter {
                _ = try parseIdentifier()
            } else {
                position += 1
            }
        }
    }
    
    private func skipArray() throws {
        try expect("[")
        var depth = 1
        
        while position < structString.count && depth > 0 {
            let char = peek()
            if char == "[" {
                depth += 1
            } else if char == "]" {
                depth -= 1
            }
            position += 1
        }
    }
    
    private func skipObject() throws {
        // Skip Person(...) or similar
        var depth = 0
        
        while position < structString.count {
            let char = peek()
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                position += 1
                if depth == 0 {
                    break
                }
            } else {
                position += 1
            }
        }
    }
}

