/**
 * AIParsingService - Manages AI service selection and family text parsing
 *
 * Converts flat AI JSON (father/mother/children) to Family with Couples array
 */

import Foundation

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
            throw AIServiceError.invalidResponse("Unknown service: \(serviceName)")
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
            let jsonResponse: String = try await currentService.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            let parsingTime = DebugLogger.shared.endTimer("ai_parsing")
            logInfo(.parsing, "📥 Received AI response in \(String(format: "%.2f", parsingTime))s")
            logTrace(.parsing, "Raw JSON response: \(jsonResponse.prefix(500))...")
            
            // Parse JSON string to Family object
            let family = try parseJSON(jsonResponse, familyId: familyId)
            
            // Debug log the parsed family
            debugLogParsedFamily(family)
            
            logInfo(.parsing, "✅ Successfully parsed family: \(familyId)")
            
            DebugLogger.shared.parseStep(
                "Parse Complete",
                "Family: \(familyId), Members: \(family.allPersons.count)"
            )
            
            return family
            
        } catch {
            logError(.parsing, "❌ Failed to parse family: \(error)")
            DebugLogger.shared.parseStep("Parse Failed", error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - JSON Parsing with Couples Structure
    
    private func parseJSON(_ jsonResponse: String, familyId: String) throws -> Family {
        logTrace(.parsing, "🔄 Starting JSON parsing")
        DebugLogger.shared.parseStep("JSON Parsing", "Response length: \(jsonResponse.count)")
        
        // Clean the JSON response
        let cleanedJSON = cleanJSONResponse(jsonResponse)
        
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            logError(.parsing, "❌ Failed to convert JSON string to data")
            throw AIServiceError.invalidResponse("Could not convert JSON to data")
        }
        
        // Decode into dictionary to handle structure conversion
        do {
            let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let json = json else {
                throw AIServiceError.invalidResponse("Invalid JSON structure")
            }
            
            // Convert flat JSON to Family with Couples
            let family = try convertJSONToFamilyWithCouples(json, familyId: familyId)
            
            logDebug(.parsing, "✅ JSON converted and decoded successfully")
            logDebug(.parsing, "Family ID: \(family.familyId)")
            logDebug(.parsing, "Couples: \(family.couples.count)")
            logDebug(.parsing, "Total children: \(family.allPersons.filter { _ in true }.count)")
            
            return family
            
        } catch {
            logError(.parsing, "❌ JSON decoding failed: \(error)")
            
            // Try minimal parsing as fallback
            if let minimalFamily = tryMinimalParsing(jsonString: cleanedJSON, familyId: familyId) {
                logWarn(.parsing, "⚠️ Used minimal parsing fallback for: \(familyId)")
                return minimalFamily
            }
            
            throw AIServiceError.parsingFailed("JSON decoding failed: \(error.localizedDescription)")
        }
    }
    
    /// Convert flat JSON structure to Family with Couples array
    private func convertJSONToFamilyWithCouples(_ json: [String: Any], familyId providedFamilyId: String) throws -> Family {
        // Extract basic fields
        let familyId = json["familyId"] as? String ?? providedFamilyId
        let pageReferences = json["pageReferences"] as? [String] ?? []
        let notes = json["notes"] as? [String] ?? []
        let noteDefinitions = json["noteDefinitions"] as? [String: String] ?? [:]
        
        // Build couples array
        var couples: [Couple] = []
        
        // Primary couple from father/mother
        if let fatherData = json["father"] as? [String: Any] {
            let husband = try convertJSONToPerson(fatherData)
            
            // Wife from mother field
            let wife: Person
            if let motherData = json["mother"] as? [String: Any] {
                wife = try convertJSONToPerson(motherData)
            } else {
                wife = Person(name: "Unknown Mother", noteMarkers: [])
            }
            
            // Children array
            var children: [Person] = []
            if let childrenData = json["children"] as? [[String: Any]] {
                for childData in childrenData {
                    let child = try convertJSONToPerson(childData)
                    // Only include children without their own spouse (married children might belong to additional couples)
                    if child.spouse == nil {
                        children.append(child)
                    }
                }
            }
            
            // Extract marriage date (might be in father data)
            let marriageDate = fatherData["marriageDate"] as? String
            
            // Children died in infancy
            let childrenDiedInfancy = json["childrenDiedInfancy"] as? Int
            
            // Create primary couple
            let primaryCouple = Couple(
                husband: husband,
                wife: wife,
                marriageDate: marriageDate,
                children: children,
                childrenDiedInfancy: childrenDiedInfancy,
                coupleNotes: []
            )
            couples.append(primaryCouple)
            
            logDebug(.parsing, "Created primary couple with \(children.count) children")
        }
        
        // Handle additional spouses (creates additional couples)
        if let additionalSpouses = json["additionalSpouses"] as? [[String: Any]] {
            for spouseData in additionalSpouses {
                // For additional spouses, the husband is the same as primary
                let husband = couples.first?.husband ?? Person(name: "Unknown Father", noteMarkers: [])
                let wife = try convertJSONToPerson(spouseData)
                
                // Find children that belong to this spouse
                var spouseChildren: [Person] = []
                if let childrenData = json["children"] as? [[String: Any]] {
                    for childData in childrenData {
                        if let childSpouse = childData["motherName"] as? String,
                           childSpouse == wife.name {
                            spouseChildren.append(try convertJSONToPerson(childData))
                        }
                    }
                }
                
                let additionalCouple = Couple(
                    husband: husband,
                    wife: wife,
                    marriageDate: spouseData["marriageDate"] as? String,
                    children: spouseChildren,
                    childrenDiedInfancy: nil,
                    coupleNotes: []
                )
                couples.append(additionalCouple)
                
                logDebug(.parsing, "Created additional couple with \(spouseChildren.count) children")
            }
        }
        
        // If no couples were created, create a minimal one
        if couples.isEmpty {
            logWarn(.parsing, "No couples found in JSON, creating minimal couple")
            let minimalCouple = Couple(
                husband: Person(name: "Unknown Father", noteMarkers: []),
                wife: Person(name: "Unknown Mother", noteMarkers: []),
                marriageDate: nil,
                children: [],
                childrenDiedInfancy: nil,
                coupleNotes: []
            )
            couples.append(minimalCouple)
        }
        
        // Create Family with couples array
        return Family(
            familyId: familyId,
            pageReferences: pageReferences,
            couples: couples,
            notes: notes,
            noteDefinitions: noteDefinitions
        )
    }
    
    /// Convert JSON dictionary to Person
    private func convertJSONToPerson(_ data: [String: Any]) throws -> Person {
        return Person(
            name: data["name"] as? String ?? "Unknown",
            patronymic: data["patronymic"] as? String,
            birthDate: data["birthDate"] as? String,
            deathDate: data["deathDate"] as? String,
            marriageDate: data["marriageDate"] as? String,
            fullMarriageDate: data["fullMarriageDate"] as? String,
            spouse: data["spouse"] as? String,
            asChild: data["asChild"] as? String,
            asParent: data["asParent"] as? String,
            familySearchId: data["familySearchId"] as? String,
            noteMarkers: data["noteMarkers"] as? [String] ?? [],
            fatherName: data["fatherName"] as? String,
            motherName: data["motherName"] as? String,
            spouseBirthDate: data["spouseBirthDate"] as? String,
            spouseParentsFamilyId: data["spouseParentsFamilyId"] as? String
        )
    }
    
    /// Clean JSON response from various AI formatting issues
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response
        
        // Remove markdown code blocks
        if cleaned.contains("```json") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }
        
        // Remove any leading/trailing whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract JSON object if wrapped in other text
        if let jsonStart = cleaned.firstIndex(of: "{"),
           let jsonEnd = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[jsonStart...jsonEnd])
        }
        
        return cleaned
    }
    
    /// Attempt minimal parsing for broken JSON responses
    private func tryMinimalParsing(jsonString: String, familyId: String) -> Family? {
        logWarn(.parsing, "⚠️ Attempting minimal parsing for malformed JSON")
        
        // Try to extract at least the family ID
        let extractedFamilyId = extractJSONValue(from: jsonString, key: "familyId") ?? familyId
        let fatherName = extractJSONValue(from: jsonString, key: "name") ?? "Unknown Father"
        
        // Create minimal couple
        let husband = Person(name: fatherName, noteMarkers: [])
        let wife = Person(name: "Unknown Mother", noteMarkers: [])
        
        let minimalCouple = Couple(
            husband: husband,
            wife: wife,
            marriageDate: nil,
            children: [],
            childrenDiedInfancy: nil,
            coupleNotes: []
        )
        
        logWarn(.parsing, "⚠️ Created minimal family structure for: \(extractedFamilyId)")
        
        // Use the Family initializer with couples array
        return Family(
            familyId: extractedFamilyId,
            pageReferences: ["999"],
            couples: [minimalCouple],  // Family expects array of Couples
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
        logInfo(.parsing, "📑 Couples: \(family.couples.count)")
        
        for (index, couple) in family.couples.enumerated() {
            logInfo(.parsing, "=== COUPLE \(index + 1) ===")
            
            // Log Husband
            logInfo(.parsing, "👨 HUSBAND: \(couple.husband.displayName)")
            logInfo(.parsing, "  - Birth: \(couple.husband.birthDate ?? "nil")")
            logInfo(.parsing, "  - Death: \(couple.husband.deathDate ?? "nil")")
            
            // Log Wife
            logInfo(.parsing, "👩 WIFE: \(couple.wife.displayName)")
            logInfo(.parsing, "  - Birth: \(couple.wife.birthDate ?? "nil")")
            logInfo(.parsing, "  - Death: \(couple.wife.deathDate ?? "nil")")
            
            // Log Marriage
            if let marriageDate = couple.marriageDate {
                logInfo(.parsing, "💑 Marriage: \(marriageDate)")
            }
            
            // Log Children
            logInfo(.parsing, "👶 CHILDREN: \(couple.children.count)")
            for (childIndex, child) in couple.children.enumerated() {
                logInfo(.parsing, "  [\(childIndex + 1)] \(child.displayName)")
                if let birthDate = child.birthDate {
                    logInfo(.parsing, "      - Birth: \(birthDate)")
                }
                if let spouse = child.spouse {
                    logInfo(.parsing, "      - Spouse: \(spouse)")
                }
            }
            
            // Children died in infancy
            if let died = couple.childrenDiedInfancy {
                logInfo(.parsing, "☠️ Children died in infancy: \(died)")
            }
        }
        
        // Log Notes
        if !family.notes.isEmpty {
            logInfo(.parsing, "📝 NOTES: \(family.notes.count)")
            for note in family.notes.prefix(3) {
                logInfo(.parsing, "  - \(note.prefix(100))...")
            }
        }
        
        logInfo(.parsing, "=== END FAMILY DEBUG INFO ===")
    }
}
