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
        
        // Initialize service factory
//        let factory = AIServiceFactory()
        
        // Get available services for platform
        let platformServices = PlatformAwareServiceManager.getRecommendedServices()
        
        // Build services dictionar
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
            DebugLogger.shared.parseStep("Parse Complete", "Family: \(familyId), Members: \(family.allPersons.count)")
            
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
    
    private func createMinimalFamilyFromBrokenJSON(_ brokenJSON: String) throws -> Family {
        logWarn(.parsing, "⚠️ Creating minimal family structure from broken JSON")
        
        // Extract family ID if possible
        let familyId = extractJSONValue(from: brokenJSON, key: "familyId") ?? "UNKNOWN"
        let fatherName = extractJSONValue(from: brokenJSON, key: "name") ?? "Unknown Father"
        
        // Create minimal viable family structure
        let father = Person(
            name: fatherName,
            noteMarkers: []
        )
        
        logWarn(.parsing, "⚠️ Created minimal family structure for: \(familyId)")
        
        return Family(
            familyId: familyId,
            pageReferences: ["999"], // Default page reference
            father: father,
            mother: nil,
            additionalSpouses: [],
            children: [],
            notes: ["Minimal parsing used - AI response was malformed"],
            childrenDiedInfancy: nil
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
        logInfo(.parsing, "👨 FATHER: \(family.father.displayName)")
        logInfo(.parsing, "  - Birth: \(family.father.birthDate ?? "nil")")
        logInfo(.parsing, "  - Death: \(family.father.deathDate ?? "nil")")
        logInfo(.parsing, "  - Marriage: \(family.father.marriageDate ?? "nil")")
        logInfo(.parsing, "  - Spouse: \(family.father.spouse ?? "nil")")
        logInfo(.parsing, "  - asChildRef: \(family.father.asChildReference ?? "⚠️ MISSING") ⬅️ (where father came from)")
        
        // Log Mother
        if let mother = family.mother {
            logInfo(.parsing, "👩 MOTHER: \(mother.displayName)")
            logInfo(.parsing, "  - Birth: \(mother.birthDate ?? "nil")")
            logInfo(.parsing, "  - Death: \(mother.deathDate ?? "nil")")
            logInfo(.parsing, "  - Marriage: \(mother.marriageDate ?? "nil")")
            logInfo(.parsing, "  - Spouse: \(mother.spouse ?? "nil")")
            logInfo(.parsing, "  - asChildRef: \(mother.asChildReference ?? "⚠️ MISSING") ⬅️ (where mother came from)")
        }
        
        // Log Additional Spouses
        for (index, spouse) in family.additionalSpouses.enumerated() {
            logInfo(.parsing, "💑 ADDITIONAL SPOUSE \(index + 1): \(spouse.displayName)")
            logInfo(.parsing, "  - asChildRef: \(spouse.asChildReference ?? "nil") ⬅️")
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
            
            // Children should ONLY have asParentReference (where they went)
            if let asParentRef = child.asParentReference {
                logInfo(.parsing, "      - ➡️ AS_PARENT_REF: \(asParentRef) ✅ (family they created)")
                childrenWithRefs += 1
            } else if child.spouse != nil {
                // Married child without reference - this might be a parsing issue
                logWarn(.parsing, "      - ⚠️ NO AS_PARENT_REF (married child - expected reference!)")
                childrenWithoutRefs += 1
            } else {
                logInfo(.parsing, "      - No reference (unmarried child)")
            }
            
            // Flag if child incorrectly has asChildReference
            if child.asChildReference != nil {
                logError(.parsing, "      - ❌ ERROR: Child has asChildReference (should not happen!)")
            }
        }
        
        // Summary of cross-references
        logInfo(.parsing, "📊 CROSS-REFERENCE SUMMARY:")
        logInfo(.parsing, "  - Parents with as_child refs: \(family.parentsNeedingResolution.count)")
        logInfo(.parsing, "  - Children with as_parent refs: \(childrenWithRefs)")
        logInfo(.parsing, "  - Married children missing refs: \(childrenWithoutRefs)")
        
        // Expected vs Found for KORPI 6
        if family.familyId.uppercased().contains("KORPI 6") {
            logInfo(.parsing, "🎯 KORPI 6 SPECIFIC CHECK:")
            logInfo(.parsing, "  Expected parent refs: KORPI 5 (father), SIKALA 5 (mother)")
            logInfo(.parsing, "  Expected child refs: ISO-PEITSO III 2, LAXO 4, KORVELA 3, RIMPILÄ 7, JÄNESNIEMI 5")
            logInfo(.parsing, "  Found parent refs: \(family.father.asChildReference ?? "none"), \(family.mother?.asChildReference ?? "none")")
            
            let foundChildRefs = family.children.compactMap { $0.asParentReference }
            logInfo(.parsing, "  Found child refs: \(foundChildRefs.isEmpty ? "NONE!" : foundChildRefs.joined(separator: ", "))")
        }
        
        // List all cross-references to resolve
        let totalRefs = family.parentsNeedingResolution.count + childrenWithRefs
        if totalRefs > 0 {
            logInfo(.parsing, "📍 REFERENCES TO RESOLVE:")
            for parent in family.parentsNeedingResolution {
                if let ref = parent.asChildReference {
                    logInfo(.parsing, "  - \(parent.displayName) → AS_CHILD in: \(ref)")
                }
            }
            for child in family.children {
                if let ref = child.asParentReference {
                    logInfo(.parsing, "  - \(child.displayName) → AS_PARENT in: \(ref)")
                }
            }
        } else {
            logWarn(.parsing, "  ⚠️ NO CROSS-REFERENCES FOUND TO RESOLVE!")
        }
        
        logInfo(.parsing, "🔍 === END PARSED FAMILY DEBUG ===")
    }
}

