//
//  AIParsingService.swift
//  Kalvian Roots
//
//  AI service orchestration and JSON parsing with enhanced debug logging
//

import Foundation

/**
 * AIParsingService - Manages AI service selection and family text parsing
 *
 * Provides a unified interface for parsing family text using various AI services.
 * Handles service selection, configuration, and JSON response processing.
 */
@Observable
class AIParsingService {
    
    // MARK: - Properties
    
    /// Currently selected AI service
    private var currentService: AIService
    
    /// Available AI services
    private let services: [String: AIService]
    
    // MARK: - Computed Properties
    
    /// Check if current service is configured
    var isConfigured: Bool {
        currentService.isConfigured
    }
    
    /// Get current service name
    var currentServiceName: String {
        currentService.name
    }
    
    /// Get all available service names
    var availableServiceNames: [String] {
        Array(services.keys).sorted()
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.ai, "🤖 Initializing AI Parsing Service")
        
        // Get available services for platform
        let platformServices = PlatformAwareServiceManager.getRecommendedServices()
        
        // Build services dictionary
        var servicesDict: [String: AIService] = [:]
        for service in platformServices {
            servicesDict[service.name] = service
        }
        self.services = servicesDict
        
        let defaultService = PlatformAwareServiceManager.getDefaultService()
        self.currentService = defaultService
        logInfo(.ai, "✅ Selected default AI service: \(defaultService.name)")
        
        logDebug(.ai, "Available AI services: \(availableServiceNames.joined(separator: ", "))")
    }
    
    // MARK: - Service Management
    
    /**
     * Switch to a different AI service
     */
    func switchService(to serviceName: String) throws {
        guard let service = services[serviceName] else {
            logError(.ai, "❌ Unknown AI service: \(serviceName)")
            throw AIServiceError.unknownService(serviceName)
        }
        
        currentService = service
        logInfo(.ai, "✅ Switched to AI service: \(serviceName)")
    }
    
    /**
     * Configure the current AI service with API key
     */
    func configureService(apiKey: String) throws {
        try currentService.configure(apiKey: apiKey)
        logInfo(.ai, "✅ Configured AI service: \(currentServiceName)")
    }
    
    // MARK: - Family Parsing
    
    /**
     * Parse family text using current AI service
     */
    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        logInfo(.parsing, "🎯 Starting family parsing for: \(familyId)")
        logDebug(.parsing, "Using AI service: \(currentServiceName)")
        logTrace(.parsing, "Family text length: \(familyText.count) characters")
        
        DebugLogger.shared.startTimer("ai_parsing")
        
        guard isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentServiceName)")
            throw AIServiceError.notConfigured(currentServiceName)
        }
        
        do {
            // Get JSON response from AI service
            logDebug(.parsing, "📤 Sending request to AI service...")
            let jsonResponse = try await currentService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            let parsingTime = DebugLogger.shared.endTimer("ai_parsing")
            logInfo(.parsing, "📥 Received AI response in \(String(format: "%.2f", parsingTime))s")
            logTrace(.parsing, "Raw JSON response: \(jsonResponse.prefix(500))...")
            
            // Parse JSON to Family object
            let family = try parseJSON(jsonResponse)
            
            // Debug log the parsed family
            debugLogParsedFamily(family)
            
            logInfo(.parsing, "✅ Successfully parsed family: \(familyId)")
            DebugLogger.shared.parseStep(
                "Parse Complete", "Family: \(familyId), Members: \(family.allPersons.count)")
            
            return family
            
        } catch {
            logError(.parsing, "❌ Failed to parse family: \(error)")
            DebugLogger.shared.parseStep("Parse Failed", error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - JSON Parsing
    
    private func parseJSON(_ jsonResponse: String) throws -> Family {
        logTrace(.parsing, "🔄 Starting JSON parsing")
        DebugLogger.shared.parseStep("JSON Parsing", "Response length: \(jsonResponse.count)")
        
        // Clean the JSON response
        let cleanedJSON = cleanJSONResponse(jsonResponse)
        
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            logError(.parsing, "❌ Failed to convert JSON string to data")
            throw AIServiceError.invalidResponse("Could not convert JSON to data")
        }
        
        do {
            // Decode the Family object
            let decoder = JSONDecoder()
            let family = try decoder.decode(Family.self, from: jsonData)
            
            logDebug(.parsing, "✅ JSON decoded successfully")
            logDebug(.parsing, "Family ID: \(family.familyId)")
            logDebug(.parsing, "Parents: \(family.allParents.count)")
            logDebug(.parsing, "Children: \(family.children.count)")
            
            DebugLogger.shared.parseStep("JSON Decoded", "Family: \(family.familyId)")
            
            return family
            
        } catch let decodingError {
            logError(.parsing, "❌ JSON decoding failed: \(decodingError)")
            logError(.parsing, "JSON structure issue: \(decodingError.localizedDescription)")
            
            // Log the problematic JSON for debugging
            if cleanedJSON.count < 5000 {
                logError(.parsing, "Problematic JSON: \(cleanedJSON)")
            } else {
                logError(.parsing, "Problematic JSON (truncated): \(cleanedJSON.prefix(1000))...")
            }
            
            DebugLogger.shared.parseStep("Decode Failed", decodingError.localizedDescription)
            
            // Try fallback parsing
            return try fallbackParseJSON(cleanedJSON)
        }
    }
    
    private func cleanJSONResponse(_ jsonResponse: String) -> String {
        logTrace(.parsing, "🧹 Cleaning JSON response")
        
        var cleaned = jsonResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code block markers if present
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        // Trim again after removing markdown
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        logTrace(.parsing, "JSON cleaned: \(cleaned.count) characters")
        return cleaned
    }
    
    private func fallbackParseJSON(_ malformedJSON: String) throws -> Family {
        logWarn(.parsing, "🔧 Attempting fallback JSON parsing")
        DebugLogger.shared.parseStep("Fallback JSON", "Attempting to extract minimal family data")
        
        // Try to extract basic family information from malformed JSON
        return try createMinimalFamilyFromBrokenJSON(malformedJSON)
    }
    
    // MARK: - FIXED: Updated fallback parser to use new Family initializer
    private func createMinimalFamilyFromBrokenJSON(_ brokenJSON: String) throws -> Family {
        logWarn(.parsing, "⚠️ Creating minimal family structure from broken JSON")
        
        // Extract family ID if possible
        let familyId = extractJSONValue(from: brokenJSON, key: "familyId") ?? "UNKNOWN"
        let fatherName = extractJSONValue(from: brokenJSON, key: "name") ?? "Unknown Father"
        
        // Create minimal viable family structure using the working initializer
        let father = Person(
            name: fatherName,
            noteMarkers: []
        )
        
        let mother = Person(
            name: "Unknown Mother",
            noteMarkers: []
        )
        
        logWarn(.parsing, "⚠️ Created minimal family structure for: \(familyId)")
        
        // FIXED: Use the correct initializer that exists
        return Family(
            familyId: familyId,
            pageReferences: ["999"], // Default page reference
            husband: father,         // ✅ Use the working initializer
            wife: Person(name: "Unknown Mother", noteMarkers: []),
            marriageDate: nil,
            children: [],
            childrenDiedInfancy: nil,
            notes: ["Minimal parsing used - AI response was malformed"],
            noteDefinitions: [:]
        )
    }
    
    private func extractJSONValue(from jsonString: String, key: String) -> String? {
        let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)) else {
            return nil
        }
        
        let matchRange = Range(match.range(at: 1), in: jsonString)!
        return String(jsonString[matchRange])
    }
    
    // MARK: - Debug Logging
    
    /// Debug method to log parsed family details
    private func debugLogParsedFamily(_ family: Family) {
        logInfo(.parsing, "🔍 === PARSED FAMILY DEBUG INFO ===")
        logInfo(.parsing, "📋 Family ID: \(family.familyId)")
        
        // Log Father
        if let father = family.father {
            logInfo(.parsing, "👨 FATHER: \(father.displayName)")
            logInfo(.parsing, "  - Birth: \(father.birthDate ?? "nil")")
            logInfo(.parsing, "  - Death: \(father.deathDate ?? "nil")")
            logInfo(.parsing, "  - Marriage: \(father.marriageDate ?? "nil")")
            logInfo(.parsing, "  - Spouse: \(father.spouse ?? "nil")")
            logInfo(.parsing, "  - asChildRef: \(father.asChild ?? "⚠️ MISSING") ⬅️ (where father came from)")
        }
        
        // Log Mother
        if let mother = family.mother {
            logInfo(.parsing, "👩 MOTHER: \(mother.displayName)")
            logInfo(.parsing, "  - Birth: \(mother.birthDate ?? "nil")")
            logInfo(.parsing, "  - Death: \(mother.deathDate ?? "nil")")
            logInfo(.parsing, "  - Marriage: \(mother.marriageDate ?? "nil")")
            logInfo(.parsing, "  - Spouse: \(mother.spouse ?? "nil")")
            logInfo(.parsing, "  - asChildRef: \(mother.asChild ?? "⚠️ MISSING") ⬅️ (where mother came from)")
        }
        
        // Log Additional Spouses
        for (index, spouse) in family.additionalSpouses.enumerated() {
            logInfo(.parsing, "💑 ADDITIONAL SPOUSE \(index + 1): \(spouse.displayName)")
            logInfo(.parsing, "  - asChildRef: \(spouse.asChild ?? "nil") ⬅️")
        }
        
        // Log Children with emphasis on as-parent references
        logInfo(.parsing, "👶 CHILDREN: \(family.children.count) total")
        var childrenWithRefs = 0
        var childrenWithoutRefs = 0
        
        for (index, child) in family.children.enumerated() {
            logInfo(.parsing, "  [\(index + 1)] \(child.displayName)")
            logInfo(.parsing, "      - Birth: \(child.birthDate ?? "nil")")
            logInfo(.parsing, "      - Death: \(child.deathDate ?? "nil")")
            logInfo(.parsing, "      - Marriage: \(child.marriageDate ?? "nil")")
            logInfo(.parsing, "      - Spouse: \(child.spouse ?? "nil")")
            
            if let asParentRef = child.asParent {
                logInfo(.parsing, "      - asParentRef: \(asParentRef) ⬅️ (where child became parent)")
                childrenWithRefs += 1
            } else {
                logInfo(.parsing, "      - asParentRef: ⚠️ MISSING")
                childrenWithoutRefs += 1
            }
        }
        
        // Summary of cross-references found
        logInfo(.parsing, "📊 CROSS-REFERENCE SUMMARY:")
        let parentsWithRefs = family.allParents.filter { $0.asChild != nil }
        logInfo(.parsing, "  - Parents with as_child refs: \(parentsWithRefs.count)/\(family.allParents.count)")
        if !parentsWithRefs.isEmpty {
            logInfo(.parsing, "  Found parent refs: \(parentsWithRefs.compactMap { $0.asChild }.joined(separator: ", "))")
        }
        
        logInfo(.parsing, "  - Children with as_parent refs: \(childrenWithRefs)/\(family.children.count)")
        if childrenWithRefs > 0 {
            let foundChildRefs = family.children.compactMap { $0.asParent }
            logInfo(.parsing, "  Found child refs: \(foundChildRefs.joined(separator: ", "))")
        } else {
            logWarn(.parsing, "  ⚠️ NO CHILD REFS FOUND!")
        }
        
        // List all cross-references to resolve
        let totalRefs = parentsWithRefs.count + childrenWithRefs
        if totalRefs > 0 {
            logInfo(.parsing, "📍 REFERENCES TO RESOLVE:")
            for parent in parentsWithRefs {
                if let ref = parent.asChild {
                    logInfo(.parsing, "  - \(parent.displayName) → AS_CHILD in: \(ref)")
                }
            }
            for child in family.children {
                if let ref = child.asParent {
                    logInfo(.parsing, "  - \(child.displayName) → AS_PARENT in: \(ref)")
                }
            }
        } else {
            logWarn(.parsing, "  ⚠️ NO CROSS-REFERENCES FOUND TO RESOLVE!")
        }
        
        logInfo(.parsing, "🔍 === END PARSED FAMILY DEBUG ===")
    }
}
