//
//  NameEquivalenceManager.swift
//  Kalvian Roots
//
//  Complete file for name equivalence learning and management
//

import Foundation

/**
 * NameEquivalenceManager - Learns and manages Finnish name equivalences
 *
 * Handles bidirectional name equivalences for genealogical cross-reference resolution.
 * Examples: Liisa ↔ Elisabet, Johan ↔ Juho, Matti ↔ Matias
 */

@Observable
class NameEquivalenceManager {
    
    // MARK: - Properties
    
    private var equivalences: [String: Set<String>] = [:]
    private let userDefaultsKey = "NameEquivalences"
    
    // MARK: - Computed Properties
    
    var totalEquivalences: Int {
        return equivalences.values.reduce(0) { $0 + $1.count }
    }
    
    var equivalenceGroups: [[String]] {
        var processed: Set<String> = []
        var groups: [[String]] = []
        
        for (name, equivalentNames) in equivalences {
            if !processed.contains(name) {
                let group = [name] + Array(equivalentNames)
                groups.append(group.sorted())
                
                // Mark all names in this group as processed
                processed.insert(name)
                for equivalent in equivalentNames {
                    processed.insert(equivalent)
                }
            }
        }
        
        return groups.sorted { $0.first ?? "" < $1.first ?? "" }
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.nameEquivalence, "🔤 NameEquivalenceManager initialization started")
        
        loadEquivalences()
        
        logInfo(.nameEquivalence, "✅ NameEquivalenceManager initialized")
        logDebug(.nameEquivalence, "Loaded \(totalEquivalences) name equivalences")
    }
    
    // MARK: - Core Equivalence Methods
    
    /**
     * Check if two names are equivalent
     */
    func areNamesEquivalent(_ name1: String, _ name2: String) -> Bool {
        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)
        
        // Same name is always equivalent
        if normalized1 == normalized2 {
            return true
        }
        
        // Check stored equivalences
        if let equivalents = equivalences[normalized1] {
            return equivalents.contains(normalized2)
        }
        
        return false
    }
    
    /**
     * Get all equivalent names for a given name
     */
    func getEquivalentNames(for name: String) -> Set<String> {
        let normalized = normalizeName(name)
        
        var allEquivalents: Set<String> = [normalized]
        
        if let directEquivalents = equivalences[normalized] {
            allEquivalents.formUnion(directEquivalents)
            
            // Also get equivalents of equivalents (transitive closure)
            for equivalent in directEquivalents {
                if let indirectEquivalents = equivalences[equivalent] {
                    allEquivalents.formUnion(indirectEquivalents)
                }
            }
        }
        
        return allEquivalents
    }
    
    /**
     * Add name equivalence (bidirectional)
     */
    func addEquivalence(between name1: String, and name2: String) {
        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)
        
        logInfo(.nameEquivalence, "➕ Adding equivalence: \(normalized1) ↔ \(normalized2)")
        
        // Add bidirectional equivalence
        addDirectionalEquivalence(from: normalized1, to: normalized2)
        addDirectionalEquivalence(from: normalized2, to: normalized1)
        
        // Ensure transitivity - if A=B and B=C, then A=C
        ensureTransitivity(for: normalized1)
        ensureTransitivity(for: normalized2)
        
        saveEquivalences()
        
        logDebug(.nameEquivalence, "✅ Equivalence added and saved")
    }
    
    /**
     * Remove name equivalence
     */
    func removeEquivalence(between name1: String, and name2: String) {
        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)
        
        logInfo(.nameEquivalence, "➖ Removing equivalence: \(normalized1) ↔ \(normalized2)")
        
        // Remove bidirectional equivalence
        equivalences[normalized1]?.remove(normalized2)
        equivalences[normalized2]?.remove(normalized1)
        
        // Clean up empty sets
        if equivalences[normalized1]?.isEmpty == true {
            equivalences.removeValue(forKey: normalized1)
        }
        if equivalences[normalized2]?.isEmpty == true {
            equivalences.removeValue(forKey: normalized2)
        }
        
        saveEquivalences()
        
        logDebug(.nameEquivalence, "✅ Equivalence removed and saved")
    }
    
    /**
     * Check if user has been asked about this name pair before
     */
    func hasBeenAskedAbout(_ name1: String, _ name2: String) -> Bool {
        // This could track which name pairs have been presented to the user
        // For now, return false to always ask
        return false
    }
    
    // MARK: - Helper Methods
    
    private func normalizeName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }
    
    private func addDirectionalEquivalence(from source: String, to target: String) {
        if equivalences[source] == nil {
            equivalences[source] = Set<String>()
        }
        equivalences[source]?.insert(target)
    }
    
    private func ensureTransitivity(for name: String) {
        guard let directEquivalents = equivalences[name] else { return }
        
        var allEquivalents = directEquivalents
        
        // For each direct equivalent, add all of its equivalents
        for equivalent in directEquivalents {
            if let indirectEquivalents = equivalences[equivalent] {
                allEquivalents.formUnion(indirectEquivalents)
            }
        }
        
        // Remove self-reference
        allEquivalents.remove(name)
        
        // Update if changed
        if allEquivalents != directEquivalents {
            equivalences[name] = allEquivalents
            
            // Recursively ensure transitivity for newly added equivalents
            for newEquivalent in allEquivalents.subtracting(directEquivalents) {
                addDirectionalEquivalence(from: newEquivalent, to: name)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveEquivalences() {
        do {
            // Convert to serializable format
            let serializable = equivalences.mapValues { Array($0) }
            let data = try JSONEncoder().encode(serializable)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            
            logTrace(.nameEquivalence, "💾 Equivalences saved to UserDefaults")
        } catch {
            logError(.nameEquivalence, "❌ Failed to save equivalences: \(error)")
        }
    }
    
    private func loadEquivalences() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            logDebug(.nameEquivalence, "No saved equivalences found")
            loadDefaultEquivalences()
            return
        }
        
        do {
            let serializable = try JSONDecoder().decode([String: [String]].self, from: data)
            equivalences = serializable.mapValues { Set($0) }
            
            logDebug(.nameEquivalence, "📂 Loaded \(equivalences.count) equivalence groups")
        } catch {
            logError(.nameEquivalence, "❌ Failed to load equivalences: \(error)")
            loadDefaultEquivalences()
        }
    }
    
    private func loadDefaultEquivalences() {
        logInfo(.nameEquivalence, "📚 Loading default Finnish name equivalences")
        
        // Common Finnish name equivalences
        let defaultPairs = [
            ("Liisa", "Elisabet"),
            ("Malin", "Magdalena"),
            ("Helena", "Leena"),
            ("Johan", "Juho"),
            ("Matti", "Matias"),
            ("Anna", "Annikki"),
            ("Kustaa", "Kustavi"),
            ("Brita", "Birgit"),
            ("Erik", "Erkki"),
            ("Henrik", "Heikki"),
            ("Margareta", "Marketta"),
            ("Kristina", "Kirstine"),
            ("Pietari", "Petrus")
        ]
        
        for (name1, name2) in defaultPairs {
            addEquivalence(between: name1, and: name2)
        }
        
        logInfo(.nameEquivalence, "✅ Loaded \(defaultPairs.count) default equivalences")
    }
    
    // MARK: - User Interaction Support
    
    /**
     * Generate user-friendly question for name equivalence
     */
    func generateEquivalenceQuestion(for name1: String, and name2: String) -> String {
        return "Are '\(name1)' and '\(name2)' the same person? (Common Finnish name variations)"
    }
    
    /**
     * Get suggestion confidence for name similarity
     */
    func getSimilarityConfidence(between name1: String, and name2: String) -> Double {
        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)
        
        // Exact match after normalization
        if normalized1 == normalized2 {
            return 1.0
        }
        
        // Known equivalence
        if areNamesEquivalent(name1, name2) {
            return 0.95
        }
        
        // Simple similarity metrics
        let similarity = calculateStringSimilarity(normalized1, normalized2)
        
        // Boost confidence for names that are likely Finnish variants
        if isLikelyFinnishVariant(normalized1, normalized2) {
            return min(similarity + 0.2, 1.0)
        }
        
        return similarity
    }
    
    private func calculateStringSimilarity(_ str1: String, _ str2: String) -> Double {
        // Simple Levenshtein distance-based similarity
        let maxLength = max(str1.count, str2.count)
        guard maxLength > 0 else { return 1.0 }
        
        let distance = levenshteinDistance(str1, str2)
        return 1.0 - (Double(distance) / Double(maxLength))
    }
    
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let array1 = Array(str1)
        let array2 = Array(str2)
        let m = array1.count
        let n = array2.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = array1[i-1] == array2[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    private func isLikelyFinnishVariant(_ name1: String, _ name2: String) -> Bool {
        // Simple heuristics for Finnish name patterns
        let commonPrefixes = ["erik", "johan", "kust", "mati"]
        let commonSuffixes = ["nen", "ina", "ta", "tti"]
        
        for prefix in commonPrefixes {
            if name1.hasPrefix(prefix) && name2.hasPrefix(prefix) {
                return true
            }
        }
        
        for suffix in commonSuffixes {
            if name1.hasSuffix(suffix) && name2.hasSuffix(suffix) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Debugging and Statistics
    
    func getEquivalenceStatistics() -> EquivalenceStatistics {
        return EquivalenceStatistics(
            totalGroups: equivalenceGroups.count,
            totalNames: totalEquivalences,
            averageGroupSize: equivalenceGroups.isEmpty ? 0 : Double(totalEquivalences) / Double(equivalenceGroups.count),
            largestGroupSize: equivalenceGroups.map { $0.count }.max() ?? 0
        )
    }
    
    func clearAllEquivalences() {
        logWarn(.nameEquivalence, "🗑️ Clearing all name equivalences")
        
        equivalences.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        
        logInfo(.nameEquivalence, "✅ All equivalences cleared")
    }
}

// MARK: - Supporting Structures

struct EquivalenceStatistics {
    let totalGroups: Int
    let totalNames: Int
    let averageGroupSize: Double
    let largestGroupSize: Int
    
    var description: String {
        return """
        Name Equivalence Statistics:
        - Total groups: \(totalGroups)
        - Total names: \(totalNames)
        - Average group size: \(String(format: "%.1f", averageGroupSize))
        - Largest group: \(largestGroupSize) names
        """
    }
}
