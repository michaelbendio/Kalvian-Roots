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
    private var userEquivalencePairs: Set<NamePair> = []

    private let userDefaultsKey = "UserNameEquivalences"


    // MARK: - Computed Properties

    var totalEquivalences: Int {
        equivalences.values.reduce(0) { $0 + $1.count }
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
        let tokens = tokenizeName(name)
        guard !tokens.isEmpty else {
            return ""
        }

        return tokens.map(canonicalTokenName(for:)).joined(separator: " ")
    }


    /**
     Add equivalence (bidirectional)
     */
    func addEquivalence(between name1: String, and name2: String) {

        let normalized1 = normalizeName(name1)
        let normalized2 = normalizeName(name2)

        logInfo(.nameEquivalence, "➕ Adding equivalence: \(normalized1) ↔ \(normalized2)")

        addEquivalenceToGraph(normalized1, normalized2)
        userEquivalencePairs.insert(NamePair(normalized1, normalized2))

        saveEquivalences()

        logDebug(.nameEquivalence, "✅ Equivalence added and saved")
    }


    // MARK: - Helper Methods

    private func normalizeName(_ name: String) -> String {
        tokenizeName(name).joined(separator: " ")
    }

    private func tokenizeName(_ name: String) -> [String] {
        name
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(normalizeToken)
            .filter { !$0.isEmpty }
    }

    private func normalizeToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private func canonicalTokenName(for token: String) -> String {
        let normalized = normalizeToken(token)
        guard !normalized.isEmpty else {
            return ""
        }

        let all = getEquivalentNames(for: normalized)

        return all.sorted().first!
    }


    private func addEquivalenceToGraph(_ normalized1: String, _ normalized2: String) {
        addDirectionalEquivalence(from: normalized1, to: normalized2)
        addDirectionalEquivalence(from: normalized2, to: normalized1)

        ensureTransitivity(for: normalized1)
        ensureTransitivity(for: normalized2)
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

            let serializable = userEquivalencePairs.sorted()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]

            let data = try encoder.encode(serializable)

            UserDefaults.standard.set(data, forKey: userDefaultsKey)

            logTrace(.nameEquivalence, "💾 User equivalences saved")

        } catch {

            logError(.nameEquivalence, "❌ Failed to save user equivalences: \(error)")
        }
    }


    private func loadEquivalences() {

        equivalences.removeAll()
        userEquivalencePairs.removeAll()

        loadDefaultEquivalences()
        loadUserEquivalences()
    }


    private func loadUserEquivalences() {

        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {

            return
        }

        do {

            let savedPairs = try JSONDecoder().decode([NamePair].self, from: data)

            userEquivalencePairs = Set(savedPairs)

            for pair in userEquivalencePairs.sorted() {
                addEquivalenceToGraph(pair.first, pair.second)
            }

            logDebug(.nameEquivalence, "📂 Loaded \(userEquivalencePairs.count) user equivalences")

        } catch {

            logError(.nameEquivalence, "❌ Failed to load user equivalences: \(error)")
        }
    }


    private func loadDefaultEquivalences() {

        logInfo(.nameEquivalence, "📚 Loading default Finnish name equivalences")

        let defaultPairs = [

            ("Liisa", "Elisabet"),
            ("Liisa", "Elis."),
            ("Maija", "Maria"),
            ("Malin", "Magdalena"),
            ("Helena", "Leena"),
            ("Tuomas", "Thomas"),
            ("Johan", "Juho"),
            ("Juho", "Johannes"),
            ("Matti", "Matias"),
            ("Matti", "Matts"),
            ("Matti", "Matthias"),
            ("Mikko", "Michel"),
            ("Anna", "Annika"),
            ("Kaisa", "Caisa"),
            ("Kustaa", "Kustavi"),
            ("Kustaa", "Gustav"),
            ("Brita", "Birgit"),
            ("Brita", "Briita"),
            ("Brita", "Britha"),
            ("Erik", "Erkki"),
            ("Erik", "Ericus"),
            ("Jaakko", "Jacob"),
            ("Kaarin", "Carin"),
            ("Henrik", "Heikki"),
            ("Henrik", "Henric"),
            ("Henrik", "Hinric"),
            ("Margareta", "Marketta"),
            ("Kristina", "Kirstine"),
            ("Pietari", "Petrus"),
            ("Pietari", "Per"),
            ("Antti", "Anders"),
            ("Antti", "Andreas"),
            ("Elisabet", "Elisabeth"),
            ("Abraham", "Abram")
        ]
        for (name1, name2) in defaultPairs {
            addEquivalenceToGraph(normalizeName(name1), normalizeName(name2))
        }

        logInfo(.nameEquivalence, "✅ Loaded \(defaultPairs.count) default equivalences")
    }


    // MARK: - Debugging

    func clearAllEquivalences() {

        logWarn(.nameEquivalence, "🗑️ Clearing all name equivalences")

        userEquivalencePairs.removeAll()
        equivalences.removeAll()

        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        loadDefaultEquivalences()

        logInfo(.nameEquivalence, "✅ User equivalences cleared")
    }
}

private struct NamePair: Codable, Hashable, Comparable {
    let first: String
    let second: String

    private enum CodingKeys: String, CodingKey {
        case first
        case second
    }

    init(_ name1: String, _ name2: String) {
        if name1 <= name2 {
            first = name1
            second = name2
        } else {
            first = name2
            second = name1
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let first = try container.decode(String.self, forKey: .first)
        let second = try container.decode(String.self, forKey: .second)
        self.init(first, second)
    }

    static func < (lhs: NamePair, rhs: NamePair) -> Bool {
        if lhs.first == rhs.first {
            return lhs.second < rhs.second
        }

        return lhs.first < rhs.first
    }
}
