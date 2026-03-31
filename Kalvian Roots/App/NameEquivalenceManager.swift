import Foundation

/**
 * NameEquivalenceManager
 *
 * Learns and manages Finnish name equivalences for genealogical matching.
 *
 * Examples:
 *   Liisa ↔ Elisabet
 *   Johan ↔ Juho
 *   Matti ↔ Matias
 *
 * The system supports:
 * - bidirectional equivalence
 * - transitive equivalence groups
 * - persistent user learning
 * - deterministic canonical name generation
 */

@Observable
class NameEquivalenceManager {

    // MARK: - Properties

    private var equivalences: [String: Set<String>] = [:]

    private let userDefaultsKey = "NameEquivalences"
    private let userDefaultsVersionKey = "NameEquivalencesVersion"

    private let currentVersion = 4


    // MARK: - Computed Properties

    var totalEquivalences: Int {
        equivalences.values.reduce(0) { $0 + $1.count }
    }

    var equivalenceGroups: [[String]] {

        var processed: Set<String> = []
        var groups: [[String]] = []

        for (name, equivalentNames) in equivalences {

            if !processed.contains(name) {

                let group = [name] + Array(equivalentNames)
                groups.append(group.sorted())

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
     Check if two names are equivalent
     */
    func areNamesEquivalent(_ name1: String, _ name2: String) -> Bool {

        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)

        if normalized1 == normalized2 {
            return true
        }

        if let equivalents = equivalences[normalized1] {
            return equivalents.contains(normalized2)
        }

        return false
    }


    /**
     Return all equivalent names for a given name
     */
    func getEquivalentNames(for name: String) -> Set<String> {

        let normalized = normalizeName(name)

        var allEquivalents: Set<String> = [normalized]

        if let directEquivalents = equivalences[normalized] {

            allEquivalents.formUnion(directEquivalents)

            for equivalent in directEquivalents {

                if let indirectEquivalents = equivalences[equivalent] {
                    allEquivalents.formUnion(indirectEquivalents)
                }
            }
        }

        return allEquivalents
    }


    /**
     Deterministic canonical name used by PersonIdentity
     */
    func canonicalName(for name: String) -> String {

        let normalized = normalizeName(name)

        var all = getEquivalentNames(for: normalized)

        all.insert(normalized)

        return all.sorted().first!
    }


    /**
     Add equivalence (bidirectional)
     */
    func addEquivalence(between name1: String, and name2: String) {

        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)

        logInfo(.nameEquivalence, "➕ Adding equivalence: \(normalized1) ↔ \(normalized2)")

        addDirectionalEquivalence(from: normalized1, to: normalized2)
        addDirectionalEquivalence(from: normalized2, to: normalized1)

        ensureTransitivity(for: normalized1)
        ensureTransitivity(for: normalized2)

        saveEquivalences()

        logDebug(.nameEquivalence, "✅ Equivalence added and saved")
    }


    /**
     Remove equivalence
     */
    func removeEquivalence(between name1: String, and name2: String) {

        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)

        logInfo(.nameEquivalence, "➖ Removing equivalence: \(normalized1) ↔ \(normalized2)")

        equivalences[normalized1]?.remove(normalized2)
        equivalences[normalized2]?.remove(normalized1)

        if equivalences[normalized1]?.isEmpty == true {
            equivalences.removeValue(forKey: normalized1)
        }

        if equivalences[normalized2]?.isEmpty == true {
            equivalences.removeValue(forKey: normalized2)
        }

        saveEquivalences()

        logDebug(.nameEquivalence, "✅ Equivalence removed and saved")
    }


    // MARK: - Helper Methods

    private func normalizeName(_ name: String) -> String {

        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

        for equivalent in directEquivalents {

            if let indirectEquivalents = equivalences[equivalent] {
                allEquivalents.formUnion(indirectEquivalents)
            }
        }

        allEquivalents.remove(name)

        if allEquivalents != directEquivalents {

            equivalences[name] = allEquivalents

            for newEquivalent in allEquivalents.subtracting(directEquivalents) {
                addDirectionalEquivalence(from: newEquivalent, to: name)
            }
        }
    }


    // MARK: - Persistence

    private func saveEquivalences() {

        do {

            let serializable = equivalences.mapValues { Array($0) }

            let data = try JSONEncoder().encode(serializable)

            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            UserDefaults.standard.set(currentVersion, forKey: userDefaultsVersionKey)

            logTrace(.nameEquivalence, "💾 Equivalences saved")

        } catch {

            logError(.nameEquivalence, "❌ Failed to save equivalences: \(error)")
        }
    }


    private func loadEquivalences() {

        let savedVersion = UserDefaults.standard.integer(forKey: userDefaultsVersionKey)

        guard savedVersion == currentVersion,
              let data = UserDefaults.standard.data(forKey: userDefaultsKey)
        else {

            loadDefaultEquivalences()

            UserDefaults.standard.set(currentVersion, forKey: userDefaultsVersionKey)

            return
        }

        do {

            let serializable = try JSONDecoder().decode([String: [String]].self, from: data)

            equivalences = serializable.mapValues { Set($0) }

            logDebug(.nameEquivalence, "📂 Loaded equivalences")

        } catch {

            logError(.nameEquivalence, "❌ Failed to load equivalences: \(error)")

            loadDefaultEquivalences()

            UserDefaults.standard.set(currentVersion, forKey: userDefaultsVersionKey)
        }
    }


    private func loadDefaultEquivalences() {

        logInfo(.nameEquivalence, "📚 Loading default Finnish name equivalences")

        let defaultPairs = [

            ("Liisa", "Elisabet"),
            ("Liisa", "Elis."),
            ("Malin", "Magdalena"),
            ("Helena", "Leena"),
            ("Johan", "Juho"),
            ("Juho", "Johannes"),
            ("Matti", "Matias"),
            ("Matti", "Matts"),
            ("Anna", "Annikki"),
            ("Kustaa", "Kustavi"),
            ("Brita", "Birgit"),
            ("Brita", "Briita"),
            ("Erik", "Erkki"),
            ("Henrik", "Heikki"),
            ("Margareta", "Marketta"),
            ("Kristina", "Kirstine"),
            ("Pietari", "Petrus"),
            ("Antti", "Anders")
        ]
        for (name1, name2) in defaultPairs {
            addEquivalence(between: name1, and: name2)
        }

        logInfo(.nameEquivalence, "✅ Loaded \(defaultPairs.count) default equivalences")
    }


    // MARK: - User Interaction Support

    func generateEquivalenceQuestion(for name1: String, and name2: String) -> String {

        "Are '\(name1)' and '\(name2)' the same person? (Common Finnish name variations)"
    }


    // MARK: - Debugging

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

        """
        Name Equivalence Statistics:
        - Total groups: \(totalGroups)
        - Total names: \(totalNames)
        - Average group size: \(String(format: "%.1f", averageGroupSize))
        - Largest group: \(largestGroupSize) names
        """
    }
}
