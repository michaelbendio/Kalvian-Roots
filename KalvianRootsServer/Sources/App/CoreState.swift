import Foundation
import Vapor

struct CachedFamily: Codable {
    var id: String
    var rawText: String
    var networkReady: Bool
    var processing: Bool
    var cachedJSON: [String: String]
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

    func generateCitation(name: String, birth: String) throws -> CitationPayload {
        guard let current = currentFamilyID else {
            throw Abort(.badRequest, reason: "No family is currently displayed.")
        }

        guard let entry = cache[current], entry.networkReady else {
            throw Abort(.conflict, reason: "Family network is still processing.")
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw Abort(.badRequest, reason: "Person name is required.")
        }

        let birthDisplay = birth.trimmingCharacters(in: .whitespacesAndNewlines)
        let citationText = "Citation for \(cleanName) (birth: \(birthDisplay.isEmpty ? "unknown" : birthDisplay)) in family \(current). Source: Juuret Kälviällä."

        return CitationPayload(personName: cleanName, birth: birthDisplay, citation: citationText)
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
    let personName: String
    let birth: String
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
