import Foundation
import KalvianRootsCore
import Vapor

struct CachedFamilyEntry {
    var id: String
    var rawText: String
    var family: Family?
    var network: FamilyNetwork?
    var networkReady: Bool
    var processing: Bool
}

enum CoreStateError: Error, LocalizedError {
    case noActiveFamily
    case networkProcessing
    case networkNotReady
    case personNotFound

    var errorDescription: String? {
        switch self {
        case .noActiveFamily:
            return "No active family selected"
        case .networkProcessing:
            return "Family network still processing"
        case .networkNotReady:
            return "Family network is not ready"
        case .personNotFound:
            return "Person not found in the current family"
        }
    }
}

struct CoreSettings: Codable {
    var selectedModel: String
    var lastDisplayedFamilyID: String?
}

@MainActor
actor CoreState {
    private var cache: [String: CachedFamilyEntry] = [:]
    private var selectedModel: String
    private var currentFamilyID: String?
    private let settingsURL: URL
    private let logger: Logger

    private let parser: FamilyParsingService
    private let fileManager: FamilyFileManaging
    private let networkCache: FamilyNetworkCache
    private let nameEquivalenceManager = NameEquivalenceManager()

    init(
        settingsURL: URL,
        logger: Logger,
        parser: FamilyParsingService,
        fileManager: FamilyFileManaging,
        networkCache: FamilyNetworkCache = FamilyNetworkCache()
    ) {
        self.settingsURL = settingsURL
        self.logger = logger
        self.parser = parser
        self.fileManager = fileManager
        self.networkCache = networkCache

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

    func getSelectedModel() -> String { selectedModel }

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
        var entry = cache[trimmedID] ?? CachedFamilyEntry(id: trimmedID, rawText: rawText, family: nil, network: nil, networkReady: false, processing: false)
        entry.rawText = rawText
        cache[trimmedID] = entry
        currentFamilyID = trimmedID
        persistSettings()
        startProcessingIfNeeded(familyId: trimmedID)
    }

    private func startProcessingIfNeeded(familyId: String) {
        guard var entry = cache[familyId] else { return }
        guard !entry.networkReady else { return }
        guard !entry.processing else { return }

        entry.processing = true
        cache[familyId] = entry

        Task { [weak self] in
            await self?.processFamilyNetwork(familyId: familyId)
        }
    }

    private func processFamilyNetwork(familyId: String) async {
        guard var entry = cache[familyId] else { return }
        let startTime = Date()

        do {
            let family = try await parser.parseFamily(familyId: familyId, familyText: entry.rawText)
            let resolver = FamilyResolver(
                aiParsingService: parser,
                nameEquivalenceManager: nameEquivalenceManager,
                fileManager: fileManager,
                familyNetworkCache: networkCache
            )
            let workflow = FamilyNetworkWorkflow(
                nuclearFamily: family,
                familyResolver: resolver,
                resolveCrossReferences: true
            )

            try await workflow.process()
            let network = workflow.getFamilyNetwork() ?? FamilyNetwork(mainFamily: family)
            let extractionTime = Date().timeIntervalSince(startTime)
            networkCache.cacheNetwork(network, extractionTime: extractionTime)

            entry.family = family
            entry.network = network
            entry.networkReady = true
            entry.processing = false
            cache[familyId] = entry
            logger.info("[Core] Network ready for family \(familyId)")
        } catch {
            logger.error("[Core] Failed to process family \(familyId): \(error.localizedDescription)")
            entry.processing = false
            cache[familyId] = entry
        }
    }

    // MARK: - Status helpers

    func statusForCurrentFamily() -> CacheStatusResponse {
        guard let current = currentFamilyID, let entry = cache[current] else {
            return CacheStatusResponse(familyId: nil, processing: false, ready: false, status: "idle")
        }

        if entry.networkReady {
            return CacheStatusResponse(familyId: current, processing: false, ready: true, status: "ready")
        }

        if entry.processing {
            return CacheStatusResponse(familyId: current, processing: true, ready: false, status: "processing")
        }

        return CacheStatusResponse(familyId: current, processing: false, ready: false, status: "pending")
    }

    func currentFamily() -> CachedFamilyEntry? {
        guard let id = currentFamilyID else { return nil }
        return cache[id]
    }

    // MARK: - Citation

    func generateCitation(name: String, birth: String) throws -> String {
        guard let entry = currentFamily(), let family = entry.family else {
            throw CoreStateError.noActiveFamily
        }

        guard let network = entry.network else {
            throw entry.processing ? CoreStateError.networkProcessing : CoreStateError.networkNotReady
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBirth = birth.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let targetPerson = findPerson(in: family, name: trimmedName, birth: trimmedBirth) else {
            throw CoreStateError.personNotFound
        }

        if let asChildFamily = network.getAsChildFamily(for: targetPerson) {
            return CitationGenerator.generateAsChildCitation(
                for: targetPerson,
                in: asChildFamily,
                network: network,
                nameEquivalenceManager: nameEquivalenceManager
            )
        }

        if let spouseAsChildFamily = network.getSpouseAsChildFamily(for: targetPerson) {
            return CitationGenerator.generateSpouseAsChildCitation(
                spouseName: targetPerson.displayName,
                in: spouseAsChildFamily
            )
        }

        return CitationGenerator.generateMainFamilyCitation(
            family: family,
            targetPerson: targetPerson,
            network: network,
            nameEquivalenceManager: nameEquivalenceManager
        )
    }

    private func findPerson(in family: Family, name: String, birth: String) -> Person? {
        let children = family.couples.flatMap { $0.children }
        let candidates = family.allParents + children

        let normalizedSearchName = name.lowercased()
        let birthToken = birth.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer matches that include birth information when provided
        if !birthToken.isEmpty {
            if let match = candidates.first(where: { person in
                guard let personBirth = person.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines), !personBirth.isEmpty else { return false }
                let birthMatches = personBirth.contains(birthToken)
                let nameMatches = nameEquivalenceManager.areNamesEquivalent(person.name, normalizedSearchName) || person.displayName.lowercased().contains(normalizedSearchName)
                return birthMatches && nameMatches
            }) {
                return match
            }
        }

        // Fallback: name-only match
        return candidates.first(where: { person in
            nameEquivalenceManager.areNamesEquivalent(person.name, normalizedSearchName) ||
            person.displayName.lowercased().contains(normalizedSearchName)
        })
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
        networkCache.deleteCachedFamily(familyId: id)
        if currentFamilyID == id {
            currentFamilyID = nil
        }
        persistSettings()
    }

    func clearAllFamilies() {
        cache.removeAll()
        currentFamilyID = nil
        networkCache.clearCache()
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
