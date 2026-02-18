/**
 * AIParsingService - Manages AI service selection and family text parsing
 *
 * Converts flat AI JSON (father/mother/children) to Family with Couples array
 */

import Foundation

@Observable
class AIParsingService {
    
    // MARK: - Properties
    
    /// The single hosted AI service used for parsing
    private let service: AIService

    
    // MARK: - Computed Properties
    
    /// Check if current service is configured
    var isConfigured: Bool {
        service.isConfigured
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.ai, "🤖 Initializing AI Parsing Service")

        let service = DeepSeekService()
        self.service = service

        logInfo(.ai, "✅ Using hosted AI service: \(service.name)")
    }
    
    func configure(apiKey: String) throws {
        try service.configure(apiKey: apiKey)
    }


    // MARK: - Family Parsing
    
    /**
     * Parse family text using current AI service
     */
    func parseFamily(familyId: String, familyText: String) async throws -> Family {
        logInfo(.parsing, "🎯 Starting family parsing for: \(familyId)")
        logDebug(.parsing, "Using AI service: \(service.name)")
        logTrace(.parsing, "Family text length: \(familyText.count) characters")
        
        DebugLogger.shared.startTimer("ai_parsing")
        
        guard isConfigured else {
            logError(.ai, "❌ AI service not configured: \(service.name)")
            throw AIServiceError.notConfigured(service.name)
        }
        
        do {
            // Get JSON response from AI service
            logDebug(.parsing, "📤 Sending request to AI service...")
            let jsonResponse: String = try await service.parseFamily(
                familyId: familyId,
                familyText: familyText
            )
            
            let parsingTime = DebugLogger.shared.endTimer("ai_parsing")
            logInfo(.parsing, "📥 Received AI response in \(String(format: "%.2f", parsingTime))s")
            logTrace(.parsing, "Raw JSON response: \(jsonResponse.prefix(500))...")
            
            // Parse JSON string to Family object
            let family = try parseJSON(jsonResponse, familyId: familyId)
            
            logDebug(.parsing, "🔍 DEBUG: Checking parsed marriage dates:")
            for (index, couple) in family.couples.enumerated() {
                logDebug(.parsing, "🔍 DEBUG: Couple \(index + 1) marriageDate: '\(couple.marriageDate ?? "nil")'")
                logDebug(.parsing, "🔍 DEBUG: Couple \(index + 1) fullMarriageDate: '\(couple.fullMarriageDate ?? "nil")'")
            }

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
            
            // Convert JSON to Family with modern Couples structure
            let family = try convertJSONToFamilyWithCouples(json, familyId: familyId)
            
            logDebug(.parsing, "✅ JSON converted and decoded successfully")
            logDebug(.parsing, "Family ID: \(family.familyId)")
            logDebug(.parsing, "Couples: \(family.couples.count)")
            logDebug(.parsing, "Total persons: \(family.allPersons.count)")
            
            return family
            
        } catch {
            logError(.parsing, "❌ JSON parsing failed: \(error)")
            logError(.parsing, "❌ Raw JSON that failed: \(cleanedJSON.prefix(500))...")
            
            // FAIL FAST - No minimal parsing fallback
            // This forces the user to see what went wrong and try a different approach
            throw AIServiceError.parsingFailed("AI service returned invalid JSON. Please try a different AI service or retry the request. Error: \(error.localizedDescription)")
        }
    }
    
    /// Convert JSON structure to Family with Couples array
    private func convertJSONToFamilyWithCouples(_ json: [String: Any], familyId providedFamilyId: String) throws -> Family {
        // Extract basic fields
        let familyId = json["familyId"] as? String ?? providedFamilyId
        let pageReferences = extractPageReferences(from: json)
        let notes = json["notes"] as? [String] ?? []
        let noteDefinitions = json["noteDefinitions"] as? [String: String] ?? [:]
        
        // Extract couples array - this is now the ONLY supported format
        guard let couplesData = json["couples"] as? [[String: Any]] else {
            logError(.parsing, "❌ No 'couples' array found in JSON - modern format required")
            throw AIServiceError.invalidResponse("JSON must contain 'couples' array with modern structure")
        }
        
        logDebug(.parsing, "✅ Found couples array with \(couplesData.count) couples")
        
        var couples: [Couple] = []
        
        for (index, coupleData) in couplesData.enumerated() {
            logDebug(.parsing, "Processing couple \(index + 1)")
            
            // Extract husband
            guard let husbandData = coupleData["husband"] as? [String: Any] else {
                throw AIServiceError.invalidResponse("Couple \(index + 1) missing 'husband' data")
            }
            let husband = try convertJSONToPerson(husbandData)
            
            // Extract wife
            guard let wifeData = coupleData["wife"] as? [String: Any] else {
                throw AIServiceError.invalidResponse("Couple \(index + 1) missing 'wife' data")
            }
            let wife = try convertJSONToPerson(wifeData)
            
            // Extract marriage date
            let marriageDate = coupleData["marriageDate"] as? String
            let fullMarriageDate = coupleData["fullMarriageDate"] as? String
            
            // Extract children
            var children: [Person] = []
            if let childrenData = coupleData["children"] as? [[String: Any]] {
                logDebug(.parsing, "Found \(childrenData.count) children for couple \(index + 1)")
                for childData in childrenData {
                    let child = try convertJSONToPerson(childData)
                    children.append(child)
                }
            }
            
            // Extract other couple fields
            let childrenDiedInfancy = coupleData["childrenDiedInfancy"] as? Int
            let coupleNotes = coupleData["coupleNotes"] as? [String] ?? []
            
            // Create couple
            let couple = Couple(
                husband: husband,
                wife: wife,
                marriageDate: marriageDate,
                fullMarriageDate: fullMarriageDate,
                children: children,
                childrenDiedInfancy: childrenDiedInfancy,
                coupleNotes: coupleNotes
            )
            
            couples.append(couple)
            logDebug(.parsing, "✅ Created couple: \(husband.displayName) & \(wife.displayName) with \(children.count) children")
        }
        
        logDebug(.parsing, "✅ Successfully created family with \(couples.count) couples")
        
        return Family(
            familyId: familyId,
            pageReferences: pageReferences,
            couples: couples,
            notes: notes,
            noteDefinitions: noteDefinitions
        )
    }
    
    /// Extract page references from JSON in various formats
    private func extractPageReferences(from json: [String: Any]) -> [String] {
        if let pageReferences = json["pageReferences"] as? [String] {
            return pageReferences
        }
        
        if let pageReference = json["pageReference"] as? String {
            return [pageReference]
        }
        
        if let pages = json["pages"] as? String {
            return pages.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        
        // Default fallback
        return ["Unknown"]
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
            logInfo(.parsing, "  - Death: \(couple.husband.deathDate ?? "nil")")
            if !couple.husband.noteMarkers.isEmpty {
                logInfo(.parsing, "  - NoteMarkers: \(couple.husband.noteMarkers)")
            }
            
            // Log Wife
            logInfo(.parsing, "👩 WIFE: \(couple.wife.displayName)")
            logInfo(.parsing, "  - Birth: \(couple.wife.birthDate ?? "nil")")
            logInfo(.parsing, "  - Death: \(couple.wife.deathDate ?? "nil")")
            logInfo(.parsing, "  - Death: \(couple.wife.deathDate ?? "nil")")
            if !couple.wife.noteMarkers.isEmpty {
                logInfo(.parsing, "  - NoteMarkers: \(couple.wife.noteMarkers)")
            }
            
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
                if !child.noteMarkers.isEmpty {
                    logInfo(.parsing, "      - NoteMarkers: \(child.noteMarkers)")
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
        
        logInfo(.parsing, "📝 NOTE DEFINITIONS: \(family.noteDefinitions.count)")
        for (key, value) in family.noteDefinitions {
            logInfo(.parsing, "  [\(key)]: \(value)")
        }
        
        logInfo(.parsing, "=== END FAMILY DEBUG INFO ===")
    }
}
