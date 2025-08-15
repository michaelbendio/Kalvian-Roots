//
//  FamilyResolver.swift
//  Kalvian Roots
//
//  Complete fixed file - all compilation errors resolved
//

import Foundation

/**
 * FamilyResolver.swift - Cross-reference resolution and family network building
 *
 * Resolves family cross-references using two methods:
 * 1. Family reference resolution ({KORPI 5} notation)
 * 2. Birth date search with multi-factor validation
 *
 * Builds complete family networks with confidence scoring and user validation.
 */

@Observable
class FamilyResolver {
    
    // MARK: - Dependencies
    
    private let aiParsingService: AIParsingService
    private let nameEquivalenceManager: NameEquivalenceManager
    
    // MARK: - State Properties
    
    private var fileContent: String?
    private var resolutionStatistics = ResolutionStatistics()
    
    // MARK: - Computed Properties
    
    var hasFileContent: Bool {
        fileContent != nil && !(fileContent?.isEmpty ?? true)
    }
    
    // MARK: - Initialization
    
    init(aiParsingService: AIParsingService, nameEquivalenceManager: NameEquivalenceManager) {
        logInfo(.resolver, "🔗 FamilyResolver initialization started")
        
        self.aiParsingService = aiParsingService
        self.nameEquivalenceManager = nameEquivalenceManager
        
        logInfo(.resolver, "✅ FamilyResolver initialized")
        logDebug(.resolver, "AI Service: \(aiParsingService.currentServiceName)")
        logDebug(.resolver, "Name Equivalence Manager ready")
    }
    
    // MARK: - File Content Management
    
    /**
     * Set the file content for cross-reference search operations
     */
    func setFileContent(_ content: String) {
        logInfo(.resolver, "📁 Setting file content for cross-reference resolution")
        logDebug(.resolver, "File content length: \(content.count) characters")
        
        self.fileContent = content
        
        // Pre-process content for efficient searching
        preprocessFileContent()
        
        logInfo(.resolver, "✅ File content set and preprocessed")
    }
    
    private func preprocessFileContent() {
        // Future optimization: Create family ID index, birth date index, etc.
        logTrace(.resolver, "File content preprocessing completed")
    }
    
    // MARK: - Main Cross-Reference Resolution Method
    
    /**
     * Resolve all cross-references for a family and build complete family network
     */
    func resolveCrossReferences(for family: Family) async throws -> FamilyNetwork {
        logInfo(.resolver, "🔗 Starting cross-reference resolution for family: \(family.familyId)")
        DebugLogger.shared.startTimer("family_network_resolution")
        
        guard hasFileContent else {
            logError(.resolver, "❌ No file content available for cross-reference resolution")
            throw FamilyResolverError.noFileContent
        }
        
        resolutionStatistics.incrementAttempt()
        
        var network = FamilyNetwork(mainFamily: family)
        
        do {
            // Step 1: Resolve as-child families (parents' families)
            logInfo(.resolver, "Step 1: Resolving as-child families")
            network = try await resolveAsChildFamilies(for: family, network: network)
            
            // Step 2: Resolve as-parent families (children's families)
            logInfo(.resolver, "Step 2: Resolving as-parent families")
            network = try await resolveAsParentFamilies(for: family, network: network)
            
            // Step 3: Resolve spouse as-child families
            logInfo(.resolver, "Step 3: Resolving spouse as-child families")
            network = try await resolveSpouseAsChildFamilies(for: family, network: network)

            resolutionStatistics.incrementSuccess()
            
            let duration = DebugLogger.shared.endTimer("family_network_resolution")
            logInfo(.resolver, "✅ Cross-reference resolution completed in \(String(format: "%.2f", duration))s")
            logDebug(.resolver, "Network summary: \(network.totalResolvedFamilies) families resolved")
            
            return network
            
        } catch {
            resolutionStatistics.incrementFailure()
            DebugLogger.shared.endTimer("family_network_resolution")
            
            logError(.resolver, "❌ Cross-reference resolution failed: \(error)")
            throw error
        }
    }
    
    // MARK: - As-Child Family Resolution (Fixed)
    
    private func resolveAsChildFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        logDebug(.resolver, "🔍 Resolving as-child families for parents")
        
        var updatedNetwork = network
        
        // Resolve father's as-child family
        if let fatherFamily = try await findAsChildFamily(for: family.father) {
            logInfo(.resolver, "✅ Found father's as-child family: \(fatherFamily.familyId)")
            updatedNetwork.asChildFamilies[family.father.name] = fatherFamily
        } else {
            logWarn(.resolver, "⚠️ Could not resolve father's as-child family")
        }
        
        // Resolve mother's as-child family
        if let mother = family.mother,
           let motherFamily = try await findAsChildFamily(for: mother) {
            logInfo(.resolver, "✅ Found mother's as-child family: \(motherFamily.familyId)")
            updatedNetwork.asChildFamilies[mother.name] = motherFamily
        } else if family.mother != nil {
            logWarn(.resolver, "⚠️ Could not resolve mother's as-child family")
        }
        
        // Resolve additional spouses' as-child families
        for spouse in family.additionalSpouses {
            if let spouseFamily = try await findAsChildFamily(for: spouse) {
                logInfo(.resolver, "✅ Found additional spouse's as-child family: \(spouseFamily.familyId)")
                updatedNetwork.asChildFamilies[spouse.name] = spouseFamily
            } else {
                logWarn(.resolver, "⚠️ Could not resolve additional spouse's as-child family")
            }
        }
        
        return updatedNetwork
    }
    
    // MARK: - As-Parent Family Resolution (Fixed)
    
    private func resolveAsParentFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        logDebug(.resolver, "🔍 Resolving as-parent families for children")
        
        var updatedNetwork = network
        
        for child in family.children {
            if let childFamily = try await findAsParentFamily(for: child) {
                logInfo(.resolver, "✅ Found child's as-parent family: \(childFamily.familyId)")
                updatedNetwork.asParentFamilies[child.name] = childFamily
            } else {
                logWarn(.resolver, "⚠️ Could not resolve child's as-parent family")
            }
        }
        
        return updatedNetwork
    }
    
    // MARK: - Spouse As-Child Family Resolution (Fixed)
    
    private func resolveSpouseAsChildFamilies(for family: Family, network: FamilyNetwork) async throws -> FamilyNetwork {
        logDebug(.resolver, "🔍 Resolving spouse as-child families")
        
        var updatedNetwork = network
        
        for child in family.children {
            if let spouse = child.spouse,
               let spouseFamily = try await findSpouseAsChildFamily(spouseName: spouse) {
                logInfo(.resolver, "✅ Found spouse's as-child family: \(spouseFamily.familyId)")
                updatedNetwork.spouseAsChildFamilies[spouse] = spouseFamily
            }
        }
        
        return updatedNetwork
    }
    
    // MARK: - Individual Family Finding Methods
    
    private func findAsChildFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-child family for: \(person.displayName)")
        
        // Method 1: Try family reference resolution first
        if let asChildRef = person.asChildReference {
            logDebug(.resolver, "Found as-child reference: \(asChildRef)")
            return try await resolveFamilyByReference(asChildRef)
        }
        
        // Method 2: Try birth date search
        if let birthDate = person.birthDate {
            logDebug(.resolver, "Trying birth date search for: \(birthDate)")
            if let family = try await findFamilyByBirthDate(person: person) { return family }
        }
        
        logWarn(.resolver, "⚠️ No resolution method available for: \(person.displayName)")
        return nil
    }
    
    private func findAsParentFamily(for person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding as-parent family for: \(person.displayName)")
        
        // Method 1: Try family reference resolution first
        if let asParentRef = person.asParentReference {
            logDebug(.resolver, "Found as-parent reference: \(asParentRef)")
            return try await resolveFamilyByReference(asParentRef)
        }
        
        // Method 2: Try spouse-based search
        if let spouse = person.spouse {
            logDebug(.resolver, "Trying spouse-based search for: \(spouse)")
            if let family = try await findFamilyBySpouse(person: person) { return family }
        }
        
        logWarn(.resolver, "⚠️ No resolution method available for: \(person.displayName)")
        return nil
    }
    
    private func findSpouseAsChildFamily(spouseName: String) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding spouse's as-child family for: \(spouseName)")
        
        // This would involve searching for the spouse as a child in some family
        // Implementation depends on the specific text format
        
        logWarn(.resolver, "⚠️ Spouse as-child family resolution not yet implemented")
        return nil
    }
    
    // MARK: - Resolution Methods
    
    private func resolveFamilyByReference(_ familyId: String) async throws -> Family? {
        logDebug(.resolver, "🔍 Resolving family by reference: \(familyId)")
        
        guard let fileContent = fileContent else {
            throw FamilyResolverError.noFileContent
        }
        
        // Extract family text for the referenced family ID
        let normalizedId = familyId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let familyText = extractFamilyText(familyId: normalizedId, from: fileContent) {
            logDebug(.resolver, "Found family text for: \(normalizedId)")
            
            do {
                let family = try await aiParsingService.parseFamily(familyId: normalizedId, familyText: familyText)
                logInfo(.resolver, "✅ Successfully resolved family: \(normalizedId)")
                return family
            } catch {
                logError(.resolver, "❌ Failed to parse referenced family \(normalizedId): \(error)")
                throw FamilyResolverError.crossReferenceFailed("Failed to parse family \(normalizedId)")
            }
        } else {
            logWarn(.resolver, "⚠️ Family text not found for: \(normalizedId)")
            return nil
        }
    }
    
    private func findFamilyByBirthDate(person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding family by birth date for: \(person.displayName)")
        
        guard let birthDate = person.birthDate,
              let fileContent = fileContent else {
            return nil
        }
        
        // Search for birth date in file content
        let candidates = await searchForBirthDate(birthDate, in: fileContent)
        
        if candidates.isEmpty {
            logWarn(.resolver, "⚠️ No families found with birth date: \(birthDate)")
            return nil
        }
        
        // Score candidates and pick best match
        let scoredCandidates = scoreCandidates(candidates, for: person)
        
        if let bestCandidate = scoredCandidates.first {
            logInfo(.resolver, "✅ Found best candidate family: \(bestCandidate.family.familyId) (confidence: \(bestCandidate.confidence))")
            return bestCandidate.family
        }
        
        return nil
    }
    
    private func findFamilyBySpouse(person: Person) async throws -> Family? {
        logDebug(.resolver, "🔍 Finding family by spouse for: \(person.displayName)")
        
        // Implementation would search for families where person appears as parent with their spouse
        logWarn(.resolver, "⚠️ Spouse-based family resolution not yet implemented")
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func extractFamilyText(familyId: String, from content: String) -> String? {
        // This should use the same family extraction logic as in FileManager
        // For now, return a simplified implementation
        
        let lines = content.components(separatedBy: .newlines)
        var familyLines: [String] = []
        var inFamily = false
        var foundFamily = false
        
        for line in lines {
            if line.uppercased().contains(familyId.uppercased()) {
                inFamily = true
                foundFamily = true
                familyLines.append(line)
            } else if inFamily {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && foundFamily {
                    // End of family section
                    break
                } else {
                    familyLines.append(line)
                }
            }
        }
        
        return foundFamily ? familyLines.joined(separator: "\n") : nil
    }
    
    private func searchForBirthDate(_ birthDate: String, in content: String) async -> [Family] {
        logDebug(.resolver, "Searching for birth date: \(birthDate)")
        var families: [Family] = []
        // Grep-like scan: collect family blocks that contain the birthDate string
        let lines = content.components(separatedBy: .newlines)
        var buffer: [String] = []
        var inFamily = false
        var currentHeader: String?

        func flushIfContainsDate() async {
            guard let header = currentHeader else { return }
            let block = buffer.joined(separator: "\n")
            if block.contains(birthDate) {
                // Extract ID from header, reuse main parser to build Family
                if let id = extractFamilyIdFromHeader(header), let text = extractFamilyText(familyId: id, from: content) {
                    if let fam = try? await awaitParse(familyId: id, text: text) { families.append(fam) }
                }
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let headerId = extractFamilyIdFromHeader(trimmed) {
                if inFamily { await flushIfContainsDate() }
                inFamily = true
                currentHeader = trimmed
                buffer = [line]
            } else if inFamily {
                buffer.append(line)
                if trimmed.isEmpty { // family delimiter heuristic
                    await flushIfContainsDate()
                    inFamily = false
                    buffer.removeAll()
                    currentHeader = nil
                }
            }
        }
        if inFamily { await flushIfContainsDate() }
        return families
    }

    private func awaitParse(familyId: String, text: String) async -> Family? {
        do { return try await aiParsingService.parseFamily(familyId: familyId, familyText: text) }
        catch { return nil }
    }

    private func extractFamilyIdFromHeader(_ line: String) -> String? {
        let pattern = #"^([A-ZÄÖÅ-]+(?:\s+[IVX]+)?\s+\d+[A-Z]?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        let matchRange = Range(match.range(at: 1), in: line)!
        return String(line[matchRange])
    }
    
    private func scoreCandidates(_ candidates: [Family], for person: Person) -> [FamilyMatch] {
        // Score on: birth date match, name or name-equivalence, spouse (or variant), marriage year (last two digits)
        func lastTwo(_ year: String?) -> String? {
            guard let y = year?.trimmingCharacters(in: .whitespaces), y.count >= 2 else { return nil }
            return String(y.suffix(2))
        }

        let personYear2 = lastTwo(person.bestMarriageDate)
        let equivalents = nameEquivalenceManager.getEquivalentNames(for: person.name)

        let scored = candidates.map { family -> FamilyMatch in
            var score: Double = 0
            var reasons: [String] = []

            // Check birth date in any person line
            if family.allPersons.contains(where: { $0.birthDate == person.birthDate }) {
                score += 0.4; reasons.append("birth date match")
            }

            // Name similarity in parents/children
            if family.allPersons.contains(where: { p in
                p.name.caseInsensitiveCompare(person.name) == .orderedSame || equivalents.contains(p.name.lowercased())
            }) {
                score += 0.25; reasons.append("name or variant match")
            }

            // Spouse name or variant
            if let spouse = person.spouse, !spouse.isEmpty {
                let spouseEq = nameEquivalenceManager.getEquivalentNames(for: spouse)
                if family.allPersons.contains(where: { p in
                    p.name.caseInsensitiveCompare(spouse) == .orderedSame || spouseEq.contains(p.name.lowercased())
                }) {
                    score += 0.2; reasons.append("spouse or variant match")
                }
            }

            // Marriage year (last two digits) heuristic
            if let y2 = personYear2 {
                if family.allPersons.contains(where: { p in (p.bestMarriageDate?.hasSuffix(y2) ?? false) }) {
                    score += 0.15; reasons.append("marriage year match (yy)")
                }
            }

            return FamilyMatch(family: family, confidence: min(score, 1.0), reasons: reasons, warnings: [])
        }

        return scored.sorted { $0.confidence > $1.confidence }
    }
    
    // MARK: - Date Utilities (Fixed)
    
    private func extractYearFromDate(_ date: String) -> Int? {
        let components = date.components(separatedBy: ".")
        if components.count >= 3, let _ = Int(components[2]) {
            // Fixed: Use _ instead of unused year variable
            return Int(components[2])
        }
        return nil
    }
}

// MARK: - Supporting Data Structures

/**
 * Complete family network with all cross-references resolved
 */
struct FamilyNetwork {
    let mainFamily: Family
    var asChildFamilies: [String: Family] = [:]      // Parent families
    var asParentFamilies: [String: Family] = [:]     // Children's families
    var spouseAsChildFamilies: [String: Family] = [:] // Spouse parent families
    
    init(mainFamily: Family) {
        self.mainFamily = mainFamily
    }
    
    var totalResolvedFamilies: Int {
        return asChildFamilies.count + asParentFamilies.count + spouseAsChildFamilies.count
    }
    
    func getAsChildFamily(for person: Person) -> Family? {
        return asChildFamilies[person.name]
    }
    
    func getAsParentFamily(for person: Person) -> Family? {
        return asParentFamilies[person.name]
    }
    
    func getSpouseAsChildFamily(for familyId: String) -> Family? {
        return spouseAsChildFamilies[familyId]
    }
}

/**
 * Family match with confidence scoring
 */
struct FamilyMatch {
    let family: Family
    let confidence: Double      // 0.0 to 1.0
    let reasons: [String]       // Match justifications
    let warnings: [String]      // Potential issues
}

/**
 * Resolution statistics for debugging and optimization
 */
struct ResolutionStatistics {
    private var attempts: Int = 0
    private var successes: Int = 0
    private var failures: Int = 0
    
    mutating func incrementAttempt() { attempts += 1 }
    mutating func incrementSuccess() { successes += 1 }
    mutating func incrementFailure() { failures += 1 }
    
    var successRate: Double {
        guard attempts > 0 else { return 0.0 }
        return Double(successes) / Double(attempts)
    }
}

/**
 * Family resolver specific errors
 */
enum FamilyResolverError: LocalizedError {
    case noFileContent
    case crossReferenceFailed(String)
    case ambiguousMatch([Family])
    case noMatchFound(String)
    
    var errorDescription: String? {
        switch self {
        case .noFileContent:
            return "No file content available for cross-reference resolution"
        case .crossReferenceFailed(let details):
            return "Cross-reference resolution failed: \(details)"
        case .ambiguousMatch(let families):
            return "Ambiguous match found: \(families.count) possible families"
        case .noMatchFound(let identifier):
            return "No match found for: \(identifier)"
        }
    }
}

