//
//  AIParsingService.swift
//  Kalvian Roots
//
//  Core AI parsing service with comprehensive debug logging
//

import Foundation

/**
 * AIParsingService.swift - Core AI parsing with detailed tracing
 *
 * Orchestrates AI family extraction with Swift struct parsing and comprehensive
 * debug logging for troubleshooting genealogical text parsing issues.
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
        let configured = currentAIService.isConfigured
        logTrace(.ai, "AIParsingService isConfigured: \(configured) (\(currentServiceName))")
        return configured
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.ai, "🚀 AIParsingService initialization started")
        
        let mockService = MockAIService()
        let openAIService = OpenAIService()
        let claudeService = ClaudeService()
        let deepSeekService = DeepSeekService()
        
        self.availableServices = [deepSeekService, mockService, openAIService, claudeService]
        self.currentAIService = deepSeekService // Start with DeepSeek as primary
        
        logInfo(.ai, "✅ AIParsingService initialized")
        logDebug(.ai, "Available services: \(availableServiceNames.joined(separator: ", "))")
        logInfo(.ai, "Primary service: \(currentServiceName)")
        
        // Try to auto-configure from saved settings
        autoConfigureServices()
    }
    
    // MARK: - Service Management
    
    /**
     * Switch to a different AI service by name
     */
    func switchToService(named serviceName: String) throws {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        guard let service = availableServices.first(where: { $0.name == serviceName }) else {
            logError(.ai, "❌ Service '\(serviceName)' not found")
            throw AIServiceError.notConfigured("Service '\(serviceName)' not found")
        }
        
        currentAIService = service
        logInfo(.ai, "✅ Successfully switched to: \(serviceName)")
        logDebug(.ai, "New service configured: \(service.isConfigured)")
    }
    
    /**
     * Configure the current AI service with an API key
     */
    func configureCurrentService(apiKey: String) throws {
        logInfo(.ai, "🔧 Configuring \(currentAIService.name) with API key")
        logTrace(.ai, "API key provided with length: \(apiKey.count)")
        
        try currentAIService.configure(apiKey: apiKey)
        
        // Save to UserDefaults for persistence
        saveAPIKey(apiKey, for: currentAIService.name)
        
        logInfo(.ai, "✅ Successfully configured \(currentAIService.name)")
    }
    
    /**
     * Get all available services with their configuration status
     */
    func getServiceStatus() -> [(name: String, configured: Bool)] {
        let status = availableServices.map { (name: $0.name, configured: $0.isConfigured) }
        logTrace(.ai, "Service status requested: \(status.map { "\($0.name)=\($0.configured)" }.joined(separator: ", "))")
        return status
    }
    
    // MARK: - Family Parsing (Core Method)
    
    /**
     * Parse a family from genealogical text using the current AI service
     *
     * This is the main entry point for AI-based family extraction with comprehensive logging
     */
    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        logInfo(.parsing, "🤖 Starting AI family parsing for: \(familyId)")
        logDebug(.parsing, "Using AI service: \(currentAIService.name)")
        logDebug(.parsing, "Family text length: \(familyText.count) characters")
        logTrace(.parsing, "Family text preview: \(String(familyText.prefix(300)))...")
        
        DebugLogger.shared.startTimer("total_parsing")
        
        guard currentAIService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentAIService.name)")
            throw AIServiceError.notConfigured(currentAIService.name)
        }
        
        do {
            // Step 1: Get Swift struct string from AI
            logDebug(.ai, "Step 1: Requesting AI parsing from \(currentAIService.name)")
            DebugLogger.shared.startTimer("ai_request")
            
            let structString = try await currentAIService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            let aiDuration = DebugLogger.shared.endTimer("ai_request")
            logInfo(.ai, "✅ AI response received in \(String(format: "%.2f", aiDuration))s")
            logDebug(.ai, "Response length: \(structString.count) characters")
            logTrace(.ai, "Response preview: \(String(structString.prefix(500)))...")
            
            // Step 2: Parse the struct string into a Family object
            logDebug(.parsing, "Step 2: Parsing struct string into Family object")
            DebugLogger.shared.startTimer("struct_parsing")
            
            let family = try parseStructString(structString)
            
            let parseDuration = DebugLogger.shared.endTimer("struct_parsing")
            let totalDuration = DebugLogger.shared.endTimer("total_parsing")
            
            logInfo(.parsing, "✅ Struct parsing completed in \(String(format: "%.3f", parseDuration))s")
            logInfo(.parsing, "🎉 Total parsing completed in \(String(format: "%.2f", totalDuration))s")
            
            // Step 3: Log parsing results
            DebugLogger.shared.logParsingSuccess(family)
            
            return family
            
        } catch let error as AIServiceError {
            _ = DebugLogger.shared.endTimer("ai_request")
            _ = DebugLogger.shared.endTimer("struct_parsing")
            _ = DebugLogger.shared.endTimer("total_parsing")
            
            logError(.ai, "❌ AI service error: \(error.localizedDescription)")
            DebugLogger.shared.logParsingFailure(error, familyId: familyId)
            throw error
        } catch {
            _ = DebugLogger.shared.endTimer("ai_request")
            _ = DebugLogger.shared.endTimer("struct_parsing")
            _ = DebugLogger.shared.endTimer("total_parsing")
            
            logError(.parsing, "❌ Parsing error: \(error.localizedDescription)")
            DebugLogger.shared.logParsingFailure(error, familyId: familyId)
            throw AIServiceError.parsingFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Struct Parsing (Enhanced with Debug Logging)
    
    /**
     * Parse AI-generated Swift struct string into Family object
     *
     * This critical function converts string responses from AI into actual Family structs
     * with comprehensive error handling and fallback strategies.
     */
    private func parseStructString(_ structString: String) throws -> Family {
        logDebug(.parsing, "🔍 Starting struct string parsing")
        DebugLogger.shared.parseStep("Clean response", "Removing markdown and formatting")
        
        // Clean the response (remove markdown, extra whitespace)
        let cleanedString = cleanStructString(structString)
        logTrace(.parsing, "Cleaned string length: \(cleanedString.count)")
        logTrace(.parsing, "Cleaned preview: \(String(cleanedString.prefix(200)))...")
        
        // Validate basic structure
        guard cleanedString.hasPrefix("Family(") && cleanedString.hasSuffix(")") else {
            logError(.parsing, "❌ Response doesn't match Family(...) format")
            logTrace(.parsing, "Invalid format - starts with: \(String(cleanedString.prefix(50)))")
            throw AIServiceError.parsingFailed("Response doesn't match Family(...) format")
        }
        
        DebugLogger.shared.parseStep("Validate format", "✅ Family(...) format confirmed")
        
        // Use Swift evaluation to parse the struct
        do {
            DebugLogger.shared.parseStep("Evaluate struct", "Using StructParser")
            let family = try evaluateStructString(cleanedString)
            
            // Validate the parsed family
            logDebug(.parsing, "Validating parsed family structure")
            let warnings = family.validateStructure()
            DebugLogger.shared.logFamilyValidation(family, warnings: warnings)
            
            logInfo(.parsing, "✅ Struct parsing successful")
            return family
            
        } catch {
            logWarn(.parsing, "⚠️ Primary struct parsing failed: \(error)")
            
            // Try fallback parsing if direct evaluation fails
            DebugLogger.shared.parseStep("Fallback parsing", "Attempting regex-based extraction")
            return try fallbackParseStruct(cleanedString)
        }
    }
    
    /**
     * Clean AI response to valid Swift struct format
     */
    private func cleanStructString(_ response: String) -> String {
        logTrace(.parsing, "Cleaning AI response string")
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
                logTrace(.parsing, "Found Family( at position, trimmed prefix")
            }
        }
        
        logTrace(.parsing, "String cleaning complete")
        return cleaned
    }
    
    /**
     * Evaluate Swift struct string using controlled struct parsing
     */
    private func evaluateStructString(_ structString: String) throws -> Family {
        logDebug(.parsing, "📝 Evaluating struct string with StructParser")
        
        let parser = StructParser(structString)
        let family = try parser.parseFamily()
        
        logDebug(.parsing, "✅ StructParser completed successfully")
        return family
    }
    
    /**
     * Fallback parsing when direct evaluation fails
     */
    private func fallbackParseStruct(_ structString: String) throws -> Family {
        logWarn(.parsing, "🔧 Using fallback parsing method")
        
        // Extract basic fields using regex patterns
        let familyId = try extractField(from: structString, field: "familyId") ?? "UNKNOWN"
        let pageRefs = try extractArrayField(from: structString, field: "pageReferences") ?? ["999"]
        
        logDebug(.parsing, "Fallback extracted familyId: \(familyId)")
        logDebug(.parsing, "Fallback extracted pageRefs: \(pageRefs)")
        
        // Create minimal family structure
        let father = Person(
            name: try extractNestedField(from: structString, path: "father.name") ?? "Unknown",
            noteMarkers: []
        )
        
        logWarn(.parsing, "⚠️ Using fallback parsing for family: \(familyId)")
        
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
        logTrace(.parsing, "Extracting field: \(field)")
        
        let pattern = "\(field):\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            logTrace(.parsing, "Field \(field) not found")
            return nil
        }
        
        let matchRange = Range(match.range(at: 1), in: text)!
        let value = String(text[matchRange])
        logTrace(.parsing, "Extracted \(field): \(value)")
        return value
    }
    
    private func extractArrayField(from text: String, field: String) throws -> [String]? {
        logTrace(.parsing, "Extracting array field: \(field)")
        
        let pattern = "\(field):\\s*\\[([^\\]]*)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        
        let matchRange = Range(match.range(at: 1), in: text)!
        let arrayContent = String(text[matchRange])
        
        // Parse array content
        let array = arrayContent
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        
        logTrace(.parsing, "Extracted \(field) array: \(array)")
        return array
    }
    
    private func extractNestedField(from text: String, path: String) throws -> String? {
        logTrace(.parsing, "Extracting nested field: \(path)")
        
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
        logDebug(.ai, "🔧 Auto-configuring services from saved settings")
        
        // Try to load saved API keys
        for service in availableServices {
            if let savedKey = loadAPIKey(for: service.name) {
                do {
                    try service.configure(apiKey: savedKey)
                    logInfo(.ai, "✅ Auto-configured \(service.name) from saved API key")
                } catch {
                    logWarn(.ai, "⚠️ Failed to auto-configure \(service.name): \(error)")
                }
            } else {
                logTrace(.ai, "No saved API key for \(service.name)")
            }
        }
    }
    
    private func saveAPIKey(_ apiKey: String, for serviceName: String) {
        logTrace(.ai, "💾 Saving API key for \(serviceName)")
        UserDefaults.standard.set(apiKey, forKey: "AIService_\(serviceName)_APIKey")
    }
    
    private func loadAPIKey(for serviceName: String) -> String? {
        let key = UserDefaults.standard.string(forKey: "AIService_\(serviceName)_APIKey")
        logTrace(.ai, "📂 Loading API key for \(serviceName): \(key != nil ? "found" : "not found")")
        return key
    }
}

// MARK: - Enhanced StructParser with Debug Logging

/**
 * Dedicated parser for Swift struct strings with comprehensive logging
 *
 * Handles the complex task of converting AI-generated struct strings
 * into actual Swift struct instances with detailed tracing.
 */
private class StructParser {
    private let structString: String
    private var position = 0
    
    init(_ structString: String) {
        self.structString = structString
        logTrace(.parsing, "📝 StructParser initialized with \(structString.count) characters")
    }
    
    func parseFamily() throws -> Family {
        logDebug(.parsing, "🏗️ Starting Family struct parsing")
        
        // Skip to Family(
        guard let familyStart = structString.range(of: "Family(") else {
            logError(.parsing, "❌ No Family( found in response")
            throw AIServiceError.parsingFailed("No Family( found in response")
        }
        
        position = structString.distance(from: structString.startIndex, to: familyStart.upperBound)
        logTrace(.parsing, "Found Family( at position \(position)")
        
        // Parse Family fields
        var familyId: String = ""
        var pageReferences: [String] = []
        var father: Person = Person(name: "Unknown", noteMarkers: [])
        var mother: Person? = nil
        var additionalSpouses: [Person] = []
        var children: [Person] = []
        var notes: [String] = []
        var childrenDiedInfancy: Int? = nil
        
        var fieldsCount = 0
        
        while position < structString.count {
            skipWhitespace()
            
            if peek() == ")" {
                break // End of Family
            }
            
            let fieldName = try parseIdentifier()
            logTrace(.parsing, "Parsing field: \(fieldName)")
            try expect(":")
            skipWhitespace()
            
            switch fieldName {
            case "familyId":
                familyId = try parseString()
                logTrace(.parsing, "Parsed familyId: \(familyId)")
            case "pageReferences":
                pageReferences = try parseStringArray()
                logTrace(.parsing, "Parsed pageReferences: \(pageReferences)")
            case "father":
                father = try parsePerson()
                logTrace(.parsing, "Parsed father: \(father.displayName)")
            case "mother":
                if peekString() == "nil" {
                    try expect("nil")
                    mother = nil
                    logTrace(.parsing, "Parsed mother: nil")
                } else {
                    mother = try parsePerson()
                    logTrace(.parsing, "Parsed mother: \(mother?.displayName ?? "unknown")")
                }
            case "additionalSpouses":
                additionalSpouses = try parsePersonArray()
                logTrace(.parsing, "Parsed additionalSpouses: \(additionalSpouses.count)")
            case "children":
                children = try parsePersonArray()
                logTrace(.parsing, "Parsed children: \(children.count)")
            case "notes":
                notes = try parseStringArray()
                logTrace(.parsing, "Parsed notes: \(notes.count)")
            case "childrenDiedInfancy":
                if peekString() == "nil" {
                    try expect("nil")
                    childrenDiedInfancy = nil
                } else {
                    childrenDiedInfancy = try parseNumber()
                }
                logTrace(.parsing, "Parsed childrenDiedInfancy: \(childrenDiedInfancy?.description ?? "nil")")
            default:
                // Skip unknown fields
                logTrace(.parsing, "Skipping unknown field: \(fieldName)")
                try skipValue()
            }
            
            fieldsCount += 1
            skipWhitespace()
            if peek() == "," {
                position += 1
            }
        }
        
        logDebug(.parsing, "✅ Family parsing complete with \(fieldsCount) fields")
        
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
        logTrace(.parsing, "👤 Parsing Person struct")
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
        
        logTrace(.parsing, "✅ Person parsed: \(name)")
        
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
