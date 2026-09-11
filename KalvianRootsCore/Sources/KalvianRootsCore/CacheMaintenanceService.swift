import CryptoKit
import Darwin
import Foundation

public enum CacheMaintenanceError: Error, LocalizedError, Sendable {
  case invalidScope, busy, desktopRunning, changed, recoveryRequired
  case malformed(String)
  public var code: String {
    switch self {
    case .invalidScope: "invalid_request"
    case .busy: "cache_busy"
    case .desktopRunning: "desktop_app_running"
    case .changed: "cache_changed"
    case .recoveryRequired: "cache_recovery_required"
    case .malformed: "cache_unreadable"
    }
  }
  public var errorDescription: String? {
    switch self {
    case .invalidScope: "Supply 1–10 distinct family IDs and a lowercase source SHA-256."
    case .busy: "Another MCP operation is using the local caches. Retry when it finishes."
    case .desktopRunning:
      "Close Kalvian Roots before applying a cache refresh; its loaded cache could overwrite the refresh."
    case .changed:
      "Source or cache files changed during preparation. Nothing further was installed."
    case .recoveryRequired:
      "An interrupted cache transaction needs recovery. Close Kalvian Roots and retry; externally changed files require manual recovery from the maintenance backup."
    case .malformed(let name): "Unsupported or malformed cache: \(name)."
    }
  }
}

/// Carries attempted AI calls through failed staging/installation for accurate MCP auditing.
public struct CacheRefreshFailure: Error, LocalizedError {
  public let cause: any Error
  public let deepSeekCalls: Int
  public var errorDescription: String? { cause.localizedDescription }
}

/// Held across a complete MCP call, including awaits. flock also coordinates separate hosts.
public final class CacheAccessLease: @unchecked Sendable {
  private let descriptor: Int32
  fileprivate init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw CacheMaintenanceError.busy }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      throw CacheMaintenanceError.busy
    }
  }
  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}

public struct CachedRevisionAudit: Codable, Sendable {
  public let key: String
  public let status: String
}
public struct FamilyCacheAudit: Codable, Sendable {
  public let familyId: String
  public let sourceSpan: SourceSpan
  public let nativeRecords: [CachedRevisionAudit]
  public let legacyNetworkIds: [String]
}
public struct CacheAuditReport: Codable, Sendable {
  public let sourceSHA256: String
  /// Stored network entries, not a count of canonical book families.
  public let totalLegacyNetworks: Int
  public let totalNativeRecords: Int
  public let families: [FamilyCacheAudit]
  public let dependentRecords: [String: [String]]
}
public enum CacheRefreshMode: String, Codable, Sendable { case cached, reparse }
public struct CacheRefreshReport: Codable, Sendable {
  public let status: String
  public let audit: CacheAuditReport
  public let refreshedFamilies: [ParsedFamilyRecord]
  public let changedNetworkIds: [String]
  public let changedFiles: [String]
  public let backupId: String?
  public let deepSeekCalls: Int
}

/// Filesystem maintenance only. Parsing and citation logic remain in their existing services.
public struct CacheMaintenanceService: Sendable {
  public static var defaultRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Kalvian Roots", isDirectory: true)
  }
  public let root: URL
  private let book: any BookTextServing
  private let ai: any FamilyAIResponding
  private let desktopIsRunning: @Sendable () throws -> Bool
  // Dependency order is also the usual invalidation order; fixed-point scanning handles back links.
  private static let stores: [(path: String, field: String, version: Int)] = [
    ("Cache/families.json", "families", 2),
    ("Cache/parsed-families-v1.json", "records", 1),
    ("Cache/person-contexts-v1.json", "contexts", 1),
    ("Research/family-comparisons.json", "records", 1),
    ("Research/citation-reviews-v1.json", "reviews", 1),
    ("Traversal/sessions-v1.json", "sessions", 1),
    ("Pilot/reports-v1.json", "reports", 1),
  ]
  public init(
    root: URL = Self.defaultRoot, book: any BookTextServing = BookTextService(),
    ai: any FamilyAIResponding = DeepSeekFamilyClient(),
    desktopIsRunning: @escaping @Sendable () throws -> Bool = Self.desktopAppIsRunning
  ) {
    self.root = root
    self.book = book
    self.ai = ai
    self.desktopIsRunning = desktopIsRunning
  }

  public static func desktopAppIsRunning() throws -> Bool {
    #if os(macOS)
      let process = Process()
      let pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: "/bin/ps")
      process.arguments = ["-axo", "comm="]
      process.standardOutput = pipe
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { throw CacheMaintenanceError.busy }
      return String(decoding: data, as: UTF8.self).contains(
        "/Contents/MacOS/Kalvian Roots")
    #else
      return false
    #endif
  }

  /// Other MCP tools acquire the same lease before accessing any persistent service.
  /// Recovery precedes access so no tool can observe a half-installed transaction.
  public func acquireAccess() throws -> CacheAccessLease {
    let lease = try CacheAccessLease(url: root.appendingPathComponent("Maintenance/access.lock"))
    try recoverIfNeeded()
    return lease
  }

  public func audit(familyIds: [String], expectedSourceSHA256: String) async throws
    -> CacheAuditReport
  {
    let lease = try acquireAccess()
    defer { withExtendedLifetime(lease) {} }
    let sources = try await sources(familyIds, expectedSourceSHA256)
    let snapshot = try readStores()
    let report = try audit(sources, snapshot)
    try await verifyUnchanged(snapshot, hash: expectedSourceSHA256)
    return report
  }

  public func refresh(
    familyIds: [String], expectedSourceSHA256: String,
    mode: CacheRefreshMode, dryRun: Bool
  ) async throws -> CacheRefreshReport {
    let lease = try acquireAccess()
    defer { withExtendedLifetime(lease) {} }
    let sources = try await sources(familyIds, expectedSourceSHA256)
    let before = try readStores()
    let auditReport = try audit(sources, before)
    if dryRun {
      try await verifyUnchanged(before, hash: expectedSourceSHA256)
      return CacheRefreshReport(
        status: "preview", audit: auditReport, refreshedFamilies: [],
        changedNetworkIds: [], changedFiles: [], backupId: nil, deepSeekCalls: 0)
    }
    guard try !desktopIsRunning() else { throw CacheMaintenanceError.desktopRunning }
    // Durable staging is never an active-cache fallback. A failed parse cannot partially refresh live data.
    let staging = root.appendingPathComponent("Maintenance/staging-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let native = NativeParsedFamilyCache(url: staging.appendingPathComponent("parsed.json"))
    if let data = before[Self.stores[1].path]?.data {
      try data.write(to: staging.appendingPathComponent("parsed.json"), options: .atomic)
    }
    let parser = FamilyParsingService(
      ai: ai, nativeCache: native,
      legacyCache: LegacyFamilyCacheReader(url: staging.appendingPathComponent("no-legacy.json")))
    var records: [ParsedFamilyRecord] = []
    var deepSeekCalls = 0
    do {
      for source in sources {
        if mode == .reparse { deepSeekCalls += 1 }
        // cached mode deliberately refuses provenance-limited legacy imports.
        let record = try await parser.parseFamily(
          source: source, cachePolicy: mode == .reparse ? .refresh : .cacheOnly)
        try FamilyParsingService.validateCachedRecord(record, against: source, allowLegacy: false)
        records.append(record)
      }
      let plan = try replacementPlan(
        before, records: records, dependencies: auditReport.dependentRecords)
      try await verifyUnchanged(before, hash: expectedSourceSHA256)
      guard try !desktopIsRunning() else { throw CacheMaintenanceError.desktopRunning }
      let backupId = try await install(
        before: before, after: plan.files, sourceSHA256: expectedSourceSHA256,
        familyIds: sources.map(\.familyId))
      return CacheRefreshReport(
        status: "refreshed", audit: auditReport, refreshedFamilies: records,
        changedNetworkIds: plan.networkIds, changedFiles: plan.files.keys.sorted(),
        backupId: backupId,
        deepSeekCalls: deepSeekCalls)
    } catch {
      if deepSeekCalls > 0 { throw CacheRefreshFailure(cause: error, deepSeekCalls: deepSeekCalls) }
      throw error
    }
  }

  private func sources(_ ids: [String], _ hash: String) async throws -> [FamilyTextRecord] {
    guard (1...10).contains(ids.count), Set(ids.map(Self.key)).count == ids.count,
      hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    else { throw CacheMaintenanceError.invalidScope }
    var result: [FamilyTextRecord] = []
    for id in ids {
      result.append(try await book.getFamilyText(familyId: id, expectedSourceSHA256: hash))
    }
    return result
  }

  private struct StoreSnapshot {
    let data: Data?
    var object: [String: Any]
  }
  private func readStores() throws -> [String: StoreSnapshot] {
    var result: [String: StoreSnapshot] = [:]
    for spec in Self.stores {
      let url = root.appendingPathComponent(spec.path)
      let data = try readOptional(url)
      let value =
        try data.map { try JSONSerialization.jsonObject(with: $0) }
        ?? ["schemaVersion": spec.version, spec.field: [String: Any]()]
      guard let object = value as? [String: Any], object["schemaVersion"] as? Int == spec.version,
        object[spec.field] is [String: Any]
      else { throw CacheMaintenanceError.malformed(spec.path) }
      result[spec.path] = StoreSnapshot(data: data, object: object)
    }
    return result
  }
  private func audit(_ sources: [FamilyTextRecord], _ files: [String: StoreSnapshot]) throws
    -> CacheAuditReport
  {
    let networks = files[Self.stores[0].path]!.object["families"] as! [String: Any]
    let native = files[Self.stores[1].path]!.object["records"] as! [String: Any]
    let families = try sources.map { source in
      let records = try native.keys.sorted().compactMap { key -> CachedRevisionAudit? in
        guard let object = native[key] as? [String: Any], let id = object["familyId"] as? String
        else {
          throw CacheMaintenanceError.malformed("parsed-family record")
        }
        guard Self.key(id) == Self.key(source.familyId) else { return nil }
        let record = try JSONDecoder().decode(ParsedFamilyRecord.self, from: Self.json(object))
        let status: String
        if record.source.sha256 != source.source.sha256 {
          status = "stale_source"
        } else {
          do {
            try FamilyParsingService.validateCachedRecord(
              record, against: source, allowLegacy: true)
            guard
              key
                == NativeParsedFamilyCache.key(
                  record.familyId, record.source.sha256, record.parserImplementationVersion)
            else { throw CacheMaintenanceError.malformed("parsed-family key") }
            status =
              record.parserImplementationVersion == "legacy-schema2-unknown"
              ? "legacy_provenance_limited" : "current"
          } catch { status = "invalid_or_obsolete" }
        }
        return CachedRevisionAudit(key: key, status: status)
      }
      let containers = networks.keys.filter {
        Self.containsFamily(networks[$0]!, ids: [Self.key(source.familyId)])
      }.sorted()
      return FamilyCacheAudit(
        familyId: source.familyId, sourceSpan: source.span,
        nativeRecords: records, legacyNetworkIds: containers)
    }
    return CacheAuditReport(
      sourceSHA256: sources[0].source.sha256,
      totalLegacyNetworks: networks.count, totalNativeRecords: native.count, families: families,
      dependentRecords: dependencies(files, ids: Set(sources.map { Self.key($0.familyId) })))
  }

  private func dependencies(_ files: [String: StoreSnapshot], ids: Set<String>) -> [String:
    [String]]
  {
    var found: [String: Set<String>] = [:]
    var references = ids
    var changed = true
    while changed {
      changed = false
      for spec in Self.stores.dropFirst(2) {
        let entries = files[spec.path]!.object[spec.field] as! [String: Any]
        for (key, value) in entries where !(found[spec.path] ?? []).contains(key) {
          if Self.references(value, ids: references) {
            found[spec.path, default: []].insert(key)
            references.insert(Self.key(key))
            if let object = value as? [String: Any] {
              for field in [
                "contextId", "comparisonId", "reviewId", "workupId", "sessionId", "pilotId",
              ] {
                if let id = object[field] as? String { references.insert(Self.key(id)) }
              }
            }
            changed = true
          }
        }
      }
    }
    return found.mapValues { $0.sorted() }
  }
  private static func references(_ value: Any, ids: Set<String>) -> Bool {
    if let text = value as? String { return ids.contains(key(text)) }
    if let object = value as? [String: Any] {
      return object.contains { ids.contains(key($0.key)) || references($0.value, ids: ids) }
    }
    if let array = value as? [Any] { return array.contains { references($0, ids: ids) } }
    return false
  }
  private static func containsFamily(_ value: Any, ids: Set<String>) -> Bool {
    if let object = value as? [String: Any] {
      if let id = object["familyId"] as? String, object["couples"] != nil, ids.contains(key(id)) {
        return true
      }
      return object.values.contains { containsFamily($0, ids: ids) }
    }
    if let array = value as? [Any] { return array.contains { containsFamily($0, ids: ids) } }
    return false
  }

  private func replacementPlan(
    _ before: [String: StoreSnapshot], records: [ParsedFamilyRecord],
    dependencies: [String: [String]]
  ) throws -> (files: [String: Data], networkIds: [String]) {
    var after = before
    let replacements = try Dictionary(
      uniqueKeysWithValues: records.map {
        (
          Self.key($0.familyId),
          try JSONSerialization.jsonObject(with: JSONEncoder().encode($0.parsedFamily))
        )
      })
    func replace(_ value: Any) -> Any {
      if let object = value as? [String: Any] {
        if let id = object["familyId"] as? String, object["couples"] != nil,
          let fresh = replacements[Self.key(id)]
        {
          return fresh
        }
        return object.mapValues(replace)
      }
      if let array = value as? [Any] { return array.map(replace) }
      return value
    }
    var networks = before[Self.stores[0].path]!.object["families"] as! [String: Any]
    var changedNetworks: [String] = []
    for id in networks.keys.sorted() {
      guard let old = networks[id] as? [String: Any], var entry = replace(old) as? [String: Any],
        var network = entry["network"] as? [String: Any]
      else { throw CacheMaintenanceError.malformed("network \(id)") }
      if let main = network["mainFamily"] as? [String: Any],
        let mainId = main["familyId"] as? String,
        let record = records.first(where: { Self.key($0.familyId) == Self.key(mainId) })
      {
        let parents = record.parsedFamily.couples.flatMap { [$0.husband, $0.wife] }
        let children = record.parsedFamily.couples.flatMap(\.children)
        let allowed = [
          "asChildFamilies": Set(parents.compactMap(\.asChild).map(Self.key)),
          "asParentFamilies": Set(children.compactMap(\.asParent).map(Self.key)),
          "spouseAsChildFamilies": Set(children.compactMap(\.spouseParentsFamilyId).map(Self.key)),
        ]
        for (field, permitted) in allowed {
          if let map = network[field] as? [String: Any] {
            network[field] = map.filter { _, value in
              guard let family = value as? [String: Any], let target = family["familyId"] as? String
              else { return false }
              return permitted.contains(Self.key(target))
            }
          }
        }
      }
      entry["network"] = network
      if try Self.json(entry) != Self.json(old) {
        entry["cachedAt"] = ISO8601DateFormatter().string(from: Date())
        entry["extractionTime"] = 0
        networks[id] = entry
        changedNetworks.append(id)
      }
    }
    // A new scoped family can be installed even if the desktop has never cached it.
    for record in records
    where !networks.keys.contains(where: { Self.key($0) == Self.key(record.familyId) }) {
      networks[Self.key(record.familyId)] = [
        "network": [
          "mainFamily": replacements[Self.key(record.familyId)]!,
          "asChildFamilies": [String: Any](), "asParentFamilies": [String: Any](),
          "spouseAsChildFamilies": [String: Any](),
        ],
        "cachedAt": ISO8601DateFormatter().string(from: Date()), "extractionTime": 0,
      ]
      changedNetworks.append(Self.key(record.familyId))
    }
    after[Self.stores[0].path]!.object["families"] = networks
    var native = before[Self.stores[1].path]!.object["records"] as! [String: Any]
    native = native.filter { _, value in
      guard let object = value as? [String: Any], let id = object["familyId"] as? String else {
        return true
      }
      return replacements[Self.key(id)] == nil
    }
    for record in records {
      let key = NativeParsedFamilyCache.key(
        record.familyId, record.source.sha256, record.parserImplementationVersion)
      native[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
    }
    after[Self.stores[1].path]!.object["records"] = native
    for spec in Self.stores.dropFirst(2) {
      var entries = after[spec.path]!.object[spec.field] as! [String: Any]
      for id in dependencies[spec.path] ?? [] { entries.removeValue(forKey: id) }
      after[spec.path]!.object[spec.field] = entries
    }
    var files: [String: Data] = [:]
    for spec in Self.stores
    where try Self.json(before[spec.path]!.object) != Self.json(after[spec.path]!.object) {
      files[spec.path] = try Self.json(after[spec.path]!.object)
    }
    return (files, changedNetworks.sorted())
  }

  private func verifyUnchanged(_ before: [String: StoreSnapshot], hash: String) async throws {
    guard try await book.loadSource().sha256 == hash else { throw CacheMaintenanceError.changed }
    for (path, snapshot) in before {
      guard try readOptional(root.appendingPathComponent(path)) == snapshot.data else {
        throw CacheMaintenanceError.changed
      }
    }
  }
  private struct Journal: Codable {
    let backupId: String
    let sourceSHA256: String
    let familyIds: [String]
    let entries: [Entry]
    struct Entry: Codable {
      let path: String
      let beforeSHA256: String?
      let afterSHA256: String
    }
  }
  private var journalURL: URL { root.appendingPathComponent("Maintenance/pending.json") }
  private func install(
    before: [String: StoreSnapshot], after: [String: Data], sourceSHA256: String,
    familyIds: [String]
  ) async throws -> String? {
    guard !after.isEmpty else { return nil }
    let id = UUID().uuidString.lowercased()
    let backup = root.appendingPathComponent("Maintenance/backups/\(id)")
    var entries: [Journal.Entry] = []
    for path in after.keys.sorted() {
      let old = before[path]!.data
      let new = after[path]!
      for (prefix, data) in [("before", old), ("after", Optional(new))] {
        if let data {
          let url = backup.appendingPathComponent("\(prefix)/\(path)")
          try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
          try data.write(to: url, options: .atomic)
        }
      }
      entries.append(.init(path: path, beforeSHA256: old.map(Self.sha), afterSHA256: Self.sha(new)))
    }
    let journal = Journal(
      backupId: id, sourceSHA256: sourceSHA256, familyIds: familyIds, entries: entries)
    let encoded = try JSONEncoder().encode(journal)
    try encoded.write(to: backup.appendingPathComponent("manifest.json"), options: .atomic)
    try encoded.write(to: journalURL, options: .atomic)
    do {
      guard try await book.loadSource().sha256 == sourceSHA256 else { throw CacheMaintenanceError.changed }
      guard try !desktopIsRunning() else { throw CacheMaintenanceError.desktopRunning }
      for entry in entries {
        let url = root.appendingPathComponent(entry.path)
        guard try readOptional(url).map(Self.sha) == entry.beforeSHA256 else {
          throw CacheMaintenanceError.changed
        }
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try after[entry.path]!.write(to: url, options: .atomic)
        guard try Self.sha(Data(contentsOf: url)) == entry.afterSHA256 else {
          throw CacheMaintenanceError.changed
        }
      }
      guard try await book.loadSource().sha256 == sourceSHA256 else { throw CacheMaintenanceError.changed }
      try FileManager.default.removeItem(at: journalURL)
      return id
    } catch {
      // If rollback encounters external edits it leaves the journal and blocks subsequent MCP calls.
      try recoverIfNeeded()
      throw error
    }
  }
  private func recoverIfNeeded() throws {
    guard let data = try readOptional(journalURL) else { return }
    guard try !desktopIsRunning() else { throw CacheMaintenanceError.recoveryRequired }
    let journal = try JSONDecoder().decode(Journal.self, from: data)
    guard UUID(uuidString: journal.backupId) != nil,
      Set(journal.entries.map(\.path)).count == journal.entries.count,
      journal.entries.allSatisfy({ entry in Self.stores.contains { $0.path == entry.path } })
    else { throw CacheMaintenanceError.recoveryRequired }
    let backup = root.appendingPathComponent("Maintenance/backups/\(journal.backupId)/before")
    // Validate every file and backup before rolling any file back.
    for entry in journal.entries {
      let current = try readOptional(root.appendingPathComponent(entry.path)).map(Self.sha)
      guard current == entry.beforeSHA256 || current == entry.afterSHA256,
        try readOptional(backup.appendingPathComponent(entry.path)).map(Self.sha)
          == entry.beforeSHA256
      else { throw CacheMaintenanceError.recoveryRequired }
    }
    for entry in journal.entries {
      let url = root.appendingPathComponent(entry.path)
      if let original = try readOptional(backup.appendingPathComponent(entry.path)) {
        try original.write(to: url, options: .atomic)
      } else if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }
    try FileManager.default.removeItem(at: journalURL)
  }
  private func readOptional(_ url: URL) throws -> Data? {
    do { return try Data(contentsOf: url) } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    { return nil }
  }
  private static func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
  }
  private static func sha(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private static func key(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
      in: CharacterSet(charactersIn: "{}")
    )
    .split(whereSeparator: \.isWhitespace).joined(separator: " ").uppercased()
  }
}
