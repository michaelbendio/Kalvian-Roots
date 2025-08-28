//
//  JuuretApp.swift
//  Kalvian Roots
//
//  Complete application coordinator with unified workflow and MLX integration
//

import Foundation
import SwiftUI

/**
 * Main application coordinator - simplified to work with actual codebase
 */
@Observable
class JuuretApp {
    
    // MARK: - Core Services
    
    private enum PersonRole: String {
        case parent = "father"
        case mother = "mother"
        case child = "child"
    }
    
    /// AI parsing service with configurable providers
    let aiParsingService: AIParsingService
    
    /// Cross-reference resolution service
    var familyResolver: FamilyResolver
    
    /// Name equivalence learning service
    let nameEquivalenceManager: NameEquivalenceManager
    
    /// File management service
    var fileManager: FileManager
    
    // MARK: - State Properties
    
    /// Currently extracted family
    var currentFamily: Family?
    
    /// Enhanced family with cross-reference data
    var enhancedFamily: Family?
    
    /// Processing state
    var isProcessing = false
    
    /// Error state
    var errorMessage: String?
    
    /// Extraction progress tracking
    var extractionProgress: ExtractionProgress = .idle

    // MARK: - Manual Citation Overrides
    private var manualCitations: [String: String] = [:] // key: familyId|personId
    private var familyNetworkWorkflow: FamilyNetworkWorkflow?
    // MARK: - Computed Properties
    
    /// Check if app is ready for family extraction
    var isReady: Bool {
        fileManager.isFileLoaded && aiParsingService.isConfigured
    }
    
    /// Available AI services for switching
    var availableServices: [String] {
        aiParsingService.availableServiceNames
    }
    
    /// Current AI service name for display
    var currentServiceName: String {
        return aiParsingService.currentServiceName
    }
    
    // MARK: - Initialization
    
    // CRITICAL FIX: Update JuuretApp initialization in JuuretApp.swift
    // Replace the existing init() method with this updated version:

    // MARK: - Initialization

    init() {
        logInfo(.app, "🚀 JuuretApp initialization started")
        
        // Initialize core services locally first
        let localNameEquivalenceManager = NameEquivalenceManager()
        let localFileManager = FileManager()  // Initialize fileManager FIRST
        
        let localAIParsingService: AIParsingService
        #if os(macOS) && arch(arm64)
        // Apple Silicon Mac - use enhanced service with MLX support
        logInfo(.ai, "🧠 Initializing AI services with MLX support (Apple Silicon)")
        localAIParsingService = AIParsingService()
        logInfo(.ai, "✅ Enhanced AI parsing service initialized")
        
        logDebug(.ai, "Available services: \(localAIParsingService.availableServiceNames.joined(separator: ", "))")
        
        #else
        // Fallback for non-Apple Silicon (shouldn't happen in this app)
        logWarn(.ai, "⚠️ Non-Apple Silicon detected - using cloud services only")
        localAIParsingService = AIParsingService()
        #endif
        
        let localFamilyResolver = FamilyResolver(
            aiParsingService: localAIParsingService,
            nameEquivalenceManager: localNameEquivalenceManager,
            fileManager: localFileManager
        )
        
        // Assign all to self properties at the end
        self.nameEquivalenceManager = localNameEquivalenceManager
        self.fileManager = localFileManager
        self.aiParsingService = localAIParsingService
        self.familyResolver = localFamilyResolver
        
        logInfo(.app, "✅ Core services initialized with memory-efficient architecture")
        logInfo(.app, "Current AI service: \(self.currentServiceName)")
        logDebug(.app, "Available services: \(self.availableServices.joined(separator: ", "))")
        
        // Auto-load default file
        Task { @MainActor in
            logDebug(.file, "Attempting auto-load of default file")
            
            await self.fileManager.autoLoadDefaultFile()
            
            if let fileContent = self.fileManager.currentFileContent {
                logInfo(.file, "✅ Auto-loaded file - FamilyResolver has direct access")
                logDebug(.file, "File content length: \(fileContent.count) characters")
            } else {
                logDebug(.file, "No default file found for auto-loading")
                logInfo(.file, "💡 Use File menu to open JuuretKälviällä.txt")
            }
        }
        
        logInfo(.app, "🎉 JuuretApp initialization")
        logDebug(.app, "Ready state: \(self.isReady)")

        // Load manual citations
        loadManualCitations()
    }
    
    // MARK: - AI Service Management
    
    /**
     * Switch to a different AI service
     */
    func switchAIService(to serviceName: String) throws {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        try aiParsingService.switchService(to: serviceName)
        
        // Clear any error state since service changed
        if errorMessage?.contains("not configured") == true {
            errorMessage = nil
            logDebug(.app, "Cleared configuration error after service switch")
        }
        
        logInfo(.ai, "✅ Successfully switched to: \(serviceName)")
    }
    
    /**
     * Configure current AI service with API key
     */
    func configureAIService(apiKey: String) async throws {
        logInfo(.ai, "🔧 Configuring \(currentServiceName) with API key")
        
        try aiParsingService.configureService(apiKey: apiKey)
        
        errorMessage = nil
        logDebug(.app, "Cleared error state after successful AI configuration")
        
        logInfo(.ai, "✅ Successfully configured \(currentServiceName)")
    }
    
    // MARK: - File Management
    
    /**
     * Load file via file picke
     */
    @MainActor
    func loadFile() async {
        logInfo(.file, "📁 User initiated file loading")
        do {
            let content = try await fileManager.openFile()
            
            // Clear any previous family data when new file loaded
            currentFamily = nil
            enhancedFamily = nil
            extractionProgress = .idle
            errorMessage = nil

            logInfo(.file, "✅ File loaded successfully with memory-efficient architecture")
            logDebug(.file, "File content length: \(content.count) characters")
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
            logError(.file, "❌ Failed to load file: \(error)")
        }
    }
    
    // MARK: - Basic Family Processing
    
    /**
     * Extract family using AI parsing
     */
    func extractFamily(familyId: String) async throws {
        logInfo(.app, "🚀 Starting family extraction for: \(familyId)")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        logDebug(.parsing, "Normalized family ID: \(normalizedId)")
        
        guard aiParsingService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentServiceName)")
            throw JuuretError.aiServiceNotConfigured(currentServiceName)
        }
        
        guard let fileContent = fileManager.currentFileContent else {
            logError(.file, "❌ No file content available")
            throw JuuretError.noFileLoaded
        }
        
        // Clear previous state
        await MainActor.run {
            currentFamily = nil
            enhancedFamily = nil
            extractionProgress = .extractingFamily
            errorMessage = nil
            isProcessing = true
        }
        
        logDebug(.app, "Cleared previous state, starting extraction")
        
        do {
            // Extract family text from file
            let familyText = try extractFamilyText(familyId: normalizedId, from: fileContent)
            logDebug(.parsing, "Extracted family text (\(familyText.count) chars)")
            
            // Parse using AI service
            await MainActor.run {
                extractionProgress = .extractingFamily
            }
            
            let family = try await aiParsingService.parseFamily(
                familyId: normalizedId,
                familyText: familyText
            )
            
            // Update UI on main thread
            await MainActor.run {
                currentFamily = family
                extractionProgress = .familyExtracted
                isProcessing = false
                logInfo(.app, "✅ Family extraction completed: \(family.familyId)")
                logDebug(.parsing, "Family has \(family.children.count) children")
            }
            
        } catch {
            await MainActor.run {
                extractionProgress = .idle
                isProcessing = false
                errorMessage = "Extraction failed: \(error.localizedDescription)"
            }
            
            logError(.app, "❌ Family extraction failed: \(error)")
            throw error
        }
    }
    
    /**
     * Extract family with complete cross-references
     */
    func extractFamilyComplete(familyId: String) async throws {
        logInfo(.app, "🚀 Starting complete family extraction for: \(familyId)")
        
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        logDebug(.parsing, "Normalized family ID: \(normalizedId)")
        
        // Validate prerequisites
        guard aiParsingService.isConfigured else {
            logError(.ai, "❌ AI service not configured: \(currentServiceName)")
            throw JuuretError.aiServiceNotConfigured(currentServiceName)
        }
        
        guard fileManager.isFileLoaded else {
            logError(.file, "❌ No file loaded")
            throw JuuretError.noFileLoaded
        }
        
        guard let fileContent = fileManager.currentFileContent else {
            logError(.file, "❌ No file content available")
            throw JuuretError.noFileLoaded
        }
        
        // Clear previous state BUT preserve workflow if it's for the same family
        await MainActor.run {
            // Only clear workflow if we're extracting a different family
            if currentFamily?.familyId != normalizedId {
                currentFamily = nil
                enhancedFamily = nil
                familyNetworkWorkflow = nil
            }
            extractionProgress = .extractingFamily
            errorMessage = nil
            isProcessing = true
        }
        
        do {
            // First extract the family using the AI service
            let familyText = try extractFamilyText(familyId: normalizedId, from: fileContent)
            logDebug(.parsing, "Extracted family text (\(familyText.count) chars)")
            
            // Parse the family
            let family = try await aiParsingService.parseFamily(
                familyId: normalizedId,
                familyText: familyText
            )
            
            // FIX: Create workflow with the correct constructor signature
            // The original FamilyNetworkWorkflow expects a Family object as the first parameter
            let workflow = FamilyNetworkWorkflow(
                nuclearFamily: family,           // Changed from aiParsingService
                familyResolver: familyResolver,
                resolveCrossReferences: true     // Removed fileManager parameter
            )
            
            // Process the workflow
            try await workflow.process()  // Changed from processFamilyNetwork(for:)
            
            // Update app state with results
            await MainActor.run {
                if let network = workflow.getFamilyNetwork() {
                    currentFamily = network.mainFamily
                    enhancedFamily = network.mainFamily
                    familyNetworkWorkflow = workflow  // CRITICAL: Store workflow instance
                    extractionProgress = .complete
                    isProcessing = false
                    
                    // DEBUG: Log what citations were generated
                    let citations = workflow.getActiveCitations()
                    logInfo(.app, "✅ Complete family extraction completed")
                    logInfo(.app, "📄 Generated \(citations.count) enhanced citations")
                    logDebug(.app, "📄 Citation keys: \(Array(citations.keys))")
                } else {
                    logError(.app, "❌ No network returned from workflow")
                    extractionProgress = .idle
                    isProcessing = false
                    errorMessage = "Failed to build family network"
                }
            }
            
        } catch {
            await MainActor.run {
                extractionProgress = .idle
                isProcessing = false
                errorMessage = "Complete extraction failed: \(error.localizedDescription)"
                familyNetworkWorkflow = nil  // Clear on error
            }
            
            logError(.app, "❌ Complete family extraction failed: \(error)")
            throw error
        }
    }

    
    // MARK: - Family Text Extraction
    
    private func extractFamilyText(familyId: String, from fileContent: String) throws -> String {
        logDebug(.parsing, "🔍 Extracting text for family: \(familyId)")
        
        let lines = fileContent.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inTargetFamily = false
        var familyFound = false
        
        let normalizedTargetId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if this line starts a new family
            if let currentFamilyId = extractFamilyIdFromLine(trimmedLine) {
                let normalizedCurrentId = currentFamilyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                if normalizedCurrentId == normalizedTargetId {
                    // Found our target family
                    inTargetFamily = true
                    familyFound = true
                    familyLines.append(line)
                    logDebug(.parsing, "Found target family header: \(trimmedLine)")
                } else if inTargetFamily {
                    // Started a different family - stop collecting
                    logDebug(.parsing, "Found next family: \(currentFamilyId), stopping collection")
                    break
                } else {
                    // Not our target family, continue searching
                    inTargetFamily = false
                }
            } else if inTargetFamily {
                // We're in our target family, collect all lines
                familyLines.append(line)
                
                // Optional: Stop at empty line after substantial content
                // But only if we have children section and notes
                if trimmedLine.isEmpty && familyLines.count > 10 {
                    let content = familyLines.joined(separator: "\n")
                    if content.contains("Lapset") || content.contains("★") {
                        // Check if next non-empty line starts a new family
                        let remainingLines = Array(lines.dropFirst(index + 1))
                        for nextLine in remainingLines {
                            let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !nextTrimmed.isEmpty {
                                if extractFamilyIdFromLine(nextTrimmed) != nil {
                                    // Next non-empty line is a family - we can stop
                                    logDebug(.parsing, "Found end of family at empty line before: \(nextTrimmed)")
                                    break
                                } else {
                                    // Next line is content, keep going
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        guard familyFound else {
            logError(.parsing, "❌ Family \(familyId) not found in file")
            throw JuuretError.familyNotFound(familyId)
        }
        
        let familyText = familyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        logInfo(.parsing, "✅ Extracted family text for \(familyId) (\(familyText.count) characters)")
        logDebug(.parsing, "Family text preview: \(String(familyText.prefix(200)))...")
        
        // Additional validation
        if familyText.count < 50 {
            logWarn(.parsing, "⚠️ Extracted family text seems too short: \(familyText.count) characters")
            logWarn(.parsing, "Full extracted text: '\(familyText)'")
        }
        
        return familyText
    }

    private func extractFamilyIdFromLine(_ line: String) -> String? {
        // More robust family ID extraction
        // Pattern: FAMILY_NAME [ROMAN_NUMERALS] NUMBER[LETTER], page(s) ...
        // Examples: "KORPI 6, pages 105-106", "SIKALA II 3, page 45", "HANHISALO III 1A, page 200"
        
        let patterns = [
            // Pattern 1: FAMILY_NAME NUMBER, page(s)
            #"^([A-ZÄÖÅ-]+\s+\d+[A-Z]?)(?:,|\s)"#,
            // Pattern 2: FAMILY_NAME ROMAN NUMBER, page(s)
            #"^([A-ZÄÖÅ-]+\s+(?:II|III|IV|V|VI)\s+\d+[A-Z]?)(?:,|\s)"#,
            // Pattern 3: Just the family name and number (more permissive)
            #"^([A-ZÄÖÅ-]+(?:\s+(?:II|III|IV|V|VI))?\s+\d+[A-Z]?)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                let familyId = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                logTrace(.parsing, "Extracted family ID: '\(familyId)' from line: '\(line)'")
                return familyId
            }
        }
        
        return nil
    }
    
    // MARK: - Citation Generation
    
    /**
     * Generate citation for person with simple name disambiguation
     * Uses displayName (with patronymic) for parents vs name only for children
     */
    func generateCitation(for person: Person, in family: Family) -> String {
        logInfo(.citation, "📖 Generating citation for: \(person.displayName)")

        // Manual override first
        if let override = getManualCitation(for: person, in: family) {
            logDebug(.citation, "Using manual citation override")
            return override
        }

        // Check for enhanced citations from workflow
        if let workflow = familyNetworkWorkflow {
            let activeCitations = workflow.getActiveCitations()
            
            // Use displayName for parents (includes patronymic), name for children
            let citationKey = person.displayName
            
            if let enhancedCitation = activeCitations[citationKey] {
                logDebug(.citation, "🔍 RETRIEVED citation for '\(citationKey)': \(enhancedCitation.prefix(100))...")
                return enhancedCitation
            }
            
            // Also try with just the name as fallback
            if citationKey != person.name {
                if let enhancedCitation = activeCitations[person.name] {
                    logDebug(.citation, "🔍 RETRIEVED citation for '\(person.name)' (fallback): \(enhancedCitation.prefix(100))...")
                    return enhancedCitation
                }
            }
            
            // If no person-specific citation, try family-level citation
            if let familyCitation = activeCitations[family.familyId] {
                logDebug(.citation, "Using enhanced family citation from workflow for: \(family.familyId)")
                return familyCitation
            }
            
            logDebug(.citation, "No enhanced citation found in workflow, falling back to standard")
        } else {
            logDebug(.citation, "No workflow available, using standard citation generation")
        }

        // Fallback to standard citation generation
        let citation = CitationGenerator.generateMainFamilyCitation(family: family)
        logDebug(.citation, "Generated standard citation length: \(citation.count) characters")
        return citation
    }

    /**
     * Check if a name appears multiple times in a family
     * Used for citation disambiguation when the same name appears for multiple people
     */
    private func hasNameConflict(_ name: String, in family: Family) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Count occurrences of the name among all family members
        var nameCount = 0
        
        // Check parents
        for parent in family.allParents {
            if parent.name.trimmingCharacters(in: .whitespaces).lowercased() == cleanName {
                nameCount += 1
                if nameCount > 1 { return true }
            }
        }
        
        // Check children
        for child in family.children {
            if child.name.trimmingCharacters(in: .whitespaces).lowercased() == cleanName {
                nameCount += 1
                if nameCount > 1 { return true }
            }
        }
        
        return false
    }
    
    /**
     * Get the citation key for a person, handling name disambiguation
     * This is used to retrieve the correct citation when there are duplicate names
     */
    private func getCitationKey(for person: Person, in family: Family) -> String {
        // Check if there's a name conflict
        if hasNameConflict(person.name, in: family) {
            // Determine role
            let role: PersonRole = family.allParents.contains(where: {
                $0.name == person.name && $0.birthDate == person.birthDate
            }) ? .parent : .child
            
            // Use birth date for disambiguation if available
            if let birthDate = person.birthDate {
                return "\(person.name) (\(role.rawValue), b. \(birthDate))"
            } else {
                return "\(person.name) (\(role.rawValue))"
            }
        }
        
        return person.name
    }

     /**
     * Generate spouse citation (placeholder implementation)
     * This will be enhanced when cross-reference resolution is implemented
     */
    func generateSpouseCitation(spouseName: String, in family: Family) -> String {
        logInfo(.citation, "📖 Generating placeholder spouse citation for: \(spouseName)")
        
        let pages = family.pageReferences.joined(separator: ", ")
        var citation = "Spouse citation for \(spouseName) in family \(family.familyId)\n"
        citation += "Information from pages \(pages)\n\n"
        citation += "This feature is being developed. The citation will include:\n"
        citation += "- \(spouseName)'s parents' family information\n"
        citation += "- Birth date and location\n"
        citation += "- Parents' names and vital dates\n"
        citation += "- Cross-referenced family data\n\n"
        citation += "Cross-reference resolution coming in Phase 2."
        
        logDebug(.citation, "Generated placeholder spouse citation length: \(citation.count) characters")
        return citation
    }
    
    /**
     * Generate Hiski URL for person verification
     */
    @available(*, deprecated, message: "Use generateHiskiQuery(for:person,eventType:) instead")
    func generateHiskiQuery(for date: String, eventType: EventType) -> String {
        let cleanDate = date.replacingOccurrences(of: ".", with: "")
        return "https://hiski.genealogia.fi/hiski?en+query_\(eventType.rawValue)_\(cleanDate)"
    }

    func generateHiskiQuery(for person: Person, eventType: EventType) -> String? {
        logInfo(.citation, "🔗 Generating Hiski URL for person: \(person.displayName), event: \(eventType)")
        guard let query = HiskiQuery.from(person: person, eventType: eventType) else {
            logWarn(.citation, "No suitable data to build Hiski query for \(eventType)")
            return nil
        }
        let url = query.queryURL
        logDebug(.citation, "Generated Hiski URL: \(url)")
        return url
    }
    
    // MARK: - Debug and Testing
    
    /**
     * Load sample family for testing
     */
    @MainActor
    func loadSampleFamily() {
        logInfo(.app, "📋 Loading sample family")
        
        currentFamily = Family.sampleFamily()
        extractionProgress = .familyExtracted
        errorMessage = nil
        
        logDebug(.app, "Sample family loaded successfully")
    }
    
    /// Load complex sample family for cross-reference testing
    @MainActor
    func loadComplexSampleFamily() {
        logInfo(.app, "📋 Loading complex sample family")
        currentFamily = Family.complexSampleFamily()
        extractionProgress = .familyExtracted
        errorMessage = nil
        logDebug(.app, "Complex sample family loaded successfully")
    }

    /**
     * Resolve cross-references for the current family
     */
    @MainActor
    func resolveCrossReferences() async throws {
        guard let currentFamily = self.currentFamily else { return }
        let network = try await familyResolver.resolveCrossReferences(for: currentFamily)
        self.enhancedFamily = network.mainFamily
    }

    // MARK: - Manual Citation Persistence
    private func manualCitationKey(familyId: String, personId: String) -> String { "\(familyId)|\(personId)" }

    private func loadManualCitations() {
        if let data = UserDefaults.standard.data(forKey: "ManualCitations"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            manualCitations = dict
            logDebug(.citation, "Loaded \(manualCitations.count) manual citations")
        }
    }

    private func saveManualCitations() {
        if let data = try? JSONEncoder().encode(manualCitations) {
            UserDefaults.standard.set(data, forKey: "ManualCitations")
        }
    }

    func setManualCitation(_ citation: String, for person: Person, in family: Family) {
        let key = manualCitationKey(familyId: family.familyId, personId: person.id)
        manualCitations[key] = citation
        saveManualCitations()
        logInfo(.citation, "Saved manual citation for \(person.displayName) in \(family.familyId)")
    }

    func getManualCitation(for person: Person, in family: Family) -> String? {
        manualCitations[manualCitationKey(familyId: family.familyId, personId: person.id)]
    }
}

extension JuuretApp {
    
    /**
     * Debug method to check citation storage and retrieval
     */
    func debugCitationSystem(for person: Person, in family: Family) {
        logInfo(.citation, "=== CITATION DEBUG for \(person.displayName) ===")
        
        // Check workflow existence
        if let workflow = familyNetworkWorkflow {
            logInfo(.citation, "✅ Workflow exists")
            
            let citations = workflow.getActiveCitations()
            logInfo(.citation, "📄 Total citations stored: \(citations.count)")
            
            // Check different name formats
            let namesToCheck = [
                person.name,
                person.displayName,
                person.name.trimmingCharacters(in: .whitespaces),
                person.displayName.trimmingCharacters(in: .whitespaces)
            ]
            
            for nameKey in namesToCheck {
                if let citation = citations[nameKey] {
                    logInfo(.citation, "✅ Found with key '\(nameKey)': \(citation.prefix(100))...")
                } else {
                    logInfo(.citation, "❌ Not found with key '\(nameKey)'")
                }
            }
            
            // List all keys that contain this person's name
            let matchingKeys = citations.keys.filter { key in
                key.lowercased().contains(person.name.lowercased().split(separator: " ")[0])
            }
            logInfo(.citation, "🔍 Keys containing '\(person.name.split(separator: " ")[0])': \(matchingKeys)")
            
        } else {
            logInfo(.citation, "❌ No workflow available")
        }
        
        logInfo(.citation, "=== END CITATION DEBUG ===")
    }
    
    /**
     * Clear all cached data and force re-extraction
     */
    @MainActor
    func clearAllCitations() {
        currentFamily = nil
        enhancedFamily = nil
        familyNetworkWorkflow = nil
        extractionProgress = .idle
        errorMessage = nil
        logInfo(.app, "🧹 Cleared all citation data")
    }
    
    /**
     * Verify citation system integrity
     */
    func verifyCitationIntegrity() -> Bool {
        guard let family = currentFamily,
              let workflow = familyNetworkWorkflow else {
            logWarn(.citation, "⚠️ No family or workflow loaded")
            return false
        }
        
        let citations = workflow.getActiveCitations()
        var issues: [String] = []
        
        // Check all parents have citations
        for parent in family.allParents {
            let hasPersonalCitation = citations[parent.name] != nil ||
                                     citations[parent.displayName] != nil ||
                                     citations[parent.name.trimmingCharacters(in: .whitespaces)] != nil
            let hasFamilyCitation = citations[family.familyId] != nil
            
            if !hasPersonalCitation && !hasFamilyCitation {
                issues.append("Missing citation for parent: \(parent.displayName)")
            }
        }
        
        // Check all children have citations
        for child in family.children {
            let hasPersonalCitation = citations[child.name] != nil ||
                                     citations[child.displayName] != nil ||
                                     citations[child.name.trimmingCharacters(in: .whitespaces)] != nil
            let hasFamilyCitation = citations[family.familyId] != nil
            
            if !hasPersonalCitation && !hasFamilyCitation {
                issues.append("Missing citation for child: \(child.displayName)")
            }
        }
        
        if issues.isEmpty {
            logInfo(.citation, "✅ Citation integrity verified - all persons have citations")
            return true
        } else {
            logWarn(.citation, "⚠️ Citation integrity issues found:")
            for issue in issues {
                logWarn(.citation, "  - \(issue)")
            }
            return false
        }
    }
}

extension JuuretApp {
    
    /// Check for name conflicts in the current family
    func checkForNameConflicts() {
        guard let family = currentFamily else { return }
        
        logInfo(.citation, "=== CHECKING FOR NAME CONFLICTS ===")
        
        var nameCount: [String: Int] = [:]
        var nameOwners: [String: [String]] = [:]
        
        // Count parent names
        for parent in family.allParents {
            let simpleName = parent.name.trimmingCharacters(in: .whitespaces)
            nameCount[simpleName, default: 0] += 1
            nameOwners[simpleName, default: []].append("Parent: \(parent.displayName)")
        }
        
        // Count child names
        for child in family.children {
            let simpleName = child.name.trimmingCharacters(in: .whitespaces)
            nameCount[simpleName, default: 0] += 1
            nameOwners[simpleName, default: []].append("Child: \(child.displayName)")
        }
        
        // Report conflicts
        let conflicts = nameCount.filter { $0.value > 1 }
        
        if conflicts.isEmpty {
            logInfo(.citation, "✅ No name conflicts found")
        } else {
            logWarn(.citation, "⚠️ Found \(conflicts.count) name conflicts:")
            for (name, count) in conflicts {
                logWarn(.citation, "   '\(name)' appears \(count) times:")
                for owner in nameOwners[name] ?? [] {
                    logWarn(.citation, "      - \(owner)")
                }
            }
        }
        
        logInfo(.citation, "=== END NAME CONFLICT CHECK ===")
    }
}
