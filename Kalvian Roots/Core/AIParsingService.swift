//
//  AIParsingService.swift - UPDATED with MLX Integration
//  Kalvian Roots
//
//  Enhanced AI service with platform-aware MLX support and improved fonts
//

import Foundation

/**
 * AIParsingService.swift - Enhanced with MLX support
 *
 * Provides platform-aware AI service selection:
 * - macOS Apple Silicon: MLX models + cloud backup
 * - macOS Intel: Cloud services only
 * - iOS: DeepSeek only (simplified)
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
    
    // MARK: - Platform-Aware Initialization
    
    init() {
        logInfo(.ai, "🚀 AIParsingService initialization started (Enhanced with MLX)")
        
        // Get platform-appropriate services
        self.availableServices = PlatformAwareServiceManager.getRecommendedServices()
        self.currentAIService = PlatformAwareServiceManager.getDefaultService()
        
        logInfo(.ai, "✅ AIParsingService initialized with platform awareness")
        logDebug(.ai, "Available services: \(availableServiceNames.joined(separator: ", "))")
        logInfo(.ai, "Default service: \(currentServiceName)")
        
        // Log platform-specific information
        #if os(macOS)
        if MLXService.isAvailable() {
            logInfo(.ai, "🖥️ macOS Apple Silicon detected - MLX services available")
            
            // Check if MLX server is running
            Task {
                if let status = await MLXService.getServerStatus() {
                    logInfo(.ai, "✅ MLX server detected with \(status.loaded_models.count) loaded models")
                } else {
                    logWarn(.ai, "⚠️ MLX server not running - start with: ~/.kalvian_roots_mlx/scripts/start_server.sh")
                }
            }
        } else {
            logInfo(.ai, "🖥️ macOS Intel detected - using cloud services")
        }
        #elseif os(iOS)
        logInfo(.ai, "📱 iOS detected - using DeepSeek only")
        #else
        logInfo(.ai, "🌐 Other platform - using cloud services")
        #endif
        
        // Try to auto-configure from saved settings
        autoConfigureServices()
    }
    
    // MARK: - Service Management (Enhanced)
    
    /**
     * Switch to a different AI service by name
     */
    func switchToService(named serviceName: String) throws {
        logInfo(.ai, "🔄 Switching AI service to: \(serviceName)")
        
        guard let service = availableServices.first(where: { $0.name == serviceName }) else {
            logError(.ai, "❌ Service '\(serviceName)' not found in available services")
            throw AIServiceError.notConfigured("Service '\(serviceName)' not found")
        }
        
        currentAIService = service
        logInfo(.ai, "✅ Successfully switched to: \(serviceName)")
        logDebug(.ai, "New service configured: \(service.isConfigured)")
        
        // If switching to MLX service, check server status
        if serviceName.contains("MLX") {
            Task {
                await checkMLXServerStatus()
            }
        }
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
    func getServiceStatus() -> [(name: String, configured: Bool, type: String)] {
        let status = availableServices.map { service in
            let type: String
            if service.name.contains("MLX") {
                type = "Local MLX"
            } else if service.name.contains("Mock") {
                type = "Test"
            } else {
                type = "Cloud API"
            }
            
            return (name: service.name, configured: service.isConfigured, type: type)
        }
        
        logTrace(.ai, "Service status requested: \(status.map { "\($0.name)=\($0.configured)" }.joined(separator: ", "))")
        return status
    }
    
    // MARK: - MLX-Specific Methods
    
    /**
     * Check MLX server status and log findings
     */
    private func checkMLXServerStatus() async {
        #if os(macOS)
        if MLXService.isAvailable() {
            if let status = await MLXService.getServerStatus() {
                logInfo(.ai, "✅ MLX server running with \(status.loaded_models.count) loaded models")
                logDebug(.ai, "Available MLX models: \(status.available_models.keys.joined(separator: ", "))")
            } else {
                logWarn(.ai, "⚠️ MLX server not responding")
                logInfo(.ai, "💡 Start MLX server with: ~/.kalvian_roots_mlx/scripts/start_server.sh")
            }
        }
        #endif
    }
    
    /**
     * Preload MLX model for faster responses
     */
    func preloadMLXModel() async throws {
        guard currentAIService is MLXService else {
            logWarn(.ai, "Current service is not MLX - cannot preload")
            return
        }
        
        if let mlxService = currentAIService as? MLXService {
            logInfo(.ai, "🔄 Preloading MLX model: \(mlxService.name)")
            try await mlxService.preloadModel()
            logInfo(.ai, "✅ MLX model preloaded successfully")
        }
    }
    
    /**
     * Get recommended model based on family complexity
     */
    func getRecommendedMLXModel(for family: Family) -> String? {
        #if os(macOS)
        guard MLXService.isAvailable() else { return nil }
        
        let complexity = calculateFamilyComplexity(family)
        
        switch complexity {
        case .simple:
            return "Mistral-7B (Local MLX)"
        case .standard:
            return "Llama3.2-8B (Local MLX)"
        case .complex:
            return "Qwen3-30B (Local MLX)"
        }
        #else
        return nil
        #endif
    }
    
    private func calculateFamilyComplexity(_ family: Family) -> FamilyComplexity {
        let childCount = family.children.count
        let spouseCount = family.additionalSpouses.count
        let crossRefCount = family.totalCrossReferencesNeeded
        
        let totalComplexity = childCount + (spouseCount * 2) + (crossRefCount * 3)
        
        if totalComplexity <= 10 {
            return .simple
        } else if totalComplexity <= 25 {
            return .standard
        } else {
            return .complex
        }
    }
    
    private enum FamilyComplexity {
        case simple, standard, complex
    }
    
    // MARK: - Family Parsing (Enhanced with Model Selection)
    
    /**
     * Parse a family with automatic model selection based on complexity
     */
    func parseFamilyWithOptimalModel(familyId: String, familyText: String) async throws -> Family {
        logInfo(.parsing, "🎯 Starting optimal family parsing for: \(familyId)")
        
        // First do a quick parse to assess complexity
        let quickFamily = try await parseFamily(familyId: familyId, familyText: familyText)
        
        #if os(macOS)
        // On macOS with MLX, switch to optimal model if needed
        if MLXService.isAvailable(),
           let recommendedModel = getRecommendedMLXModel(for: quickFamily),
           recommendedModel != currentServiceName {
            
            logInfo(.ai, "🔄 Switching to optimal model: \(recommendedModel)")
            try switchToService(named: recommendedModel)
            
            // Re-parse with optimal model
            return try await parseFamily(familyId: familyId, familyText: familyText)
        }
        #endif
        
        return quickFamily
    }
    
    // MARK: - Original parseFamily method (unchanged)
    
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
    
    // MARK: - Configuration Persistence (Enhanced)
    
    private func autoConfigureServices() {
        logDebug(.ai, "🔧 Auto-configuring services from saved settings")
        
        // Try to load saved API keys
        for service in availableServices {
            // Skip MLX services - they don't need API keys
            if service.name.contains("MLX") {
                logTrace(.ai, "Skipping MLX service configuration: \(service.name)")
                continue
            }
            
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
    
    // MARK: - All existing parsing methods remain unchanged...
    // (parseStructString, cleanStructString, evaluateStructString, etc.)
    
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
    
    // [All other existing methods remain the same - cleanStructString, evaluateStructString, etc.]
    
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
    
    private func evaluateStructString(_ structString: String) throws -> Family {
        logDebug(.parsing, "📝 Evaluating struct string with StructParser")
        
        let parser = StructParser(structString)
        let family = try parser.parseFamily()
        
        logDebug(.parsing, "✅ StructParser completed successfully")
        return family
    }
    
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
    
    // [All other helper methods remain unchanged]
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
}
