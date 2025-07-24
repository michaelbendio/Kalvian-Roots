//
//  NameEquivalenceManager.swift
//  Kalvian Roots
//
//  Dynamic name equivalence learning for Finnish genealogical names
//
//  Created by Michael Bendio on 7/23/25.
//

import Foundation

/**
 * NameEquivalenceManager.swift - Dynamic name equivalence learning
 *
 * Manages equivalences between Finnish names (e.g., Liisa = Elisabet, Johan = Juho)
 * with progressive learning that improves accuracy over time through user interaction.
 */

/**
 * Service for managing name equivalences in Finnish genealogical research
 *
 * Features:
 * - Dynamic learning through user interaction
 * - Bidirectional equivalence storage
 * - Persistent storage across app sessions
 * - Built-in common Finnish name variants
 */
@Observable
class NameEquivalenceManager {
    
    // MARK: - Properties
    
    /// User-learned equivalences (persistent across sessions)
    private var learnedEquivalences: [String: Set<String>] = [:]
    
    /// Built-in common Finnish name equivalences
    private let builtInEquivalences: [String: Set<String>] = [
        "liisa": ["elisabet", "lisa", "elisa"],
        "elisabet": ["liisa", "lisa", "elisa"],
        "johan": ["juho", "johannes", "juhana"],
        "juho": ["johan", "johannes", "juhana"],
        "johannes": ["johan", "juho", "juhana"],
        "maria": ["maija", "mari"],
        "maija": ["maria", "mari"],
        "erik": ["eero", "erkki"],
        "eero": ["erik", "erkki"],
        "erkki": ["erik", "eero"],
        "kristina": ["kirstin", "kirsti"],
        "kirsti": ["kristina", "kirstin"],
        "henrik": ["heikki", "henrikki"],
        "heikki": ["henrik", "henrikki"],
        "margareta": ["margeta", "marketta"],
        "margeta": ["margareta", "marketta"],
        "katharina": ["katariina", "kaarina"],
        "katariina": ["katharina", "kaarina"],
        "gertrud": ["kerttuli", "kerttu"],
        "kerttu": ["gertrud", "kerttuli"]
    ]
    
    /// Pending user confirmations (names waiting for user input)
    private var pendingConfirmations: Set<NamePair> = []
    
    /// Statistics for monitoring learning progress
    var learningStats = LearningStatistics()
    
    // MARK: - Initialization
    
    init() {
        loadLearnedEquivalences()
        print("📚 NameEquivalenceManager initialized")
        print("   Built-in equivalences: \(builtInEquivalences.count)")
        print("   Learned equivalences: \(learnedEquivalences.count)")
    }
    
    // MARK: - Core Equivalence Methods
    
    /**
     * Check if two names are equivalent
     *
     * Checks both built-in and learned equivalences
     */
    func areEquivalent(_ name1: String, _ name2: String) -> Bool {
        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)
        
        // Exact match
        if normalized1 == normalized2 {
            return true
        }
        
        // Check built-in equivalences
        if checkBuiltInEquivalence(normalized1, normalized2) {
            return true
        }
        
        // Check learned equivalences
        if checkLearnedEquivalence(normalized1, normalized2) {
            return true
        }
        
        return false
    }
    
    /**
     * Check equivalence with learning opportunity
     *
     * If names aren't known to be equivalent, may trigger user interaction
     */
    func areEquivalentWithLearning(_ name1: String, _ name2: String) async -> Bool {
        // First check existing equivalences
        if areEquivalent(name1, name2) {
            return true
        }
        
        // If not equivalent and names are similar, ask user
        if shouldAskUser(name1, name2) {
            return await askUserAboutEquivalence(name1, name2)
        }
        
        return false
    }
    
    /**
     * Get all known equivalents for a name
     */
    func getEquivalents(for name: String) -> Set<String> {
        let normalized = normalizeName(name)
        var equivalents: Set<String> = []
        
        // Add built-in equivalents
        if let builtIn = builtInEquivalences[normalized] {
            equivalents.formUnion(builtIn)
        }
        
        // Add learned equivalents
        if let learned = learnedEquivalences[normalized] {
            equivalents.formUnion(learned)
        }
        
        // Add the name itself
        equivalents.insert(normalized)
        
        return equivalents
    }
    
    // MARK: - Learning Methods
    
    /**
     * Learn a new equivalence from user input
     */
    func learnEquivalence(_ name1: String, _ name2: String) {
        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)
        
        // Add bidirectional equivalence
        addToLearnedEquivalences(normalized1, normalized2)
        addToLearnedEquivalences(normalized2, normalized1)
        
        // Save to persistent storage
        saveLearnedEquivalences()
        
        // Update statistics
        learningStats.recordLearning(normalized1, normalized2)
        
        print("📖 Learned equivalence: \(normalized1) ↔ \(normalized2)")
    }
    
    /**
     * Mark two names as NOT equivalent
     */
    func markAsNotEquivalent(_ name1: String, _ name2: String) {
        let pair = NamePair(name1: normalizeName(name1), name2: normalizeName(name2))
        pendingConfirmations.remove(pair)
        
        // Could add to a "negative equivalences" set if needed
        learningStats.recordNonEquivalence(pair.name1, pair.name2)
        
        print("❌ Marked as not equivalent: \(pair.name1) ↔ \(pair.name2)")
    }
    
    /**
     * Ask user about potential name equivalence (async for UI integration)
     */
    private func askUserAboutEquivalence(_ name1: String, _ name2: String) async -> Bool {
        let pair = NamePair(name1: normalizeName(name1), name2: normalizeName(name2))
        
        // Check if we're already pending on this pair
        if pendingConfirmations.contains(pair) {
            return false
        }
        
        pendingConfirmations.insert(pair)
        
        // This would integrate with UI - for now, simulate user response
        let userResponse = await simulateUserResponse(pair)
        
        pendingConfirmations.remove(pair)
        
        if userResponse {
            learnEquivalence(name1, name2)
            return true
        } else {
            markAsNotEquivalent(name1, name2)
            return false
        }
    }
    
    /**
     * Simulate user response for testing (replace with real UI)
     */
    private func simulateUserResponse(_ pair: NamePair) async -> Bool {
        // Simulate thinking time
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // For testing, use some heuristics to simulate reasonable responses
        let similarity = calculateSimilarity(pair.name1, pair.name2)
        
        // If names are very similar, more likely to be equivalent
        if similarity > 0.7 {
            print("🤖 Simulated user: YES - \(pair.name1) and \(pair.name2) are equivalent")
            return true
        } else {
            print("🤖 Simulated user: NO - \(pair.name1) and \(pair.name2) are not equivalent")
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    private func normalizeName(_ name: String) -> String {
        return name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "å", with: "a")
    }
    
    private func checkBuiltInEquivalence(_ name1: String, _ name2: String) -> Bool {
        if let equivalents = builtInEquivalences[name1] {
            return equivalents.contains(name2)
        }
        return false
    }
    
    private func checkLearnedEquivalence(_ name1: String, _ name2: String) -> Bool {
        if let equivalents = learnedEquivalences[name1] {
            return equivalents.contains(name2)
        }
        return false
    }
    
    private func shouldAskUser(_ name1: String, _ name2: String) -> Bool {
        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)
        
        // Don't ask if names are too different
        let similarity = calculateSimilarity(normalized1, normalized2)
        if similarity < 0.3 {
            return false
        }
        
        // Don't ask if we've already asked about this pair
        let pair = NamePair(name1: normalized1, name2: normalized2)
        if pendingConfirmations.contains(pair) {
            return false
        }
        
        // Don't ask too frequently (rate limiting)
        if learningStats.recentInteractions > 5 {
            return false
        }
        
        return true
    }
    
    private func calculateSimilarity(_ name1: String, _ name2: String) -> Double {
        // Simple similarity based on common characters and length
        let set1 = Set(name1)
        let set2 = Set(name2)
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        
        guard !union.isEmpty else { return 0.0 }
        
        let jaccardSimilarity = Double(intersection.count) / Double(union.count)
        
        // Bonus for similar length
        let lengthDifference = abs(name1.count - name2.count)
        let lengthSimilarity = 1.0 - (Double(lengthDifference) / Double(max(name1.count, name2.count)))
        
        return (jaccardSimilarity + lengthSimilarity) / 2.0
    }
    
    private func addToLearnedEquivalences(_ name1: String, _ name2: String) {
        if learnedEquivalences[name1] == nil {
            learnedEquivalences[name1] = Set<String>()
        }
        learnedEquivalences[name1]?.insert(name2)
    }
    
    // MARK: - Persistence
    
    private func saveLearnedEquivalences() {
        do {
            let data = try JSONEncoder().encode(learnedEquivalences)
            UserDefaults.standard.set(data, forKey: "LearnedNameEquivalences")
            print("💾 Saved learned equivalences to UserDefaults")
        } catch {
            print("❌ Failed to save learned equivalences: \(error)")
        }
    }
    
    private func loadLearnedEquivalences() {
        guard let data = UserDefaults.standard.data(forKey: "LearnedNameEquivalences") else {
            print("📂 No saved equivalences found")
            return
        }
        
        do {
            learnedEquivalences = try JSONDecoder().decode([String: Set<String>].self, from: data)
            print("📂 Loaded \(learnedEquivalences.count) learned equivalences")
        } catch {
            print("❌ Failed to load learned equivalences: \(error)")
            learnedEquivalences = [:]
        }
    }
    
    // MARK: - Batch Operations
    
    /**
     * Import equivalences from external source
     */
    func importEquivalences(_ equivalences: [String: [String]]) {
        for (name, variants) in equivalences {
            let normalized = normalizeName(name)
            let normalizedVariants = variants.map { normalizeName($0) }
            
            for variant in normalizedVariants {
                addToLearnedEquivalences(normalized, variant)
                addToLearnedEquivalences(variant, normalized)
            }
        }
        
        saveLearnedEquivalences()
        print("📥 Imported \(equivalences.count) equivalence groups")
    }
    
    /**
     * Export learned equivalences
     */
    func exportEquivalences() -> [String: [String]] {
        var exported: [String: [String]] = [:]
        
        for (name, equivalents) in learnedEquivalences {
            exported[name] = Array(equivalents)
        }
        
        return exported
    }
    
    /**
     * Clear all learned equivalences (keep built-ins)
     */
    func clearLearnedEquivalences() {
        learnedEquivalences.removeAll()
        saveLearnedEquivalences()
        learningStats = LearningStatistics()
        print("🗑️ Cleared all learned equivalences")
    }
    
    // MARK: - Statistics and Monitoring
    
    func getLearningStatistics() -> LearningStatistics {
        return learningStats
    }
    
    func getEquivalenceReport() -> EquivalenceReport {
        let totalBuiltIn = builtInEquivalences.values.reduce(0) { $0 + $1.count }
        let totalLearned = learnedEquivalences.values.reduce(0) { $0 + $1.count }
        
        return EquivalenceReport(
            builtInCount: builtInEquivalences.count,
            builtInEquivalences: totalBuiltIn,
            learnedCount: learnedEquivalences.count,
            learnedEquivalences: totalLearned,
            pendingConfirmations: pendingConfirmations.count,
            learningStats: learningStats
        )
    }
}

// MARK: - Supporting Data Structures

/**
 * Name pair for tracking equivalence relationships
 */
struct NamePair: Hashable, Codable {
    let name1: String
    let name2: String
    
    init(name1: String, name2: String) {
        // Ensure consistent ordering for comparison
        if name1 <= name2 {
            self.name1 = name1
            self.name2 = name2
        } else {
            self.name1 = name2
            self.name2 = name1
        }
    }
}

/**
 * Learning statistics for monitoring progress
 */
struct LearningStatistics {
    var totalLearned: Int = 0
    var totalRejected: Int = 0
    var recentInteractions: Int = 0
    var lastInteractionDate: Date?
    
    mutating func recordLearning(_ name1: String, _ name2: String) {
        totalLearned += 1
        recentInteractions += 1
        lastInteractionDate = Date()
    }
    
    mutating func recordNonEquivalence(_ name1: String, _ name2: String) {
        totalRejected += 1
        recentInteractions += 1
        lastInteractionDate = Date()
    }
    
    var totalInteractions: Int {
        return totalLearned + totalRejected
    }
    
    var learningRate: Double {
        guard totalInteractions > 0 else { return 0.0 }
        return Double(totalLearned) / Double(totalInteractions)
    }
}

/**
 * Report on current equivalence state
 */
struct EquivalenceReport {
    let builtInCount: Int
    let builtInEquivalences: Int
    let learnedCount: Int
    let learnedEquivalences: Int
    let pendingConfirmations: Int
    let learningStats: LearningStatistics
    
    var totalEquivalences: Int {
        return builtInEquivalences + learnedEquivalences
    }
}

// MARK: - Extensions for Codable Support

extension Set: Codable where Element: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Array(self))
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let array = try container.decode([Element].self)
        self = Set(array)
    }
}
