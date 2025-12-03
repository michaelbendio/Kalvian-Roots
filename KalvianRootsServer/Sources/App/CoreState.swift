import Foundation
import KalvianRootsCore
import Vapor

struct CachedFamily: Codable {
    var id: String
    var rawText: String
    var networkReady: Bool
    var processing: Bool
    var cachedJSON: [String: String]
}

enum CoreStateError: Error, LocalizedError {
    case noActiveFamily
    case networkProcessing
    case personNotFound
    case ambiguousMatch

    var errorDescription: String? {
        switch self {
        case .noActiveFamily:
            return "No active family selected"
        case .networkProcessing:
            return "Family network still processing"
        case .personNotFound:
            return "Person not found in the current family"
        case .ambiguousMatch:
            return "Multiple matching people found; provide birth information"
        }
    }
}

struct ParsedPerson: Equatable {
    enum Role { case parent, child }

    let name: String
    let birth: String
    let role: Role
    let line: String
}

struct ParsedFamily {
    let id: String
    let persons: [ParsedPerson]
}

struct CoreSettings: Codable {
    var selectedModel: String
    var lastDisplayedFamilyID: String?
}

actor CoreState {
    private var cache: [String: CachedFamily] = [:]
    private var selectedModel: String
    private var currentFamilyID: String?
    private let settingsURL: URL
    private let logger: Logger

    init(settingsURL: URL, logger: Logger) {
        self.settingsURL = settingsURL
        self.logger = logger

        let (model, lastFamily) = CoreState.loadSettings(from: settingsURL) ?? ("DeepSeek", nil)
        self.selectedModel = model
        self.currentFamilyID = lastFamily
    }

    // MARK: - Settings

    private static func loadSettings(from url: URL) -> (String, String?)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        guard let settings = try? decoder.decode(CoreSettings.self, from: data) else { return nil }
        return (settings.selectedModel, settings.lastDisplayedFamilyID)
    }

    private func persistSettings() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let settings = CoreSettings(selectedModel: selectedModel, lastDisplayedFamilyID: currentFamilyID)
        do {
            let data = try encoder.encode(settings)
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            logger.error("Failed to persist settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Model selection

    func getSelectedModel() -> String {
        selectedModel
    }

    func updateModel(_ model: String) {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        selectedModel = model
        persistSettings()
        startModelIfNeeded()
    }

    private func startModelIfNeeded() {
        if selectedModel.lowercased().contains("mlx") {
            logger.info("[Core] Auto-start requested for MLX model: \(selectedModel)")
        }
    }

    // MARK: - Family cache lifecycle

    func displayFamily(id: String, rawText: String) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = cache[trimmedID] ?? CachedFamily(id: trimmedID, rawText: rawText, networkReady: false, processing: false, cachedJSON: [:])
        entry.rawText = rawText
        cache[trimmedID] = entry
        currentFamilyID = trimmedID
        persistSettings()
        startProcessingIfNeeded(familyId: trimmedID)
    }

    func startProcessingIfNeeded(familyId: String) {
        guard var entry = cache[familyId] else { return }
        guard !entry.networkReady else { return }
        guard !entry.processing else { return }

        entry.processing = true
        cache[familyId] = entry

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await self?.completeProcessing(for: familyId)
        }
    }

    private func completeProcessing(for familyId: String) {
        guard var entry = cache[familyId] else { return }
        entry.cachedJSON = ["familyId": familyId, "summary": "Cached network for \(familyId)"]
        entry.networkReady = true
        entry.processing = false
        cache[familyId] = entry
        logger.info("[Core] Network ready for family \(familyId)")
    }

    // MARK: - Status helpers

    func statusForCurrentFamily() -> CacheStatusResponse {
        guard let current = currentFamilyID, let entry = cache[current] else {
            return CacheStatusResponse(familyId: nil, processing: false, ready: false, status: "idle")
        }

        if entry.networkReady {
            return CacheStatusResponse(familyId: current, processing: false, ready: true, status: "ready")
        }

        return CacheStatusResponse(familyId: current, processing: true, ready: false, status: "processing")
    }

    func cachedFamily(id: String) -> CachedFamily? {
        cache[id]
    }

    func currentFamily() -> CachedFamily? {
        guard let id = currentFamilyID else { return nil }
        return cache[id]
    }

    // MARK: - Citation

    private func parseFamily(_ family: CachedFamily) -> ParsedFamily {
        let lines = family.rawText.split(separator: "\n", omittingEmptySubsequences: false)
        var persons: [ParsedPerson] = []

        let nameRegex = try! NSRegularExpression(
            pattern: "\\b[\\p{Lu}][\\p{Ll}]+(?:\\s+[\\p{Lu}][\\p{Ll}]+)+",
            options: [.caseInsensitive]
        )

        for (index, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = nameRegex.matches(in: String(line), range: range)
            guard let match = matches.first else { continue }

            let name = nsLine.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            let birth = extractBirth(from: String(line))
            let role: ParsedPerson.Role = index <= 2 ? .parent : .child
            persons.append(ParsedPerson(name: name, birth: birth, role: role, line: String(line)))
        }

        return ParsedFamily(id: family.id, persons: persons)
    }

    private func extractBirth(from line: String) -> String {
        if let starRange = line.range(of: "★\\s*([^\\s]+)", options: .regularExpression) {
            return String(line[starRange]).replacingOccurrences(of: "★", with: "").trimmingCharacters(in: .whitespaces)
        }

        if let dateRange = line.range(of: "\\b\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}\\b", options: .regularExpression) {
            return String(line[dateRange])
        }

        if let yearRange = line.range(of: "\\b\\d{4}\\b", options: .regularExpression) {
            return String(line[yearRange])
        }

        return ""
    }

    func generateCitation(name: String, birth: String) throws -> String {

        guard let family = currentFamily else {
            throw CoreStateError.noActiveFamily
        }

        guard let network = cachedFamilyNetwork else {
            throw CoreStateError.networkNotReady
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBirth = birth.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Find the target person in the CURRENT nuclear family
        guard let targetPerson = family.findPerson(
            name: trimmedName,
            birthDate: trimmedBirth
        ) else {
            throw CoreStateError.personNotFound
        }

        // 2. CHILD CASE → as-child citation
        if let asChildFamilyID = targetPerson.asChild,
           let asChildFamily = network.families[asChildFamilyID] {

            return CitationGenerator.generateAsChildCitation(
                for: targetPerson,
                in: asChildFamily,
                network: network,
                nameEquivalenceManager: nameEquivalenceManager
            )
        }

        // 3. SPOUSE CASE → spouse as-child citation
        if let spouseFamilyID = network.getSpouseAsChildFamilyID(for: targetPerson),
           let spouseFamily = network.families[spouseFamilyID] {

            return CitationGenerator.generateSpouseAsChildCitation(
                for: targetPerson,
                in: spouseFamily,
                network: network
            )
        }

        // 4. PARENT / MAIN FAMILY CASE
        return CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: targetPerson,
            network: network,
            nameEquivalenceManager: nameEquivalenceManager
        )
    }
    // MARK: - Cache listing

    func groupedCacheList() -> [String: [String]] {
        let families = cache.values
            .filter { $0.networkReady }
            .map { $0.id }
            .sorted()

        var grouped: [String: [String]] = [:]

        for id in families {
            let prefix = id.split(separator: " ").first.map { String($0).uppercased() } ?? id.uppercased()
            grouped[prefix, default: []].append(id)
        }

        return grouped
    }

    func removeFamily(id: String) {
        cache.removeValue(forKey: id)
        if currentFamilyID == id {
            currentFamilyID = nil
        }
        persistSettings()
    }

    func clearAllFamilies() {
        cache.removeAll()
        currentFamilyID = nil
        persistSettings()
    }
}

struct CacheStatusResponse: Content {
    let familyId: String?
    let processing: Bool
    let ready: Bool
    let status: String
}

struct CitationPayload: Content {
    let citation: String
}

extension Application {
    private struct CoreStateKey: StorageKey { static let service = "CoreState"; typealias Value = CoreState }

    var coreState: CoreState {
        get {
            if let existing = storage[CoreStateKey.self] {
                return existing
            }
            fatalError("CoreState not configured")
        }
        set { storage[CoreStateKey.self] = newValue }
    }
}
